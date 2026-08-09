-- Webhelper launch diagnostic. The C++ audit hook cannot observe an execl
-- caller directly, so Lumen watches the first steamwebhelper appearance and
-- reports when no current-session CEF rewrite has been observed first.
local lfs = require("lfs")

local webhelperwatch = {}

function webhelperwatch.new_state()
  return {
    webhelper_alive = false,
    rewrite_seen = false,
    warned = false,
  }
end

-- Reset only the per-Steam-session observation state. The file offset is kept
-- by Watcher:reset_session so a rewrite written during the restart gap is
-- still consumed by the next poll.
function webhelperwatch.reset_state(state)
  state = state or webhelperwatch.new_state()
  state.webhelper_alive = false
  state.rewrite_seen = false
  state.warned = false
  return state
end

-- Pure state transition used by the host test and by the IO-backed watcher.
-- `decky_present` is an intentional exception: Decky owns port 8080 and the
-- injected Steam path deliberately does not rewrite that launch.
function webhelperwatch.observe(state, webhelper_alive, rewrite_seen, decky_present)
  state = state or webhelperwatch.new_state()
  if rewrite_seen == true then state.rewrite_seen = true end

  local appeared = webhelper_alive == true and not state.webhelper_alive
  state.webhelper_alive = webhelper_alive == true
  if appeared and not state.rewrite_seen and not decky_present and not state.warned then
    state.warned = true
    return true
  end
  return false
end

local Watcher = {}
Watcher.__index = Watcher

local function file_size(path)
  if not path or path == "" then return 0 end
  local size = lfs.attributes(path, "size")
  return tonumber(size) or 0
end

function webhelperwatch.new(opts)
  opts = opts or {}
  local home = os.getenv("HOME") or ""
  local log_path = opts.log_path or (home ~= "" and home .. "/.SLSsteam.log" or nil)
  local decky = opts.decky_present
  if decky == nil and home ~= "" then
    decky = lfs.attributes(home .. "/homebrew/services/PluginLoader") ~= nil
  end
  return setmetatable({
    state = webhelperwatch.new_state(),
    log_path = log_path,
    log_offset = file_size(log_path),
    decky_present = decky == true,
  }, Watcher)
end

-- Steam restarts while this sidecar remains alive. Reset the observation state
-- at the lifecycle return boundary, but keep log_offset so a rewrite emitted
-- during the restart gap is still attributed to the new session.
function Watcher:reset_session()
  self.state = webhelperwatch.reset_state(self.state)
end

-- Read only bytes appended after Lumen started. This avoids treating a stale
-- rewrite line from a previous Steam session as proof for the current one.
function Watcher:poll_rewrite()
  if not self.log_path or self.log_path == "" then return false end
  local size = file_size(self.log_path)
  if size < self.log_offset then self.log_offset = 0 end
  if size == self.log_offset then return false end

  local file = io.open(self.log_path, "rb")
  if not file then return false end
  file:seek("set", self.log_offset)
  local chunk = file:read(size - self.log_offset) or ""
  file:close()
  self.log_offset = size
  return chunk:find("CEF: rewrote --remote-debugging-port", 1, true) ~= nil
end

function Watcher:observe(webhelper_alive, consume_log)
  local rewrite_seen = false
  if consume_log ~= false then
    rewrite_seen = self:poll_rewrite()
  end
  return webhelperwatch.observe(
    self.state, webhelper_alive, rewrite_seen, self.decky_present)
end

function Watcher:warning_message()
  return "steamwebhelper appeared without a prior CEF port rewrite; " ..
    "execl/exec-family coverage may have changed (use SLSSTEAM_AUDIT_BINDALL=1)"
end

return webhelperwatch
