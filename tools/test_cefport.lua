-- Run via the built binary:
--   LUMEN_LUA_DIR=lua ./bin/lumen --test tools/test_cefport.lua
--
-- cefport.lua resolves which TCP port Steam's CEF endpoint is on: slsteam-moon
-- rewrites Steam's hard-coded 8080 to a free loopback port and writes it to
-- ~/.local/share/Lumen/cef_port; the injector reads it from there, falling back
-- to 8080 (vanilla Steam / slsteam-moon off). These tests cover the pure parse
-- and the resolve(read_fn, fallback) wrapper exhaustively.
package.path = "lua/?.lua;" .. package.path
local cefport = require("cefport")

local fails = 0
local checks = 0
local function ok(cond, name)
  checks = checks + 1
  if cond then io.write("ok " .. name .. "\n")
  else io.write("FAIL " .. name .. "\n"); fails = fails + 1 end
end

-- ── parse_port: accepted ────────────────────────────────────────────────────
ok(cefport.parse_port("54017") == 54017, "plain valid")
ok(cefport.parse_port("54017\n") == 54017, "trailing newline")
ok(cefport.parse_port("  8123  ") == 8123, "surrounding whitespace")
ok(cefport.parse_port("\t8123\r\n") == 8123, "tabs/CRLF")
ok(cefport.parse_port("1024") == 1024, "low boundary")
ok(cefport.parse_port("65535") == 65535, "high boundary")
ok(cefport.parse_port("08080") == 8080, "leading zero decimal")

-- ── parse_port: rejected ────────────────────────────────────────────────────
ok(cefport.parse_port("1023") == nil, "below range")
ok(cefport.parse_port("65536") == nil, "above range")
ok(cefport.parse_port("70000") == nil, "way above range")
ok(cefport.parse_port("0") == nil, "zero")
ok(cefport.parse_port("-5") == nil, "negative")
ok(cefport.parse_port("80.5") == nil, "non-integer")
ok(cefport.parse_port("8080abc") == nil, "trailing garbage")
ok(cefport.parse_port("abc") == nil, "letters")
ok(cefport.parse_port("") == nil, "empty")
ok(cefport.parse_port("   ") == nil, "whitespace only")
ok(cefport.parse_port(nil) == nil, "nil")
ok(cefport.parse_port(8080) == nil, "number (non-string) rejected")
ok(cefport.parse_port({}) == nil, "table rejected")

-- ── resolve(read_fn, fallback) ──────────────────────────────────────────────
do local p, ff = cefport.resolve(function() return "49777" end, 8080)
   ok(p == 49777 and ff == true, "valid file content wins") end
do local p, ff = cefport.resolve(function() return "nonsense" end, 8080)
   ok(p == 8080 and ff == false, "garbage -> fallback") end
do local p, ff = cefport.resolve(function() return nil end, 8080)
   ok(p == 8080 and ff == false, "missing -> fallback") end
do local p, ff = cefport.resolve(function() return "70000" end, 8080)
   ok(p == 8080 and ff == false, "out-of-range -> fallback") end
do local p, ff = cefport.resolve(function() error("io boom") end, 8080)
   ok(p == 8080 and ff == false, "read error caught -> fallback") end
do local p, ff = cefport.resolve(function() return 49777 end, 8080)
   ok(p == 8080 and ff == false, "non-string content -> fallback") end
do local p, ff = cefport.resolve(function() return "12345" end, 9001)
   ok(p == 12345 and ff == true, "custom fallback unused when file valid") end
do local p, ff = cefport.resolve(function() return nil end, 9001)
   ok(p == 9001 and ff == false, "custom fallback honoured") end
do local p, ff = cefport.resolve(function() return nil end)
   ok(p == cefport.FALLBACK and p == 8080 and ff == false, "default fallback is 8080") end

