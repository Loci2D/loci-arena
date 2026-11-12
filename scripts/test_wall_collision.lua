-- Automated Test Suite: Arena Wall Collision & Netcode Prediction/Reconciliation
-- Card CXjaqwVl / PR #51
-- Note: Intentionally placed in scripts/ (outside server/scripts/default_arena/)
-- so loci2d does not bundle test code into map VFS or replays.

local function assert_near(actual, expected, eps, msg)
    eps = eps or 1e-4
    if math.abs((actual or 0) - expected) > eps then
        error(string.format("%s: expected %.6f, got %.6f (eps=%.6f)", msg or "assert_near", expected, actual or 0, eps), 2)
    end
end

local function assert_bounds(x, y, ctx)
    if x < -498.0 - 1e-6 or x > 498.0 + 1e-6 or y < -498.0 - 1e-6 or y > 498.0 + 1e-6 then
        error(string.format("%s: position out of [-498, +498]: (%.6f, %.6f)", ctx or "assert_bounds", x, y), 2)
    end
end

print("=== [1/4] Syntax Checks (loadfile) ===")
local files_to_syntax_check = {
    "server/scripts/default_arena/core/arena_bounds.lua",
    "server/scripts/default_arena/main.lua",
    "server/scripts/default_arena/data/skills/whirlwind_dash.lua",
    "client/main.lua"
}
for _, path in ipairs(files_to_syntax_check) do
    local chunk, err = loadfile(path)
    if not chunk then
        error("Syntax error in " .. path .. ": " .. tostring(err))
    end
    print("  OK syntax: " .. path)
end

-- Helper to isolate package.loaded between server and client test runs
local base_loaded = {}
for k, v in pairs(package.loaded) do
    base_loaded[k] = v
end
local original_path = package.path
local original_cpath = package.cpath

local function reset_lua_env()
    for k in pairs(package.loaded) do
        if base_loaded[k] == nil then
            package.loaded[k] = nil
        end
    end
    package.path = original_path
    package.cpath = original_cpath
end

-- ============================================================================
-- SERVER SIMULATION HARNESS (mirrors loci2d simulation.rs & intent_handler.rs)
-- ============================================================================
local function create_server_harness()
    reset_lua_env()
    package.path = "./server/scripts/default_arena/?.lua;" .. original_path

    local state = {
        tick = 0,
        entities = {},
        cmd_queue = nil, -- nil => immediate flush (intent handlers); table => deferred end-of-tick
        aoe_queries = {},
        max_pre_clamp_overshoot = 0.0
    }

    local function make_pos_ud(ent)
        return {
            x = ent.x,
            y = ent.y,
            x_float = function() return ent.x end,
            y_float = function() return ent.y end
        }
    end

    local function clamp_circle(x, y, radius)
        local r = radius or 2.0
        local smin, smax = -500.0 + r, 500.0 - r
        return math.max(smin, math.min(smax, x)), math.max(smin, math.min(smax, y))
    end

    local function apply_cmd(cmd)
        local e = state.entities[cmd.id]
        if cmd.kind == "destroy" then
            state.entities[cmd.id] = nil
            return
        end
        if not e then return end
        if cmd.kind == "pos" then
            e.x = cmd.x
            e.y = cmd.y
        elseif cmd.kind == "vel" then
            e.vx = cmd.x
            e.vy = cmd.y
        elseif cmd.kind == "prop" then
            e.props[cmd.key] = cmd.value
        end
    end

    local function push_or_apply(cmd)
        if state.cmd_queue then
            table.insert(state.cmd_queue, cmd)
        else
            apply_cmd(cmd)
        end
    end

    _G.dpairs = pairs
    _G.Loci = {
        Log = {
            info = function() end,
            warn = function() end,
            error = function(msg) print("[MockServer ERR] " .. tostring(msg)) end
        },
        get_entity_position = function(id)
            local e = state.entities[id]
            return e and make_pos_ud(e) or nil
        end,
        get_velocity = function(id)
            local e = state.entities[id]
            return e and { x = e.vx, y = e.vy } or nil
        end,
        get_entity_property = function(id, key)
            local e = state.entities[id]
            return e and e.props[key] or nil
        end,
        get_entities_in_radius = function(pos, radius)
            table.insert(state.aoe_queries, { x = pos.x, y = pos.y, r = radius })
            local res = {}
            local r2 = radius * radius
            for id, e in pairs(state.entities) do
                local dx = e.x - pos.x
                local dy = e.y - pos.y
                if (dx * dx + dy * dy) <= r2 then
                    table.insert(res, id)
                end
            end
            return res
        end,
        Commands = {
            set_position = function(id, vec)
                push_or_apply({ kind = "pos", id = id, x = vec.x, y = vec.y })
            end,
            set_velocity = function(id, vec)
                push_or_apply({ kind = "vel", id = id, x = vec.x, y = vec.y })
            end,
            set_property = function(id, key, value)
                push_or_apply({ kind = "prop", id = id, key = key, value = tostring(value) })
            end,
            destroy_entity = function(id)
                push_or_apply({ kind = "destroy", id = id })
            end
        }
    }

    dofile("server/scripts/default_arena/main.lua")

    local harness = { state = state }

    function harness.spawn_player(id, x, y, move_speed)
        state.entities[id] = {
            id = id,
            x = x or 0,
            y = y or 0,
            vx = 0,
            vy = 0,
            radius = 2.0,
            props = {}
        }
        state.cmd_queue = nil
        on_player_join(id)
        if move_speed then
            state.entities[id].props["move_speed"] = tostring(move_speed)
        end
        state.entities[id].x = x or 0
        state.entities[id].y = y or 0
        return state.entities[id]
    end

    function harness.move_intent(id, dx, dy)
        state.cmd_queue = nil -- IntentHandler flushes immediately
        return on_move_intent(id, dx, dy)
    end

    function harness.action_intent(id, ability_id, aim_x, aim_y)
        state.cmd_queue = nil -- IntentHandler flushes immediately
        return on_action(id, ability_id, aim_x, aim_y)
    end

    function harness.step_tick()
        state.tick = state.tick + 1
        state.cmd_queue = {}

        -- Engine Step 0: Script on_tick (runs BEFORE velocity integration)
        on_tick(state.tick)

        -- Engine Step 1: Integrate velocity and record any pre-clamp overshoot
        for _, e in pairs(state.entities) do
            e.x = e.x + e.vx
            e.y = e.y + e.vy
            local ox = math.max(0, math.abs(e.x) - 498.0)
            local oy = math.max(0, math.abs(e.y) - 498.0)
            state.max_pre_clamp_overshoot = math.max(state.max_pre_clamp_overshoot, ox, oy)
            e.x, e.y = clamp_circle(e.x, e.y, e.radius)
        end

        -- Engine Step 3: Dynamic Entity-vs-Entity Collision
        local ids = {}
        for id in pairs(state.entities) do
            table.insert(ids, id)
        end
        table.sort(ids)
        for i = 1, #ids do
            for j = i + 1, #ids do
                local a = state.entities[ids[i]]
                local b = state.entities[ids[j]]
                local dx = b.x - a.x
                local dy = b.y - a.y
                local dist = math.sqrt(dx * dx + dy * dy)
                local min_sum = a.radius + b.radius
                if dist < min_sum then
                    local nx, ny = 1, 0
                    if dist > 1e-6 then
                        nx, ny = dx / dist, dy / dist
                    end
                    local overlap = (min_sum - dist) * 0.5
                    a.x = a.x - nx * overlap
                    a.y = a.y - ny * overlap
                    b.x = b.x + nx * overlap
                    b.y = b.y + ny * overlap
                    on_collision(a.id, b.id)
                    a.x, a.y = clamp_circle(a.x, a.y, a.radius)
                    b.x, b.y = clamp_circle(b.x, b.y, b.radius)
                end
            end
        end

        -- Engine End of Tick: CommandBuffer::flush_and_apply
        local queue = state.cmd_queue
        state.cmd_queue = nil
        for _, cmd in ipairs(queue) do
            apply_cmd(cmd)
        end
    end

    return harness
