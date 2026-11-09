-- Integration Test for loci-arena client and loci_client SDK (PR2)
package.path = package.path .. ";./client/loci2d/?.lua;./client/loci2d/lib/?.lua;./client/src/?.lua;./client/?.lua;./?.lua"
package.cpath = package.cpath .. ";./client/loci2d/lib/?.so;./client/loci2d/?.so;./client/?.so;./lib/?.so"

-- 1. Mock Love2D minimal environment
_G.love = {
    getVersion = function() return 11, 5, 0 end,
    window = {
        getMode = function() return 1280, 720, {} end,
        setMode = function() return true end,
        getDPIScale = function() return 1 end,
    },
    graphics = {
        setDefaultFilter = function() end,
        newFont = function() return { getWidth = function() return 100 end, getHeight = function() return 16 end } end,
        getFont = function() return { getWidth = function() return 100 end, getHeight = function() return 16 end } end,
        setFont = function() end,
        setColor = function() end,
        setBackgroundColor = function() end,
        getShader = function() return nil end,
        setShader = function() end,
        getColor = function() return 1, 1, 1, 1 end,
        rectangle = function() end,
        printf = function() end,
        print = function() end,
        newCanvas = function() return { setFilter = function() end } end,
        setCanvas = function() end,
        setLineWidth = function() end,
        clear = function() end,
        circle = function() end,
        ellipse = function() end,
        line = function() end,
        push = function() end,
        pop = function() end,
        translate = function() end,
        scale = function() end,
        draw = function() end,
        newQuad = function() return {} end,
        newImage = function() return { getDimensions = function() return 32, 32 end, getWidth = function() return 32 end, getHeight = function() return 32 end, setFilter = function() end } end,
        getWidth = function() return 1280 end,
        getHeight = function() return 720 end,
    },
    timer = {
        _time = 100.0,
        getTime = function() return _G.love.timer._time end,
        getFPS = function() return 60 end,
    },
    math = {
        random = function(min, max) return min and (min + 1) or 0.5 end
    },
    keyboard = {
        isDown = function() return false end
    },
    filesystem = {
        createDirectory = function() return true end,
        write = function() return true end,
        getInfo = function() return true end,
        read = function(path)
            local f = io.open(path, "rb")
            if f then
                local content = f:read("*a")
                f:close()
                return content
            end
            return nil
        end
    }
}

-- Mock os.getenv to avoid binding network during mock unit test
local orig_getenv = os.getenv
os.getenv = function(k)
    if k == "LOCI_SERVER_IP" then return "127.0.0.1" end
    if k == "LOCI_SERVER_PORT" then return "8080" end
    return orig_getenv(k)
end

print(">>> Loading client/main.lua into test harness...")
dofile("client/main.lua")

local loci = require("loci_client")

-- 2. Mock loci network state and test entity
loci.my_entity_id = 42
local my_ent = {
    id = 42,
    x = 0,
    y = 0,
    vx = 0,
    vy = 0,
    properties = {
        move_speed = "3.0",
        character_name = "arya",
        stunned_until = "0",
        paralyzed_until = "0",
        dashing_until = "0"
    },
    get = function(self, k, default)
        return self.properties[k] or default
    end,
    is_local_player = function(self) return true end
}
loci._entities = { [42] = my_ent }
loci.get_my_entity = function() return my_ent end
loci.get_entities = function() return { my_ent } end
loci.get_server_tick_rate = function() return 30 end
loci._last_state_tick = 100

-- Initialize client hooks
love.load()

print("[Test 1] Testing Connection UX Callbacks (on_connection_lost & on_reconnected)...")
assert(loci.on_connection_lost ~= nil, "loci.on_connection_lost must be set")
assert(loci.on_reconnected ~= nil, "loci.on_reconnected must be set")

loci.on_connection_lost("heartbeat timeout")
-- Call love.draw to ensure it renders the connection lost banner without crashing
love.draw()

loci.on_reconnected(42)
love.draw()
print("  -> Passed: Connection resilience callbacks verified.")

