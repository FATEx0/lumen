#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESTART_SH="$ROOT/lua/restart_steam.sh"

if [ ! -f "$RESTART_SH" ]; then
  echo "FAIL: restart helper is missing" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.local/share/SLSsteam/path"

write_systemctl() {
  local mode="$1"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${TEST_SYSTEMCTL_MODE:-}" in' \
    '  steamos)' \
    '    [[ "$*" == *"is-active --quiet steam-launcher.service"* ]] && exit 0' \
    '    ;;' \
    '  gamescope)' \
    '    [[ "$*" == *"is-active --quiet steam-launcher.service"* ]] && exit 1' \
    '    [[ "$*" == *"list-units"* ]] && {' \
    '      echo "gamescope-session-plus@steam.service loaded active running Gamescope"' \
    '      exit 0' \
    '    }' \
    '    ;;' \
    '  desktop)' \
    '    [[ "$*" == *"is-active --quiet steam-launcher.service"* ]] && exit 1' \
    '    [[ "$*" == *"list-units"* ]] && exit 0' \
    '    ;;' \
    'esac' \
    'exit 1' >"$TMP/bin/systemctl"
  chmod +x "$TMP/bin/systemctl"
  export TEST_SYSTEMCTL_MODE="$mode"
}

write_systemctl steamos
HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" \
  bash "$RESTART_SH" --check
result="$(
  HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" SLS_RESTART_DRYRUN=1 \
    bash "$RESTART_SH"
)"
[[ "$result" == "unit:steam-launcher.service" ]] || {
  echo "FAIL: SteamOS unit decision: $result" >&2
  exit 1
}

write_systemctl gamescope
HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" \
  bash "$RESTART_SH" --check
result="$(
  HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" SLS_RESTART_DRYRUN=1 \
    bash "$RESTART_SH"
)"
[[ "$result" == "unit:gamescope-session-plus@steam.service" ]] || {
  echo "FAIL: gamescope unit decision: $result" >&2
  exit 1
}

write_systemctl desktop
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
  >"$TMP/home/.local/share/SLSsteam/path/steam"
chmod +x "$TMP/home/.local/share/SLSsteam/path/steam"
HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" \
  bash "$RESTART_SH" --check
result="$(
  HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" SLS_RESTART_DRYRUN=1 \
    bash "$RESTART_SH"
)"
[[ "$result" == "desktop:$TMP/home/.local/share/SLSsteam/path/steam" ]] || {
  echo "FAIL: desktop wrapper decision: $result" >&2
  exit 1
}

# Exercise the desktop signal state machine without touching a real Steam.
STEAM_ROOT="$TMP/home/.steam/debian-installation"
mkdir -p "$STEAM_ROOT/logs" "$TMP/home/.local/state" "$TMP/run"
BOOTSTRAP_LOG="$STEAM_ROOT/logs/bootstrap_log.txt"
EVENTS="$TMP/events"
STATE="$TMP/steam-alive"
STEAM_SH_STATE="$TMP/steamsh-alive"
printf '%s\n' before >"$BOOTSTRAP_LOG"
: >"$EVENTS"
printf '%s\n' alive >"$STATE"

cat >"$TMP/bin/pkill" <<'SCRIPT'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >>"$TEST_EVENTS"
case "$*" in
  '-TERM -x steam')
    if [[ "${TEST_MODE:-}" == clean ]]; then
      printf '%s\n' Shutdown >>"$TEST_BOOTSTRAP_LOG"
      rm -f "$TEST_STATE"
    elif [[ "${TEST_MODE:-}" == shutdown-stuck ]]; then
      printf '%s\n' Shutdown >>"$TEST_BOOTSTRAP_LOG"
    fi
    ;;
  '-KILL -x steam')
    [[ "${TEST_MODE:-}" != unkillable ]] && rm -f "$TEST_STATE"
    ;;
esac
SCRIPT
chmod +x "$TMP/bin/pkill"
cat >"$TMP/bin/pgrep" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == -x && "${2:-}" == steam ]]; then
  [[ -e "$TEST_STATE" ]] && exit 0 || exit 1
fi
if [[ "${1:-}" == -f ]]; then
  case "${2:-}" in
    *'/steam.sh'*)
      [[ -e "${TEST_STEAM_SH_STATE:-}" ]] && exit 0 || exit 1
      ;;
  esac