end

print("=== [2/4] Server Wall Collision & Dash Projection Tests ===")

-- Test A: Walk at speed = 3.0 & speed = 3.2 (Arya) across all 4 walls with zero CommandBuffer lag
do
    for _, spd in ipairs({ 3.0, 3.2 }) do
        local h = create_server_harness()
        local p = h.spawn_player(1, 490.0, 0.0, spd)
        h.move_intent(1, 1, 0)

        for t = 1, 10 do
            h.step_tick()
            assert_bounds(p.x, p.y, "Walk +X speed=" .. spd)
        end

        assert_near(p.x, 498.0, 1e-4, "Stops right at +498 wall")
        assert_near(p.vx, 0.0, 1e-6, "Zero residual vx on +498 wall")
        assert_near(h.state.max_pre_clamp_overshoot, 0.0, 1e-6, "Projected velocity never overshot +498 pre-clamp (spd=" .. spd .. ")")

        -- Verify exact arrival tick also had vx == 0 (no 1-tick CommandBuffer lag)
        local h2 = create_server_harness()
        local p2 = h2.spawn_player(1, 493.0, 0.0, 3.0)
        h2.move_intent(1, 1, 0)
        h2.step_tick() -- moves 493 -> 496, queues vx = 2.0
        assert_near(p2.x, 496.0, 1e-5, "Tick 1 reaches 496")
        assert_near(p2.vx, 2.0, 1e-5, "Tick 1 broadcasts exact remaining distance 2.0")
        h2.step_tick() -- integrates 496 -> 498, flushes vx = 0
        assert_near(p2.x, 498.0, 1e-5, "Tick 2 arrives at 498")
        assert_near(p2.vx, 0.0, 1e-6, "Tick 2 arrival snapshot has vx == 0 immediately (no 1-tick lag)")

        -- Test -X, -Y, +Y walls as well
        local walls = {
            { x = -490, y = 0, dx = -1, dy = 0, ex = -498, ey = 0 },
            { x = 0, y = 490, dx = 0, dy = 1, ex = 0, ey = 498 },
            { x = 0, y = -490, dx = 0, dy = -1, ex = 0, ey = -498 }
        }
        for idx, w in ipairs(walls) do
            local hw = create_server_harness()
            local pw = hw.spawn_player(1, w.x, w.y, spd)
            hw.move_intent(1, w.dx, w.dy)
            for _ = 1, 10 do
                hw.step_tick()
                assert_bounds(pw.x, pw.y, "Wall case " .. idx)
            end
            assert_near(pw.x, w.ex, 1e-4, "Wall X case " .. idx)
            assert_near(pw.y, w.ey, 1e-4, "Wall Y case " .. idx)
            assert_near(pw.vx, 0.0, 1e-6, "Wall vx=0 case " .. idx)
            assert_near(pw.vy, 0.0, 1e-6, "Wall vy=0 case " .. idx)
            assert_near(hw.state.max_pre_clamp_overshoot, 0.0, 1e-6, "Zero overshoot case " .. idx)

            -- Immediate departure when reversing off the wall
            hw.move_intent(1, -w.dx, -w.dy)
            hw.step_tick()
            assert(math.abs(pw.x - w.ex) > 0.1 or math.abs(pw.y - w.ey) > 0.1, "Must reverse off wall immediately")
        end
    end
    print("  OK Walk limits, 0-lag arrival velocity & 4-wall recovery (speed 3.0 & 3.2)")
