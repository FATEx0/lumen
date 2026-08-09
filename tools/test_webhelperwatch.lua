-- TDD test for the one-shot warning when steamwebhelper appears before a
-- CEF rewrite was observed.

local webhelperwatch = require("webhelperwatch")

local function check(condition, message)
  assert(condition, message)
end

local state = webhelperwatch.new_state()
check(webhelperwatch.observe(state, false, false, false) == false,
  "no process appearance is not a warning")
check(webhelperwatch.observe(state, true, false, false) == true,
  "first webhelper without rewrite warns")
check(webhelperwatch.observe(state, true, false, false) == false,
  "same webhelper appearance warns only once")
check(webhelperwatch.observe(state, false, false, false) == false,
  "webhelper disappearance is not a warning")
check(webhelperwatch.observe(state, true, false, false) == false,
  "warning remains one-shot after a restart")

local rewritten = webhelperwatch.new_state()
check(webhelperwatch.observe(rewritten, true, true, false) == false,
  "rewrite observed before webhelper suppresses warning")
check(webhelperwatch.observe(rewritten, false, false, false) == false,
  "rewrite state remains remembered")
check(webhelperwatch.observe(rewritten, true, false, false) == false,
  "later webhelper still has rewrite evidence")

local delayed = webhelperwatch.new_state()
check(webhelperwatch.observe(delayed, false, false, false) == false,
  "delayed process initially quiet")
check(webhelperwatch.observe(delayed, false, true, false) == false,
  "rewrite observed while process is absent")
check(webhelperwatch.observe(delayed, true, false, false) == false,
  "delayed webhelper sees rewrite evidence")

local restarted = webhelperwatch.new_state()
check(webhelperwatch.observe(restarted, false, true, false) == false,
  "prior session rewrite can be recorded before reset")
webhelperwatch.reset_state(restarted)
check(webhelperwatch.observe(restarted, true, false, false) == true,
  "new Steam session warns independently of prior rewrite state")

local decky = webhelperwatch.new_state()
check(webhelperwatch.observe(decky, true, false, true) == false,
  "Decky default-port coexistence does not warn")

local path = os.tmpname()
local file = assert(io.open(path, "wb"))
file:write("[Info] CEF: rewrote --remote-debugging-port to 40000\\n")
file:close()
local file_watcher = webhelperwatch.new({
  log_path = path,
  decky_present = false,
})
check(file_watcher:observe(true) == true,
  "stale rewrite line does not count for the new watcher")

local rewrite_watcher = webhelperwatch.new({
  log_path = path,
  decky_present = false,
})
local append = assert(io.open(path, "ab"))
append:write("[Info] CEF: rewrote --remote-debugging-port to 40001\\n")
append:close()
check(rewrite_watcher:observe(true) == false,
  "current-session rewrite suppresses the warning")
local gap_path = os.tmpname()
local gap_file = assert(io.open(gap_path, "wb"))
gap_file:close()
local gap_watcher = webhelperwatch.new({
  log_path = gap_path,
  decky_present = false,
})
local gap_append = assert(io.open(gap_path, "ab"))
gap_append:write("[Info] CEF: rewrote --remote-debugging-port to 40002\\n")
gap_append:close()
check(gap_watcher:observe(false, false) == false,
  "rewrite during a Steam gap is not consumed before return")
gap_watcher:reset_session()
check(gap_watcher:observe(true, true) == false,
  "rewrite during the gap suppresses the new-session warning")
os.remove(gap_path)

os.remove(path)

io.stderr:write("test_webhelperwatch OK\n")