fi
exit 1
SCRIPT
chmod +x "$TMP/bin/pgrep"
cat >"$TMP/bin/sleep" <<'SCRIPT'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$TEST_EVENTS"
exit 0
SCRIPT
chmod +x "$TMP/bin/sleep"
cat >"$TMP/bin/sync" <<'SCRIPT'
#!/usr/bin/env bash
printf 'sync\n' >>"$TEST_EVENTS"
exit 0
SCRIPT
chmod +x "$TMP/bin/sync"
printf '%s\n' '#!/usr/bin/env bash' 'printf "launcher\\n" >>"$TEST_EVENTS"' \
  >"$TMP/home/.local/share/SLSsteam/path/steam"
chmod +x "$TMP/home/.local/share/SLSsteam/path/steam"

run_restart() {
  HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" XDG_RUNTIME_DIR="$TMP/run" \
    TEST_MODE="$1" TEST_EVENTS="$EVENTS" TEST_STATE="$STATE" \
    TEST_STEAM_SH_STATE="$STEAM_SH_STATE" \
    TEST_BOOTSTRAP_LOG="$BOOTSTRAP_LOG" SLS_RESTART_GRACE_SECS="$2" \
    bash "$RESTART_SH"
}

run_restart clean 1
grep -q '^pkill -TERM -x steam$' "$EVENTS" || {
  echo "FAIL: clean restart did not request TERM first" >&2
  exit 1
}
if grep -q '^pkill -KILL -x steam$' "$EVENTS"; then
  echo "FAIL: clean Shutdown observation unnecessarily escalated" >&2
  exit 1
fi
grep -q ' clean$' "$TMP/home/.local/state/slsteam-moon/restart.log" || {
  echo "FAIL: clean restart outcome was not recorded" >&2
  exit 1
}
grep -q '^launcher$' "$EVENTS" || {
  echo "FAIL: clean restart did not relaunch through the wrapper" >&2
  exit 1
}

: >"$EVENTS"
printf '%s\n' before >"$BOOTSTRAP_LOG"
printf '%s\n' alive >"$STATE"
run_restart shutdown-stuck 1
grep -q '^pkill -TERM -x steam$' "$EVENTS" || {
  echo "FAIL: stuck-clean restart did not request TERM first" >&2
  exit 1
}
grep -q '^pkill -KILL -x steam$' "$EVENTS" || {
  echo "FAIL: Shutdown observation with a live Steam process did not escalate" >&2
  exit 1
}
grep -q '^launcher$' "$EVENTS" || {
  echo "FAIL: stuck-clean restart did not relaunch after escalation" >&2
  exit 1
}

grep -q ' escalated$' "$TMP/home/.local/state/slsteam-moon/restart.log" || {
  echo "FAIL: stuck-clean escalation outcome was not recorded" >&2
  exit 1
}

: >"$EVENTS"
printf '%s\n' before >"$BOOTSTRAP_LOG"
printf '%s\n' alive >"$STATE"
if run_restart unkillable 0; then
  echo "FAIL: restart succeeded while the old Steam process remained alive" >&2
  exit 1
fi
if grep -q '^launcher$' "$EVENTS"; then
  echo "FAIL: restart relaunched while the old Steam process remained alive" >&2
  exit 1
fi

grep -q '^pkill -TERM -x steam$' "$EVENTS" || {
  echo "FAIL: fallback restart did not request TERM first" >&2
  exit 1
}
grep -q '^pkill -KILL -x steam$' "$EVENTS" || {
  echo "FAIL: fallback restart did not escalate to KILL" >&2
  exit 1
}
grep -q ' escalated$' "$TMP/home/.local/state/slsteam-moon/restart.log" || {
  echo "FAIL: escalated restart outcome was not recorded" >&2
  exit 1
}

: >"$EVENTS"
printf '%s\n' before >"$BOOTSTRAP_LOG"
printf '%s\n' alive >"$STATE"
printf '%s\n' alive >"$STEAM_SH_STATE"
if run_restart residual-steam-sh 0; then
  echo "FAIL: restart succeeded while the previous steam.sh process remained alive" >&2
  exit 1