end

-- Test B: Diagonal wall slide & corner stop
do
    local h = create_server_harness()
    local p = h.spawn_player(1, 496.0, 10.0, 3.2)
    h.move_intent(1, 1, -1) -- Northeast
    for _ = 1, 5 do
        h.step_tick()
        assert_bounds(p.x, p.y, "Diagonal slide")
    end
    assert_near(p.x, 498.0, 1e-4, "Clamped X at 498 during Northeast wall slide")
    assert_near(p.vx, 0.0, 1e-6, "Normal vx zeroed on wall slide")
    assert(p.vy < -2.0 and p.y < 2.0, "Tangential vy preserved during wall slide")

    -- Corner lock (498, 498) moving Southeast
    local hc = create_server_harness()
    local pc = hc.spawn_player(1, 495.0, 495.0, 3.2)
    hc.move_intent(1, 1, 1)
    for _ = 1, 6 do
        hc.step_tick()
        assert_bounds(pc.x, pc.y, "Corner lock")
    end
    assert_near(pc.x, 498.0, 1e-4, "Corner X stops at 498")
    assert_near(pc.y, 498.0, 1e-4, "Corner Y stops at 498")
    assert_near(pc.vx, 0.0, 1e-6, "Corner vx == 0")
    assert_near(pc.vy, 0.0, 1e-6, "Corner vy == 0")
    assert_near(hc.state.max_pre_clamp_overshoot, 0.0, 1e-6, "Zero overshoot on corner")
    print("  OK Diagonal wall sliding and corner clamping")
end

