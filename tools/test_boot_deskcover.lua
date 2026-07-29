-- Run: LUMEN_LUA_DIR=lua ./bin/lumen --test tools/test_boot_deskcover.lua
-- Static check: the once-per-session desktop-coverage pass must NOT run while
-- Lumen boots. It is 2.9-3.9 s of shell CPU and the wrapper already kicks the
-- guardian for the same work, so running it here delayed Steam's own startup.
-- boot.lua wires up the whole sidecar, so we assert on the source; the deferred
-- replacement lives in loop.lua (see test_loop_deskcover.lua).
local dir = os.getenv("LUMEN_LUA_DIR") or "lua"
local fh = assert(io.open(dir .. "/boot.lua")); local src = fh:read("*a"); fh:close()
local function ok(c, m) if not c then error("FAIL: " .. m) end end
ok(not src:find('require("deskcover").run', 1, true),
   "boot.lua runs no coverage pass on the launch critical path")
ok(src:find("deskcover.new_initial", 1, true),
   "boot.lua documents where the deferred pass now lives")
print("test_boot_deskcover: ALL PASS")