fi
if grep -q '^launcher$' "$EVENTS"; then
  echo "FAIL: restart relaunched while the previous steam.sh process remained alive" >&2
  exit 1
fi
grep -q ' failed$' "$TMP/home/.local/state/slsteam-moon/restart.log" || {
  echo "FAIL: residual steam.sh restart failure was not recorded" >&2
  exit 1
}
rm -f "$STEAM_SH_STATE"

: >"$EVENTS"
printf '%s\n' before >"$BOOTSTRAP_LOG"
rm -f "$STATE"
run_restart already-gone 1
if grep -q '^pkill -TERM -x steam$\|^pkill -KILL -x steam$' "$EVENTS"; then
  echo "FAIL: already-gone restart sent a client signal" >&2
  exit 1
fi
grep -q ' already-gone$' "$TMP/home/.local/state/slsteam-moon/restart.log" || {
  echo "FAIL: already-gone restart outcome was not recorded" >&2
  exit 1
}

unlink "$TMP/home/.local/share/SLSsteam/path/steam"
if HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" \
    bash "$RESTART_SH" --check; then
  echo "FAIL: preflight accepted a desktop without the slsteam-moon wrapper" >&2
  exit 1
fi

grep -q "flock -n" "$RESTART_SH" || {
  echo "FAIL: restart helper has no cross-process lock" >&2
  exit 1
}
grep -q '^nohup "$LAUNCHER" 9>&-' "$RESTART_SH" || {
  echo "FAIL: launched Steam inherits the restart lock descriptor" >&2
  exit 1
}
if grep -q 'setsid nohup "$LAUNCHER"' "$RESTART_SH"; then
  echo "FAIL: desktop Steam launcher is moved into a second session" >&2
  exit 1
fi
if grep -Eq 'steam -shutdown|steam\.pipe' "$RESTART_SH"; then
  echo "FAIL: restart helper uses Steam's logout-producing shutdown path" >&2
  exit 1
fi
grep -q '^sync$' "$RESTART_SH" || {
  echo "FAIL: restart helper does not flush pending filesystem writes" >&2
  exit 1
}
grep -q 'pkill -TERM -x steam' "$RESTART_SH" || {
  echo "FAIL: restart helper has no TERM-first client shutdown" >&2
  exit 1
}
grep -q 'SLS_RESTART_GRACE_SECS' "$RESTART_SH" || {
  echo "FAIL: restart helper has no configurable TERM grace window" >&2
  exit 1
}
grep -q 'bootstrap_log' "$RESTART_SH" || {
  echo "FAIL: restart helper does not observe the bootstrap log" >&2
  exit 1
}
grep -q 'Shutdown' "$RESTART_SH" || {
  echo "FAIL: restart helper does not recognize a clean Shutdown record" >&2
  exit 1
}
grep -q 'restart.log' "$RESTART_SH" || {
  echo "FAIL: restart helper does not record restart outcomes" >&2
  exit 1
}
grep -q 'for _ in $(seq 1 75)' "$RESTART_SH" || {
  echo "FAIL: restart helper does not wait for Steam children to exit" >&2
  exit 1
}
grep -Fq "pgrep -f '/steam.sh([[:space:]]|$)'" "$RESTART_SH" || {
  echo "FAIL: helper relaunches before the previous Steam wrapper exits" >&2
  exit 1
}
grep -Fq "pgrep -f 'srt-logger'" "$RESTART_SH" || {
  echo "FAIL: helper relaunches before the previous Steam logger exits" >&2
  exit 1
}
grep -q '^sleep 12$' "$RESTART_SH" || {
  echo "FAIL: account logoff state is not given time to settle before relaunch" >&2
  exit 1
}
grep -q '^cd "$HOME" || exit 1$' "$RESTART_SH" || {
  echo "FAIL: Steam relaunch inherits Lumen's working directory" >&2
  exit 1
}

PACKAGE="$ROOT/dist/lumen-linux.zip"
if [ ! -f "$PACKAGE" ]; then
  echo "FAIL: packaged Lumen archive is missing" >&2
  exit 1
fi
if ! unzip -p "$PACKAGE" lua/restart_steam.sh | cmp -s - "$RESTART_SH"; then
  echo "FAIL: packaged restart helper differs from the source helper" >&2
  exit 1
fi

echo "test_restart_steam: ALL PASS"