-- Test C: Whirlwind Dash (5.0 un/tick, 4 ticks) — stationary, near wall, at wall, diagonal
do
    -- Stationary caster near right wall (player_intents[1] == nil)
    local h = create_server_harness()
    local p = h.spawn_player(1, 490.0, 0.0, 3.2)
    local ok, err = h.action_intent(1, 3, 1, 0) -- Slot 3 = whirlwind_dash
    assert(ok, "whirlwind_dash failed: " .. tostring(err))
    assert(#h.state.aoe_queries > 0, "whirlwind_dash must sample AoE")
    for _, q in ipairs(h.state.aoe_queries) do
        assert_bounds(q.x, q.y, "whirlwind_dash AoE query")
    end
    for _ = 1, 6 do
        h.step_tick()
        assert_bounds(p.x, p.y, "Stationary whirlwind_dash +X")
    end
    assert_near(p.x, 498.0, 1e-4, "Stationary dash stops at +498")
    assert_near(p.vx, 0.0, 1e-6, "Stationary dash velocity projected to 0")
    assert_near(h.state.max_pre_clamp_overshoot, 0.0, 1e-6, "Stationary dash zero pre-clamp overshoot")

    -- Caster starting already at x=496 aiming East (initial dash impulse > remaining 2 units)
    local h2 = create_server_harness()
    local p2 = h2.spawn_player(1, 496.0, 0.0, 3.2)
    assert(h2.action_intent(1, 3, 1, 0))
    assert(p2.vx <= 2.0 + 1e-6, "on_action immediately projects initial dash velocity <= 2.0")
    h2.step_tick()
    assert_near(p2.x, 498.0, 1e-5, "Lands cleanly at 498.0 on tick 1")
    assert_near(p2.vx, 0.0, 1e-6, "Dash velocity zeroed on arrival tick")

    -- Diagonal dash sliding along right wall
    local h3 = create_server_harness()
    local p3 = h3.spawn_player(1, 496.0, 0.0, 3.2)
    assert(h3.action_intent(1, 3, 1, -1)) -- Northeast
    for _ = 1, 4 do
        h3.step_tick()
        assert_bounds(p3.x, p3.y, "Diagonal whirlwind_dash")
    end
    assert_near(p3.x, 498.0, 1e-4, "Diagonal dash holds X=498")
    assert_near(p3.vx, 0.0, 1e-6, "Diagonal dash zeros outward X velocity")
    assert(p3.y < -10.0, "Diagonal dash slides smoothly along wall (-Y)")
    assert_near(h3.state.max_pre_clamp_overshoot, 0.0, 1e-6, "Diagonal dash zero pre-clamp overshoot")
    print("  OK whirlwind_dash (stationary, near-wall initial projection, diagonal slide, AoE clamp)")
end

-- Test D: High-speed dash_speed = 22.0 (Trello card CXjaqwVl criterion)
do
    local h = create_server_harness()
    local p = h.spawn_player(1, 460.0, 0.0, 3.2)
    local ArenaBounds = require("core.arena_bounds")
    local whirlwind = require("data.skills.whirlwind_dash")
    local CharFactory = require("systems.character_factory")

    -- First advance a tick so CharacterFactory tick syncs
    h.step_tick()
    h.state.cmd_queue = nil
    local ok = whirlwind.on_execute(1, 1, 0, {
        id = "whirlwind_dash_test22",
        range = 88.0, -- 4 ticks * 22.0
        aoe_radius = whirlwind.aoe_radius,
        damage = whirlwind.damage,
        damage_type = whirlwind.damage_type,
        dash_speed = 22.0
    })
    assert(ok, "dash_speed=22.0 execute failed")
    for _ = 1, 6 do
        h.step_tick()
        assert_bounds(p.x, p.y, "High speed dash 22.0")
    end
    assert_near(p.x, 498.0, 1e-4, "dash_speed=22.0 stops exactly at +498")
    assert_near(p.vx, 0.0, 1e-6, "dash_speed=22.0 stops pushing wall")
    assert_near(h.state.max_pre_clamp_overshoot, 0.0, 1e-6, "dash_speed=22.0 zero pre-clamp tunneling")

    -- Diagonal 22.0 into corner (498, 498) from (470, 470)
    local h2 = create_server_harness()
    local p2 = h2.spawn_player(1, 470.0, 470.0, 3.2)
    h2.step_tick()
    h2.state.cmd_queue = nil
    local whirlwind2 = require("data.skills.whirlwind_dash")
    assert(whirlwind2.on_execute(1, 1, 1, {
        id = "whirlwind_dash_test22_diag",
        range = 88.0,
        aoe_radius = whirlwind2.aoe_radius,
        damage = whirlwind2.damage,
        damage_type = whirlwind2.damage_type,
        dash_speed = 22.0
    }))
    for _ = 1, 6 do
        h2.step_tick()
        assert_bounds(p2.x, p2.y, "High speed diagonal dash 22.0 into corner")
    end
    assert_near(p2.x, 498.0, 1e-4, "Diagonal dash 22.0 stops X at 498")
    assert_near(p2.y, 498.0, 1e-4, "Diagonal dash 22.0 stops Y at 498")
    assert_near(h2.state.max_pre_clamp_overshoot, 0.0, 1e-6, "Diagonal dash 22.0 zero tunneling")
    print("  OK High-speed dash_speed=22.0 (straight & corner, zero tunneling)")
end

-- Test E: Player-vs-Player collision near arena boundary (no regression & clamped)
do
    local h = create_server_harness()
    local p1 = h.spawn_player(1, 493.0, 0.0, 3.2)
    local p2 = h.spawn_player(2, 497.5, 0.0, 3.2)
    h.step_tick() -- populate last_tick_positions
    h.move_intent(1, 1, 0) -- P1 walks into P2 sitting against the right wall
    for _ = 1, 8 do
        h.step_tick()
        assert_bounds(p1.x, p1.y, "P1 near-wall collision")
        assert_bounds(p2.x, p2.y, "P2 near-wall collision")
        local dist = math.sqrt((p1.x - p2.x)^2 + (p1.y - p2.y)^2)
        assert(dist >= 3.99, string.format("Players overlapped near wall: dist=%.3f", dist))
    end
    assert(p2.x <= 498.0 + 1e-6 and p1.x <= 494.5, "P2 held in bounds and P1 blocked behind P2")
    print("  OK Player-vs-player collision near boundary preserves separation & bounds")
end

-- Test E2: on_move_intent updates player_intents during active dash (pre-existing bug fix)
do
    -- Case 1: Holding East -> dash -> release keys mid-dash -> must stop cleanly once dash ends
    local h1 = create_server_harness()
    local p1 = h1.spawn_player(1, 0.0, 0.0, 3.2)
    h1.move_intent(1, 1, 0) -- start walking +X
    h1.step_tick()
    assert(h1.action_intent(1, 3, 1, 0)) -- start whirlwind_dash (4 ticks: until tick 5)
    h1.step_tick() -- tick 2 (mid-dash)
    assert(h1.move_intent(1, 0, 0)) -- player releases WASD during dash!
    assert_near(p1.vx, 5.0, 1e-5, "Dash velocity stays active mid-dash after key release")

    -- Advance past dash end (ticks 3..8)
    for _ = 1, 6 do
        h1.step_tick()
    end
    local x_after_dash = p1.x
    assert_near(p1.vx, 0.0, 1e-6, "Player stops cleanly after dash when keys released mid-dash")
    h1.step_tick()
    h1.step_tick()
    assert_near(p1.x, x_after_dash, 1e-6, "Player must not keep drifting after dash ends")

    -- Case 2: Holding East -> dash -> switch to West (-1, 0) mid-dash -> walks West after dash ends
    local h2 = create_server_harness()
    local p2 = h2.spawn_player(1, 0.0, 0.0, 3.2)
    h2.move_intent(1, 1, 0)
    h2.step_tick()
    assert(h2.action_intent(1, 3, 1, 0))
    h2.step_tick() -- tick 2 (mid-dash)
    assert(h2.move_intent(1, -1, 0)) -- switch intent to -X mid-dash
    assert_near(p2.vx, 5.0, 1e-5, "Dash continues forward until duration expires")
    for _ = 1, 5 do
        h2.step_tick()
    end
    assert(p2.vx < -3.0, "Post-dash velocity switches to updated West intent instead of stale East intent")
    print("  OK on_move_intent updates intent mid-dash (stop & redirect after dash ends)")
end

-- ============================================================================
-- CLIENT NETCODE & MAIN.LUA INTEGRATION HARNESS
-- ============================================================================
print("=== [3/4] Client Prediction, Reconciliation, Remote Clamping & VFX Tests ===")

local function create_client_harness()
    reset_lua_env()

    local sent_packets = {}
    local recv_queue = {}
    local drawn_ops = {}
    local keys_down = {}
    local mock_time = 100.0
    local dummy_sock = {
        settimeout = function() end,
        setsockname = function() end,
        setpeername = function() end,
        send = function(_, data) table.insert(sent_packets, data); return #data end,
        receive = function()
            if #recv_queue > 0 then
                return table.remove(recv_queue, 1)
            end
            return nil
        end,
        close = function() end
    }

    package.preload["socket"] = function()
        return {
            udp = function() return dummy_sock end,
            gettime = function() return mock_time end
        }
    end

    local dummy_font = {
        getWidth = function(_, s) return #tostring(s or "") * 8 end,
        getHeight = function() return 16 end
    }
    local dummy_canvas = { setFilter = function() end }
    _G.love = {
        getVersion = function() return 11 end,
        window = {
            getDPIScale = function() return 1 end,
            getMode = function() return 1280, 720, {} end,
            setMode = function() end,
            updateMode = function() end
        },
        graphics = {
            setDefaultFilter = function() end,
            setBackgroundColor = function() end,
            getShader = function() return nil end,
            setShader = function() end,
            getCanvas = function() return nil end,
            origin = function() end,
            setScissor = function() end,
            newFont = function() return dummy_font end,
            getFont = function() return dummy_font end,
            setFont = function() end,
            newCanvas = function() return dummy_canvas end,
            setCanvas = function() end,
            clear = function() end,
            getDimensions = function() return 1280, 720 end,
            setColor = function() end,
            setLineWidth = function() end,
            rectangle = function() end,
            ellipse = function() end,
            polygon = function() end,
            arc = function() end,
            print = function() end,
            printf = function() end,
            push = function() end,
            pop = function() end,
            translate = function() end,
            scale = function() end,
            draw = function() end,
            circle = function(mode, x, y, r)
                table.insert(drawn_ops, { kind = "circle", mode = mode, x = x, y = y, r = r })
            end,
            line = function(x1, y1, x2, y2)
                table.insert(drawn_ops, { kind = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
            end
        },
        keyboard = {
            isDown = function(k) return keys_down[k] == true end
        },
        mouse = {
            getPosition = function() return 640, 360 end
        },
        timer = {
            getTime = function() return mock_time end,
            getFPS = function() return 60 end
        },
        math = {
            random = math.random
        },
        filesystem = {
            getInfo = function() return nil end
        }
    }

    -- Clear global callbacks from server harness
    _G.on_tick = nil
    _G.on_player_join = nil
    _G.on_move_intent = nil
    _G.on_action = nil
    _G.on_collision = nil
    _G.on_player_leave = nil
    _G.Loci = nil

    local sdk_dir = os.getenv("LOCI_SDK_DIR") or "./client/loci2d"
    package.path = "./client/?.lua;" .. sdk_dir .. "/?.lua;" .. sdk_dir .. "/lib/?.lua;./client/loci2d/?.lua;./client/loci2d/lib/?.lua;" .. original_path
    package.cpath = sdk_dir .. "/lib/?.so;./client/loci2d/lib/?.so;" .. original_cpath

    dofile("client/main.lua")
    love.load()

    local loci = require("loci_client")
    local ok_schema, schema_mod = pcall(require, "loci.network.schema")
    loci._player_name = "LocalHero"
    loci._mock_time = mock_time

    local function get_pb()
        if ok_schema and schema_mod and schema_mod.get_pb then
            return schema_mod.get_pb()
        end
        local ok_pb, pb_mod = pcall(require, "pb")
        return ok_pb and pb_mod or nil
    end

    local function to_bits(v)
        return math.floor(v * 65536 + 0.5)
    end

    local function build_world_state(tick, ts_ms, ents)
        local packed = {}
        for _, e in ipairs(ents) do
            local props = {}
            if e.props then
                for k, v in pairs(e.props) do
                    table.insert(props, { key = k, value = tostring(v) })
                end
            end
            table.insert(packed, {
                id = e.id,
                name = e.name,
                position = { x_bits = to_bits(e.x), y_bits = to_bits(e.y) },
                velocity = { x_bits = to_bits(e.vx or 0), y_bits = to_bits(e.vy or 0) },
                properties = props
            })
        end
        return {
            tick = tick,
            timestamp = ts_ms,
            match_state = 0,
            entities = packed
        }
    end

    local function push_snapshot(tick, ts_ms, ents)
        local st = build_world_state(tick, ts_ms, ents)
        st._receive_time = mock_time
        loci._handle_world_state(st)
    end

    local function enqueue_udp_snapshot(tick, ts_ms, ents)
        local pb = get_pb()
        assert(pb, "pb must be loaded")
        local bytes = pb.encode("loci2d.ServerPacket", {
            sequence_id = tick,
            world_state = build_world_state(tick, ts_ms, ents)
        })
        assert(bytes, "failed to encode loci2d.ServerPacket")
        table.insert(recv_queue, bytes)
    end

    local function advance_time(dt)
        mock_time = mock_time + dt
        loci._mock_time = mock_time
    end

    return {
        loci = loci,
        keys_down = keys_down,
        drawn_ops = drawn_ops,
        push_snapshot = push_snapshot,
        enqueue_udp_snapshot = enqueue_udp_snapshot,
        advance_time = advance_time
    }
end

-- Client Test F1: Local walk prediction at wall + no reconciliation bounce-back
do
    local c = create_client_harness()
    assert(c.loci._prediction_handler ~= nil, "client/main.lua must register loci._prediction_handler")

    c.push_snapshot(10, 1000, {
        { id = 1, name = "LocalHero", x = 496.0, y = 0.0, vx = 0, vy = 0, props = { move_speed = "3.2" } }
    })
    local me = c.loci.get_my_entity()
    assert(me ~= nil, "my_entity should spawn")

    -- Simulate key D held
    c.keys_down["d"] = true
    c.advance_time(0.016)
    love.update(0.016) -- update_movement sends move(1, 0) -> _active_move_dx = 1

    for f = 1, 15 do
        c.advance_time(1/30)
        -- Server authoritative snapshot hits 498.0 and stops
        love.update(1/30)
        assert_bounds(me.x, me.y, "Client predicted walk at frame " .. f)
        c.push_snapshot(10 + f, 1000 + f * 33, {
            { id = 1, name = "LocalHero", x = 498.0, y = 0.0, vx = 0, vy = 0, props = { move_speed = "3.2" } }
        })
    end
    assert_near(me.x, 498.0, 1e-4, "Local walk clamped smoothly at 498.0")
    assert_near(me._error_x or 0, 0.0, 1e-4, "No reconciliation error accumulated on wall")
    assert_near(me.vx or 0, 0.0, 1e-4, "Outward vx zeroed at +498")

    -- Now hold W+D for diagonal slide along right wall
    c.keys_down["w"] = true
    c.advance_time(0.016)
    love.update(0.016)
    c.advance_time(0.050)
    love.update(0.050)
    assert_near(me.x, 498.0, 1e-4, "Diagonal slide keeps x at 498")
    assert_near(me.vx or 0, 0.0, 1e-4, "Diagonal slide keeps vx == 0")
    assert(me.vy < -1.0 and me.y < -1.0, "Diagonal slide preserves tangential -Y motion")
    print("  OK Client walk prediction, zero-bounce reconciliation & diagonal wall slide")
end

-- Client Test F2: Local dash (5.0 and 22.0) via full UDP poll -> reconcile -> clamp cycle ("efeito mola")
do
    for _, spd in ipairs({ 5.0, 22.0 }) do
        local c = create_client_harness()
        c.push_snapshot(20, 2000, {
            {
                id = 1, name = "LocalHero", x = 494.0, y = 0.0, vx = spd, vy = 0,
                props = { move_speed = "3.2", dashing_until = "25" }
            }
        })
        local me = c.loci.get_my_entity()
        me.vx = spd
        me.vy = 0

        -- Enqueue real ServerPacket at nx = 498.0 to arrive during poll_network inside loci.update(dt):
        -- predict_local_player runs first (overshooting past 498 during dash because SDK bypasses _prediction_handler),
        -- reconcile_position sees err_x = 498 - overshoot (< -2px), then love.update clamps to 498 & clears _error_x!
        c.enqueue_udp_snapshot(21, 2050, {
            {
                id = 1, name = "LocalHero", x = 498.0, y = 0.0, vx = 0, vy = 0,
                props = { move_speed = "3.2", dashing_until = "25" }
            }
        })
        c.advance_time(0.050)
        love.update(0.050)

        assert_near(me.x, 498.0, 1e-4, "Post-update clamp forces me.x == 498 (dash_speed=" .. spd .. ")")
        assert_near(me._error_x or 0, 0.0, 1e-4, "Post-update clamp clears _error_x so no bounce-back (dash_speed=" .. spd .. ")")
        assert_near(me.vx or 0, 0.0, 1e-4, "Dash outward vx zeroed on clamp (dash_speed=" .. spd .. ")")

        -- Run 20 subsequent frames and confirm ZERO spring-back away from 498.0
        for f = 1, 20 do
            c.advance_time(0.016)
            love.update(0.016)
            assert_near(me.x, 498.0, 1e-4, "No spring-back on frame " .. f .. " (dash_speed=" .. spd .. ")")
        end
    end
    print("  OK Client dash UDP reconciliation eliminates spring-back (5.0 & 22.0)")
end

-- Client Test F3: Remote entity 80ms jitter extrapolation clamped inside [-498, +498]
do
    local c = create_client_harness()
    c.push_snapshot(100, 3000, {
        { id = 1, name = "LocalHero", x = 0.0, y = 0.0, vx = 0, vy = 0 },
        { id = 2, name = "Enemy", x = 495.0, y = 0.0, vx = 3.0, vy = 0 }
    })
    c.advance_time(0.033)
    c.push_snapshot(101, 3033, {
        { id = 1, name = "LocalHero", x = 0.0, y = 0.0, vx = 0, vy = 0 },
        -- Even if an old packet arrived with positive velocity at x=498:
        { id = 2, name = "Enemy", x = 498.0, y = 0.0, vx = 5.0, vy = 0 }
    })

    -- Advance by interpolation_delay (50ms) + 80ms jitter (= 130ms) without new snapshots
    -- So render_time = (t101 + 0.130) - 0.050 = t101 + 0.080 (inside 100ms extrapolation cap!)
    c.advance_time(0.130)
    love.update(0.016)

    local enemy = c.loci.entities[2]
    assert(enemy ~= nil, "Enemy entity must exist")
    assert_bounds(enemy.x, enemy.y, "Remote entity under jitter extrapolation")
    assert_near(enemy.x, 498.0, 1e-4, "Remote extrapolation clamped strictly to 498.0")
    assert_near(enemy.vx, 0.0, 1e-4, "Remote outward velocity zeroed on clamp")
    print("  OK Remote entity jitter extrapolation stays within [-498, +498]")
end

-- Client Test F4: whirlwind_dash VFX coordinates clamped inside arena bounds (NE & SW corners)
do
    -- Northeast corner (+498, -498)
    local c1 = create_client_harness()
    c1.push_snapshot(1, 100, {
        { id = 1, name = "LocalHero", x = 490.0, y = -498.0, vx = 0, vy = 0 }
    })
    local me1 = c1.loci.get_my_entity()
    c1.loci.on_action_cast(me1, 3, math.sqrt(0.5), -math.sqrt(0.5))
    c1.advance_time(0.36)
    love.update(0.36) -- inv_prog = 0.8 -> dist=16*0.707=11.31 -> raw=(501.31,-509.31), r=65*(0.7+0.4)=71.5
    for i = #c1.drawn_ops, 1, -1 do c1.drawn_ops[i] = nil end
    love.draw()

    local found_ne = false
    for _, op in ipairs(c1.drawn_ops) do
        if op.kind == "circle" and op.mode == "line" and math.abs(op.r - 71.5) < 0.05 then
            found_ne = true
            assert_near(op.x, 498.0 * 8.0, 1e-2, "NE Dash VFX X clamped to +498*8")
            assert_near(op.y, (-498.0 * 8.0) - 32.0, 1e-2, "NE Dash VFX Y clamped to -498*8 - body_offset")
        end
    end
    assert(found_ne, "Expected NE whirlwind_dash circle VFX draw call")

    -- Southwest corner (-498, +498)
    local c2 = create_client_harness()
    c2.push_snapshot(1, 100, {
        { id = 1, name = "LocalHero", x = -490.0, y = 498.0, vx = 0, vy = 0 }
    })
    local me2 = c2.loci.get_my_entity()
    c2.loci.on_action_cast(me2, 3, -math.sqrt(0.5), math.sqrt(0.5))
    c2.advance_time(0.36)
    love.update(0.36)
    for i = #c2.drawn_ops, 1, -1 do c2.drawn_ops[i] = nil end
    love.draw()

    local found_sw = false
    for _, op in ipairs(c2.drawn_ops) do
        if op.kind == "circle" and op.mode == "line" and math.abs(op.r - 71.5) < 0.05 then
            found_sw = true
            assert_near(op.x, -498.0 * 8.0, 1e-2, "SW Dash VFX X clamped to -498*8")
            assert_near(op.y, (498.0 * 8.0) - 32.0, 1e-2, "SW Dash VFX Y clamped to +498*8 - body_offset")
        end
    end
    assert(found_sw, "Expected SW whirlwind_dash circle VFX draw call")
    print("  OK whirlwind_dash VFX coordinates clamped inside safe bounds")
end

-- Client Test F5: Inward reconciliation error preserved while pushing against wall (review item 1)
do
    -- +X wall (498) with server at 460 while client holds key D into the wall
    local c1 = create_client_harness()
    c1.push_snapshot(10, 1000, {
        { id = 1, name = "LocalHero", x = 498.0, y = 0.0, vx = 0, vy = 0, props = { move_speed = "3.0" } }
    })
    local me1 = c1.loci.get_my_entity()
    c1.keys_down["d"] = true

    local dt = 1 / 60
    for frame = 1, 120 do
        if frame % 2 == 0 then
            c1.enqueue_udp_snapshot(10 + math.floor(frame / 2), 1000 + math.floor(frame * 1000 / 60), {
                { id = 1, name = "LocalHero", x = 460.0, y = 0.0, vx = 0, vy = 0, props = { move_speed = "3.0" } }
            })
        end
        c1.advance_time(dt)
        love.update(dt)
        assert_bounds(me1.x, me1.y, "Inward reconciliation at +498 wall")
    end
    assert(me1.x < 475.0, string.format("Client must pull inward from 498 even while holding D, got %.2f", me1.x))

    -- Releasing key D converges all the way to authoritative 460
    c1.keys_down["d"] = nil
    for frame = 121, 160 do
        if frame % 2 == 0 then
            c1.enqueue_udp_snapshot(10 + math.floor(frame / 2), 1000 + math.floor(frame * 1000 / 60), {
                { id = 1, name = "LocalHero", x = 460.0, y = 0.0, vx = 0, vy = 0, props = { move_speed = "3.0" } }
            })
        end
        c1.advance_time(dt)
        love.update(dt)
    end
    assert_near(me1.x, 460.0, 2.01, "Converges within reconciliation_threshold (2.0) of authoritative 460 after releasing key")

    -- Symmetric check on -X wall (-498) with server at -460 while holding A
    local c2 = create_client_harness()
    c2.push_snapshot(10, 1000, {
        { id = 1, name = "LocalHero", x = -498.0, y = 0.0, vx = 0, vy = 0, props = { move_speed = "3.0" } }
    })
    local me2 = c2.loci.get_my_entity()
    c2.keys_down["a"] = true
    for frame = 1, 120 do
        if frame % 2 == 0 then
            c2.enqueue_udp_snapshot(10 + math.floor(frame / 2), 1000 + math.floor(frame * 1000 / 60), {
                { id = 1, name = "LocalHero", x = -460.0, y = 0.0, vx = 0, vy = 0, props = { move_speed = "3.0" } }
            })
        end
        c2.advance_time(dt)
        love.update(dt)
        assert_bounds(me2.x, me2.y, "Inward reconciliation at -498 wall")
    end
    assert(me2.x > -475.0, string.format("Client must pull inward from -498 while holding A, got %.2f", me2.x))

    -- Residual outward error at wall is blocked so decay_error never pushes outside bounds
    local c3 = create_client_harness()
    c3.push_snapshot(10, 1000, {
        { id = 1, name = "LocalHero", x = 496.0, y = 0.0, vx = 0, vy = 0, props = { move_speed = "3.0" } }
    })
    local me3 = c3.loci.get_my_entity()
    c3.keys_down["d"] = true
    c3.advance_time(0.016)
    love.update(0.016) -- update_movement sends move(1, 0) -> _active_move_dx = 1
    me3._error_x = 12.0 -- residual outward error while pushing into +498 wall
    c3.advance_time(0.050)
    love.update(0.050)
    assert_near(me3.x, 498.0, 1e-4, "Outward residual error blocked at +498 wall")
    assert_near(me3._error_x or 0, 0.0, 1e-4, "Outward error clamped to 0 at +498")
    print("  OK Inward reconciliation error preserved while blocking outward overshoot at walls")
end

-- Client Test F6: Dash overshoot compensated when server keeps player inward (e.g. knockback/body-block)
do
    local c = create_client_harness()
    c.push_snapshot(20, 2000, {
        {
            id = 1, name = "LocalHero", x = 494.0, y = 0.0, vx = 22.0, vy = 0,
            props = { move_speed = "3.2", dashing_until = "25" }
        }
    })
    local me = c.loci.get_my_entity()
    me.vx = 22.0
    me.vy = 0

    -- Client dash predicts 494 -> 527; server keeps player at 480 (err = -47)
    -- Clamp moves 527 -> 498 (shift = -29), compensating _error_x to -18
    c.enqueue_udp_snapshot(21, 2050, {
        {
            id = 1, name = "LocalHero", x = 480.0, y = 0.0, vx = 0, vy = 0,
            props = { move_speed = "3.2", dashing_until = "25" }
        }
    })
    c.advance_time(0.050)
    love.update(0.050)

    assert_near(me.x, 498.0, 1e-4, "Dash clamped to 498 on overshoot frame")
    assert_near(me._error_x, -18.0, 1e-3, "Post-update clamp preserves remaining -18 error toward server=480")

    local dt = 1 / 60
    for frame = 1, 30 do
        if frame % 2 == 0 then
            c.enqueue_udp_snapshot(21 + math.floor(frame / 2), 2050 + math.floor(frame * 1000 / 60), {
                {
                    id = 1, name = "LocalHero", x = 480.0, y = 0.0, vx = 0, vy = 0,
                    props = { move_speed = "3.2", dashing_until = "25" }
                }
            })
        end
        c.advance_time(dt)
        love.update(dt)
        assert(me.x >= 479.8 and me.x <= 498.0 + 1e-4,
            string.format("Dash+knockback should converge toward 480 without overshooting inward, got %.3f", me.x))
    end
    assert_near(me.x, 480.0, 2.01, "Dash overshoot + inward server position settles within reconciliation_threshold of 480")
    print("  OK Dash overshoot compensation settles smoothly to inward server position")
end

-- Client Test F7: Entity clamp filter clamps player entities only, sparing non-player entities
do
    local c = create_client_harness()
    c.push_snapshot(1, 100, {
        { id = 1, name = "LocalHero", x = 0.0, y = 0.0, vx = 0, vy = 0 },
        { id = 2, name = "EnemyPlayer", x = 505.0, y = 0.0, vx = 0, vy = 0 },
        { id = 3, name = "ThrownBlade", x = 505.0, y = 0.0, vx = 0, vy = 0, props = { entity_type = "projectile" } },
        { id = 4, name = "blade_projectile", x = -505.0, y = 0.0, vx = 0, vy = 0 }
    })
    c.advance_time(0.016)
    love.update(0.016)

    assert_near(c.loci.entities[2].x, 498.0, 1e-4, "Player entity clamped to +498")
    assert_near(c.loci.entities[3].x, 505.0, 1e-4, "Projectile entity_type skipped by player clamp")
    assert_near(c.loci.entities[4].x, -505.0, 1e-4, "Projectile blueprint skipped by player clamp")
    print("  OK Client clamp filter applies to players while sparing projectiles")
end

print("=== [4/4] All automated wall collision tests PASSED ===")