-- ── read_contract: end-to-end against a real temp file via HOME override ─────
do
  local orig = os.getenv
  local home = "/tmp/lumen_cefport_test_" .. tostring(os.time())
  os.execute("mkdir -p '" .. home .. "/.local/share/Lumen'")
  os.getenv = function(k) if k == "HOME" then return home end return orig(k) end

  -- no file yet
  ok(cefport.read_contract() == nil, "read_contract: nil when file absent")
  local p1 = cefport.resolve(cefport.read_contract, 8080)
  ok(p1 == 8080, "resolve(read_contract): fallback when file absent")

  -- write a real contract file
  local f = io.open(home .. "/.local/share/Lumen/cef_port", "w")
  f:write("51515\n"); f:close()
  ok(cefport.read_contract() == "51515", "read_contract: reads first line")
  local p2, ff2 = cefport.resolve(cefport.read_contract, 8080)
  ok(p2 == 51515 and ff2 == true, "resolve(read_contract): reads real file")

  -- a contract owned by THIS process is live (self-owned, so the pid exists)
  local self_stat = cefport.read_proc_stat(
    tonumber(io.open("/proc/self/stat"):read("*l"):match("^(%d+)")))
  local self_pid = tonumber(self_stat:match("^(%d+)"))
  local self_start = cefport.stat_start_ticks(self_stat)
  f = io.open(home .. "/.local/share/Lumen/cef_port", "w")
  f:write("51516\nowner " .. self_pid .. " " .. self_start .. "\n"); f:close()
  local p3, ff3 = cefport.resolve(cefport.read_contract, 8080)
  ok(p3 == 51516 and ff3 == true, "resolve(read_contract): live owner honoured")

  -- ... and the same contract with a bumped start time is stale
  f = io.open(home .. "/.local/share/Lumen/cef_port", "w")
  f:write("51517\nowner " .. self_pid .. " " .. (self_start + 1) .. "\n"); f:close()
  local p4, ff4, why4 = cefport.resolve(cefport.read_contract, 8080)
  ok(p4 == 8080 and ff4 == false and why4 == "stale",
     "resolve(read_contract): previous-session contract ignored")

  os.getenv = orig
  os.execute("rm -rf '" .. home .. "'")
end

-- ── parse_contract ──────────────────────────────────────────────────────────
do
  local c = cefport.parse_contract("49777\n")
  ok(c and c.port == 49777 and c.pid == nil and c.start == nil,
     "parse_contract: port-only (legacy slsteam-moon)")
  c = cefport.parse_contract("49777\nowner 4242 987654\n")
  ok(c and c.port == 49777 and c.pid == 4242 and c.start == 987654,
     "parse_contract: port + owner record")
  c = cefport.parse_contract("49777")
  ok(c and c.port == 49777, "parse_contract: no trailing newline")
  c = cefport.parse_contract("49777\nowner garbage\n")
  ok(c and c.port == 49777 and c.pid == nil,
     "parse_contract: malformed owner ignored, port kept")
  ok(cefport.parse_contract("owner 1 2\n49777") == nil,
     "parse_contract: port must be the first line")
  ok(cefport.parse_contract("70000\nowner 1 2") == nil,
     "parse_contract: out-of-range port rejected")
  ok(cefport.parse_contract("") == nil, "parse_contract: empty")
  ok(cefport.parse_contract(nil) == nil, "parse_contract: nil")
end

-- ── stat_start_ticks / owner_alive (injected /proc reader) ───────────────────
do
  local plain = "1234 (steam) S 1 1234 1234 0 -1 4194560 100 0 0 0 1 2 0 0 20 0 3 0 "
    .. "555666 100 200 300"
  local weird = "1234 (we ird) na:me) S 1 1234 1234 0 -1 4194560 100 0 0 0 1 2 0 0 20 0 3 0 "
    .. "777888 100 200 300"
  ok(cefport.stat_start_ticks(plain) == 555666, "stat_start_ticks: plain comm")
  ok(cefport.stat_start_ticks(weird) == 777888,
     "stat_start_ticks: comm with spaces and parens")
  ok(cefport.stat_start_ticks("1234 (steam) S 1 2 3") == nil,
     "stat_start_ticks: truncated -> nil")
  ok(cefport.stat_start_ticks("no parens") == nil, "stat_start_ticks: malformed -> nil")
  ok(cefport.stat_start_ticks(nil) == nil, "stat_start_ticks: nil -> nil")

  local function reader(_) return plain end
  ok(cefport.owner_alive(1234, 555666, reader) == true, "owner_alive: exact match")
  ok(cefport.owner_alive(1234, 555667, reader) == false,
     "owner_alive: start-time mismatch (pid reuse) -> dead")
  ok(cefport.owner_alive(1234, 555666, function() return nil end) == false,
     "owner_alive: no /proc entry -> dead")
  ok(cefport.owner_alive(1234, 555666, function() error("boom") end) == false,
     "owner_alive: reader error -> dead")
  ok(cefport.owner_alive(nil, 555666, reader) == false, "owner_alive: nil pid -> dead")

  -- resolve() must consult the injected reader, not the real /proc
  local p, ff = cefport.resolve(function() return "49777\nowner 1234 555666" end,
                                8080, reader)
  ok(p == 49777 and ff == true, "resolve: live owner via injected reader")
  local p2, ff2, why = cefport.resolve(function() return "49777\nowner 1234 999" end,
                                       8080, reader)
  ok(p2 == 8080 and ff2 == false and why == "stale",
     "resolve: dead owner -> fallback + stale reason")
end

if fails == 0 then io.write("\ntest_cefport: ALL PASS (" .. checks .. " checks)\n")
else io.write("\n" .. fails .. "/" .. checks .. " FAILED\n"); os.exit(1) end
