-- Integration Test for loci-arena client and loci_client SDK
package.path = package.path .. ";./client/loci2d/?.lua;./client/loci2d/lib/?.lua;./client/src/?.lua;./client/?.lua;./?.lua"
package.cpath = package.cpath .. ";./client/loci2d/lib/?.so;./client/loci2d/?.so;./client/?.so;./lib/?.so"

-- Track printed/rendered text and keyboard state for real integration assertions
local captured_prints = {}
local captured_printf = {}
local keys_down = {}
local sent_udp_packets = {}

-- 1. Stub luasocket UDP so loci.connect() exercises schema loading without real network I/O
local ok_sock, socket = pcall(require, "socket")
if not ok_sock then
    socket = {
        gettime = function() return _G.love.timer._time end
    }
    package.preload["socket"] = function() return socket end
end

socket.udp = function()
    return {
        settimeout = function() end,
        setpeername = function() end,
        send = function(_, data)
            table.insert(sent_udp_packets, data)
            return #data
        end,
        receive = function() return nil, "timeout" end,
        close = function() end,
    }
end

-- 2. Mock Love2D minimal environment
_G.love = {
    getVersion = function() return 11, 5, 0 end,
    window = {
        getMode = function() return 1280, 720, {} end,
        setMode = function() return true end,
        getDPIScale = function() return 1 end,
    },
    graphics = {
        _font = { getWidth = function() return 100 end, getHeight = function() return 16 end },
        _line_width = 1,
        setDefaultFilter = function() end,
        newFont = function() return { getWidth = function() return 100 end, getHeight = function() return 16 end } end,
        getFont = function() return _G.love.graphics._font end,
        setFont = function(f) _G.love.graphics._font = f or _G.love.graphics._font end,
        setColor = function() end,
        setBackgroundColor = function() end,
        getShader = function() return nil end,
        setShader = function() end,
        getColor = function() return 1, 1, 1, 1 end,
        rectangle = function() end,
        polygon = function() end,
        printf = function(text) table.insert(captured_printf, tostring(text)) end,
        print = function(text) table.insert(captured_prints, tostring(text)) end,
        newCanvas = function() return { setFilter = function() end } end,
        setCanvas = function() end,
        setLineWidth = function(w) _G.love.graphics._line_width = w end,
        getLineWidth = function() return _G.love.graphics._line_width end,
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
        getDimensions = function() return 1280, 720 end,
    },
    timer = {
        _time = 100.0,
        getTime = function() return _G.love.timer._time end,
        getFPS = function() return 60 end,
    },
    math = {
        random = function(min) return min and (min + 1) or 0.5 end
    },
    keyboard = {
        isDown = function(k) return keys_down[k] == true end
    },
    mouse = {
        getPosition = function() return 640, 360 end
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

local function reset_draw_captures()
    captured_prints = {}
    captured_printf = {}
end

local function contains_text(list, needle)
    for _, item in ipairs(list) do
        if item:find(needle, 1, true) then
            return true
        end
    end
    return false
end

print(">>> Loading client/main.lua into test harness...")
dofile("client/main.lua")

local loci = require("loci_client")
local entity_mod = require("loci.entity")

-- Initialize client hooks (uses stubbed socket.udp, no real network I/O)
love.load()

-- Populate real SDK entity state
loci._mock_time = 100.0
loci._last_state_received_time = 100.0
loci._last_packet_received_time = 100.0
loci._last_state_tick = 100
loci.server_tick_rate = 30.0
loci.my_entity_id = 42

local my_ent = entity_mod.new_entity(42, "player")
my_ent.properties = {
    entity_type = "player",
    move_speed = 3.0,
    character_name = "arya",
    stunned_until = 0,
    paralyzed_until = 0,
    dashing_until = 0
}
loci.entities = { [42] = my_ent }
loci._entities_list_cache = nil

print("[Test 1] Testing Connection UX Callbacks (on_connection_lost & on_reconnected)...")
assert(loci.on_connection_lost ~= nil, "loci.on_connection_lost must be set")
assert(loci.on_reconnected ~= nil, "loci.on_reconnected must be set")

loci.on_connection_lost("heartbeat timeout")
reset_draw_captures()
love.draw()
assert(contains_text(captured_printf, "Conexão instável / Reconectando..."),
    "Connection lost banner must render when on_connection_lost fires")

loci.on_reconnected(42)
reset_draw_captures()
love.draw()
assert(not contains_text(captured_printf, "Conexão instável / Reconectando..."),
    "Connection lost banner must clear after on_reconnected fires")

-- Fallback recovery via love.update when entity is present
loci.on_connection_lost("heartbeat timeout")
love.update(0.016)
reset_draw_captures()
love.draw()
assert(not contains_text(captured_printf, "Conexão instável / Reconectando..."),
    "Connection lost banner must also clear on entity recovery in love.update")
print("  -> Passed: Connection resilience banner and callbacks verified.")

print("[Test 2] Testing Arena Boundary Clamping (-498 to 498) via love.update...")
assert(loci._prediction_handler ~= nil, "loci._prediction_handler must be registered")

-- Move beyond positive border via held 'd' key (frame 1 captures input -> send_move; frame 2 predicts)
my_ent.x = 495.0
my_ent.y = 0.0
keys_down = { d = true }
loci._mock_time = 100.10
_G.love.timer._time = 100.10
loci._last_state_received_time = 100.10
love.update(0.016)
loci._mock_time = 100.35
_G.love.timer._time = 100.35
loci._last_state_received_time = 100.35
love.update(0.25)
assert(my_ent.x == 498.0, string.format("my_ent.x should clamp to 498.0, got: %f", my_ent.x))
assert(my_ent.vx == 0, "outward vx must zero on wall contact")

-- Move beyond negative borders via held 'a' + 'w'
my_ent.x = -495.0
my_ent.y = -495.0
keys_down = { a = true, w = true }
loci._mock_time = 100.40
_G.love.timer._time = 100.40
loci._last_state_received_time = 100.40
love.update(0.016)
loci._mock_time = 100.65
_G.love.timer._time = 100.65
loci._last_state_received_time = 100.65
love.update(0.25)
assert(my_ent.x == -498.0, string.format("my_ent.x should clamp to -498.0, got: %f", my_ent.x))
assert(my_ent.y == -498.0, string.format("my_ent.y should clamp to -498.0, got: %f", my_ent.y))
keys_down = {}
love.update(0.016)
print("  -> Passed: Arena clamping strictly bounds movement to [-498, 498].")

print("[Test 3] Testing Crowd Control Interruption (stunned_until & paralyzed_until)...")
my_ent.x = 0.0
my_ent.y = 0.0
keys_down = { d = true }
my_ent.properties.stunned_until = 150 -- Current tick is 100
love.update(0.016)
love.update(0.1)
assert(my_ent.x == 0.0 and my_ent.vx == 0, "stunned entity must not move via prediction")

my_ent.properties.stunned_until = 0
my_ent.properties.paralyzed_until = 150
love.update(0.1)
assert(my_ent.x == 0.0 and my_ent.vx == 0, "paralyzed entity must not move via prediction")

-- Clear CC and verify immediate movement recovery (frame 1 resyncs move intent, frame 2 predicts)
my_ent.properties.paralyzed_until = 0
love.update(0.016)
love.update(0.1)
assert(my_ent.x > 0.0, "entity must resume predicted movement after CC expires")
keys_down = {}
love.update(0.016)
print("  -> Passed: Crowd control locks and recovers displacement.")

print("[Test 4] Testing Dash Processing (dashing_until) & Border Clamp via love.update...")
my_ent.x = 0.0
my_ent.y = 0.0
my_ent.vx = 10.0 -- 10 units/tick * 30 ticks = 300 units/sec
my_ent.vy = 0.0
my_ent.properties.dashing_until = 110 -- Active dash (cur_tick = 100)
love.update(0.1)
assert(math.abs(my_ent.x - 30.0) < 0.001, string.format("dash should displace by 30 units, got %f", my_ent.x))

-- Test dash clamping at safe arena border (498)
my_ent.x = 480.0
my_ent.vx = 10.0
love.update(0.5) -- 300 * 0.5 = 150 -> 630 -> clamp to 498
assert(my_ent.x == 498.0, string.format("dash should clamp to 498 at arena boundary, got %f", my_ent.x))
assert(my_ent.vx == 0, "dash outward vx must zero on wall contact")
my_ent.properties.dashing_until = 0
print("  -> Passed: Dash prediction operates with server velocity and respects [-498, 498] borders.")

print("[Test 5] Testing Telemetry Overlay & Keybindings (F3, F4, F5, F6)...")
if loci.network_stats then
    loci.network_stats:record_rtt(42)
    loci.network_stats:record_snapshot(100, 100.000)
    loci.network_stats:record_snapshot(101, 100.033)
end

love.keypressed("f3") -- Toggle debug overlay ON
reset_draw_captures()
love.draw()
assert(contains_text(captured_prints, "Ping: 42 ms"), "F3 overlay must display real Ping metric")
assert(contains_text(captured_prints, "Jitter:"), "F3 overlay must display Jitter metric")
assert(contains_text(captured_prints, "Loss:"), "F3 overlay must display Packet Loss metric")
assert(contains_text(captured_prints, "Tick Rate:"), "F3 overlay must display Tick Rate metric")
assert(contains_text(captured_prints, "Touch UI:"), "F3 overlay must preserve Touch UI status")

love.keypressed("f5")
assert(math.abs(loci.netcode.simulate_latency - 0.050) < 1e-6, "F5 #1 should set simulated latency to 50ms")
love.keypressed("f5")
assert(math.abs(loci.netcode.simulate_latency - 0.100) < 1e-6, "F5 #2 should set simulated latency to 100ms")
love.keypressed("f5")
assert(loci.netcode.simulate_latency == 0, "F5 #3 should reset simulated latency to 0ms")

love.keypressed("f6")
assert(math.abs(loci.netcode.simulate_packet_loss - 0.10) < 1e-6, "F6 #1 should set packet loss to 10%")
love.keypressed("f6")
assert(math.abs(loci.netcode.simulate_packet_loss - 0.25) < 1e-6, "F6 #2 should set packet loss to 25%")
love.keypressed("f6")
assert(loci.netcode.simulate_packet_loss == 0, "F6 #3 should reset packet loss to 0%")

-- Test F4 CSV export invokes the real SDK method name (export_network_stats_csv)
local orig_export = loci.export_network_stats_csv
local csv_exported = false
loci.export_network_stats_csv = function()
    csv_exported = true
    return "logs/network_stats_test.csv"
end
love.keypressed("f4")
assert(csv_exported == true, "F4 must trigger loci.export_network_stats_csv()")
print("  -> Passed: F3, F4, F5, F6 hotkeys work with real SDK APIs.")

print("[Test 6] Testing Clean Shutdown in love.quit()...")
csv_exported = false
loci.netcode.auto_export_csv_on_quit = true
local quit_called = false
local disconnect_called = false
local orig_quit = loci.quit
local orig_disconnect = loci.disconnect
loci.quit = function()
    quit_called = true
    return orig_quit()
end
loci.disconnect = function(reason)
    disconnect_called = true
    return orig_disconnect(reason)
end
love.quit()
loci.export_network_stats_csv = orig_export
assert(quit_called == true, "love.quit() must invoke loci.quit()")
assert(csv_exported == true, "loci.quit() must trigger export_network_stats_csv when auto_export_csv_on_quit=true")
assert(disconnect_called == true, "love.quit() must invoke loci.disconnect()")
print("  -> Passed: love.quit invokes loci.quit() and loci.disconnect() cleanly.")

print("\n>>> ALL CLIENT INTEGRATION TESTS PASSED SUCCESSFULLY! <<<")