print("[Test 2] Testing Arena Boundary Clamping (-500 to 500)...")
assert(loci._prediction_handler ~= nil, "loci._prediction_handler must be registered")

-- Move beyond positive border
my_ent.x = 495.0
my_ent.y = 0.0
-- Simulate moving right: dx = 1, dy = 0, dt = 1.0 (velocity 90 px/s would reach 585 without clamping)
loci._prediction_handler(my_ent, 1, 0, 1.0)
assert(my_ent.x == 500.0, string.format("my_ent.x should clamp to 500.0, got: %f", my_ent.x))

-- Move beyond negative border
my_ent.x = -495.0
my_ent.y = -495.0
loci._prediction_handler(my_ent, -1, -1, 1.0)
assert(my_ent.x == -500.0, string.format("my_ent.x should clamp to -500.0, got: %f", my_ent.x))
assert(my_ent.y == -500.0, string.format("my_ent.y should clamp to -500.0, got: %f", my_ent.y))
print("  -> Passed: Arena clamping strictly bounds movement.")

print("[Test 3] Testing Crowd Control Interruption (stunned_until & paralyzed_until)...")
my_ent.x = 0.0
my_ent.y = 0.0
my_ent.properties.stunned_until = "150" -- Current tick is 100
loci._prediction_handler(my_ent, 1, 0, 0.1)
assert(my_ent.x == 0.0 and my_ent.vx == 0, "stunned entity must not move via prediction")

my_ent.properties.stunned_until = "0"
my_ent.properties.paralyzed_until = "150"
loci._prediction_handler(my_ent, 1, 0, 0.1)
assert(my_ent.x == 0.0 and my_ent.vx == 0, "paralyzed entity must not move via prediction")
my_ent.properties.paralyzed_until = "0"
print("  -> Passed: Crowd control locks displacement.")

print("[Test 4] Testing Dash Processing (whirlwind_dash)...")
my_ent.x = 0.0
my_ent.y = 0.0
my_ent.vx = 10.0 -- 10 units/tick * 30 ticks = 300 units/sec
my_ent.vy = 0.0
my_ent.properties.dashing_until = "110" -- Active dash
loci._prediction_handler(my_ent, 0, 0, 0.1)
-- 300 * 0.1 = 30
assert(math.abs(my_ent.x - 30.0) < 0.001, string.format("dash should displace by 30 units, got %f", my_ent.x))

-- Test dash clamping at border
my_ent.x = 480.0
my_ent.vx = 10.0
loci._prediction_handler(my_ent, 0, 0, 0.5) -- 300 * 0.5 = 150 -> 630 -> clamp to 500
assert(my_ent.x == 500.0, string.format("dash should clamp to 500 at arena boundary, got %f", my_ent.x))
my_ent.properties.dashing_until = "0"
print("  -> Passed: Dash prediction operates with server velocity and respects borders.")

print("[Test 5] Testing Keybindings (F3, F4, F5, F6)...")
love.keypressed("f3") -- Toggle debug overlay
love.draw() -- Verify debug overlay rendering (Ping, Jitter, Loss, Tick Hz)

love.keypressed("f5") -- Toggle latency simulation
assert(loci.netcode.simulate_latency == 0.050, "F5 should toggle simulated latency to 50ms")

love.keypressed("f6") -- Toggle packet loss simulation
assert(loci.netcode.simulate_packet_loss == 0.10, "F6 should toggle simulated packet loss to 10%")

-- Test F4 CSV export
local csv_exported = false
loci.export_telemetry_csv = function()
    csv_exported = true
    return "logs/network_stats_test.csv"
end
love.keypressed("f4")
assert(csv_exported == true, "F4 must trigger CSV telemetry export")
print("  -> Passed: F3, F4, F5, F6 hotkeys work as intended.")

print("[Test 6] Testing Clean Shutdown in love.quit()...")
local quit_called = false
loci.quit = function() quit_called = true end
love.quit()
assert(quit_called == true, "love.quit() must invoke loci.quit()")
print("  -> Passed: love.quit cleans up and exports telemetry.")

print("\n>>> ALL CLIENT INTEGRATION TESTS PASSED SUCCESSFULLY! <<<")
