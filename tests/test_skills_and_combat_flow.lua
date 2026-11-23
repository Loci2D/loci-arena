-- Integration & Skill tests for server combat flow (Phase 3 of Issue #59)
-- Covers slash, fireball, blade_throw, fury_reward, shield, whirlwind_dash AoE damage,
-- on_action CC/death/slot guards, character swap (999), and end-to-end duel + KDA + passive + respawn.

package.path = "./server/scripts/default_arena/?.lua;./client/src/?.lua;./?.lua;" .. package.path

local function assert_near(actual, expected, eps, msg)
    eps = eps or 1e-4
    if math.abs((actual or 0) - expected) > eps then
        error(string.format("%s: expected %.6f, got %.6f (eps=%.6f)", msg or "assert_near", expected, actual or 0, eps), 2)
    end
end

local function with_fixed_random(value, fn)
    local orig_random = math.random
    math.random = function() return value end
    local ok, err = pcall(fn)
    math.random = orig_random
    if not ok then
        error(err, 2)
    end
end

local function make_server_env(load_main)
    local entities = {}
    local logs = {}

    local function make_pos_ud(ent)
        return {
            x = ent.x,
            y = ent.y,
            x_float = function() return ent.x end,
            y_float = function() return ent.y end,
        }
    end

    _G.dpairs = pairs
    _G.Loci = {
        Log = {
            info = function(msg) table.insert(logs, { level = "info", msg = msg }) end,
            warn = function(msg) table.insert(logs, { level = "warn", msg = msg }) end,
            error = function(msg) table.insert(logs, { level = "error", msg = msg }) end,
        },
        get_entity_position = function(id)
            local e = entities[id]
            return e and make_pos_ud(e) or nil
        end,
        get_velocity = function(id)
            local e = entities[id]
            return e and { x = e.vx, y = e.vy } or nil
        end,
        get_entity_property = function(id, key)
            local e = entities[id]
            return e and e.props[key] or nil
        end,
        get_entities_in_radius = function(pos, radius)
            local res = {}
            local r2 = radius * radius
            for id, e in pairs(entities) do
                local dx = e.x - pos.x
                local dy = e.y - pos.y
                if (dx * dx + dy * dy) <= r2 then
                    table.insert(res, id)
                end
            end
            table.sort(res)
            return res
        end,
        Commands = {
            set_position = function(id, vec)
                local e = entities[id]
                if e then
                    e.x = vec.x
                    e.y = vec.y
                end
            end,
            set_velocity = function(id, vec)
                local e = entities[id]
                if e then
                    e.vx = vec.x
                    e.vy = vec.y
                end
            end,
            set_property = function(id, key, value)
                local e = entities[id]
                if e then
                    e.props[key] = tostring(value)
                end
            end,
            destroy_entity = function(id)
                entities[id] = nil
            end,
        },
    }

    -- Reset all server modules for clean isolation
    for k in pairs(package.loaded) do
        if k == "respawn_system"
            or k:match("^core%.")
            or k:match("^systems%.")
            or k:match("^data%.") then
            package.loaded[k] = nil
        end
    end

    local CombatSystem = require("core.combat_system")
    local CharacterFactory = require("systems.character_factory")
    local RespawnSystem = require("respawn_system")

    if load_main then
        dofile("server/scripts/default_arena/main.lua")
    end

    local function spawn_entity(id, char_name, team, x, y)
        entities[id] = {
            id = id,
            x = x or 0,
            y = y or 0,
            vx = 0,
            vy = 0,
            props = { team = tostring(team or "1"), kills = "0", deaths = "0", is_dead = "false" },
        }
        CharacterFactory.create_character(id, char_name or "default")
        return entities[id]
    end

    local function join_player(id, x, y)
        entities[id] = {
            id = id,
            x = x or 0,
            y = y or 0,
            vx = 0,
            vy = 0,
            props = {},
        }
        on_player_join(id)
        return entities[id]
    end

    local function step_ticks(start_tick, end_tick)
        for t = start_tick, end_tick do
            on_tick(t)
            for _, e in pairs(entities) do
                e.x = math.max(-498.0, math.min(498.0, e.x + e.vx))
                e.y = math.max(-498.0, math.min(498.0, e.y + e.vy))
            end
        end
    end

    return {
        entities = entities,
        logs = logs,
        CombatSystem = CombatSystem,
        CharacterFactory = CharacterFactory,
        RespawnSystem = RespawnSystem,
        spawn_entity = spawn_entity,
        join_player = join_player,
        step_ticks = step_ticks,
    }
end

local passed = 0
local function run_test(name, fn)
    fn()
    passed = passed + 1
    print("  [PASS] " .. name)
end

print("=== Phase 3: Skills & Combat Flow Integration Tests ===")

run_test("slash deals physical damage once to enemies in front, sparing allies and behind targets", function()
    local env = make_server_env(false)
    local CF = env.CharacterFactory

    -- Caster (arya, team 1) at (0, 0), aim (0, 0) defaults to (+1, 0)
    -- Slash range=16.0, aoe_radius=7.0, sample points at x=4.0 and x=8.0 (reach: x in [-3, 15])
    env.spawn_entity(1, "arya", "1", 0, 0)
    local enemy_front = env.spawn_entity(2, "default", "2", 3.5, 0) -- inside BOTH sample circles
    local ally_front = env.spawn_entity(3, "default", "1", 3.5, 0)  -- same team -> spared
    local enemy_behind = env.spawn_entity(4, "default", "2", -6.0, 0) -- behind caster -> spared
    local enemy_far = env.spawn_entity(5, "default", "2", 20.0, 0)  -- beyond the melee reach (15) -> spared

    local initial_hp = tonumber(enemy_front.props.hp)
    with_fixed_random(0.99, function()
        local ok = CF.execute_skill(1, "slash", 0, 0)
        assert(ok == true)
    end)

    -- Default has phys_def=80 -> mitigation = 80/180; slash dmg=350 -> 350 * (100/180) = 194.444...
    local expected_dmg = 350 * (100 / 180)
    assert_near(tonumber(enemy_front.props.hp), initial_hp - expected_dmg, 1e-4, "enemy hit once by slash")
    assert(ally_front.props.hp == "5000", "ally must not take friendly fire from slash")
    assert(enemy_behind.props.hp == "5000", "enemy behind caster must not be hit")
    assert(enemy_far.props.hp == "5000", "slash is melee: enemy beyond ~2 character heights must not be hit")
end)

run_test("fireball deals magical AoE damage at 70% range and spares allies", function()
    local env = make_server_env(false)
    local CF = env.CharacterFactory

    -- Fireball range=64.0 -> explosion center at 0.7 * 64 = 44.8, aoe_radius=9.0
    env.spawn_entity(1, "mage", "1", 0, 0)
    local enemy_in = env.spawn_entity(2, "warrior", "2", 46, 2)   -- dist from (44.8,0) ~ 2.3 < 9
    local ally_in = env.spawn_entity(3, "default", "1", 44, 0)    -- same team -> spared
    local enemy_out = env.spawn_entity(4, "warrior", "2", 60, 0)  -- dist 15.2 > 9 -> spared

    with_fixed_random(0.99, function()
        local ok = CF.execute_skill(1, "fireball", 10, 0)
        assert(ok == true)
    end)

    -- Warrior mag_def=40 -> mitigation = 40/140; fireball dmg=500 -> 500 * (100/140)
    local expected_dmg = 500 * (100 / 140)
    assert_near(tonumber(enemy_in.props.hp), 6000 - expected_dmg, 1e-4, "enemy in blast takes magical damage")
    assert(ally_in.props.hp == "5000", "ally in blast spared")
    assert(enemy_out.props.hp == "6000", "enemy outside blast spared")
end)

run_test("blade_throw stops at first enemy, stuns AoE targets, and disarms caster", function()
    local env = make_server_env(false)
    local CF = env.CharacterFactory

    CF.update_tick(100)
    env.spawn_entity(1, "arya", "1", 0, 0)
    local ally_path = env.spawn_entity(2, "default", "1", 6, 0)    -- ally in flight path must NOT stop blade
    local enemy_hit = env.spawn_entity(3, "default", "2", 12, 0)   -- first enemy at d=12 -> impact at x=12
    enemy_hit.vx, enemy_hit.vy = 2.0, 1.0
    local enemy_splash = env.spawn_entity(4, "default", "2", 16, 0) -- within aoe_radius=8.0 of x=12
    local enemy_far = env.spawn_entity(5, "default", "2", 25, 0)   -- beyond impact AoE -> unharmed

    with_fixed_random(0.99, function()
        local ok = CF.execute_skill(1, "blade_throw", 1, 0)
        assert(ok == true)
    end)

    -- Caster disarmed for 60 ticks (100 + 60 = 160)
    assert(env.entities[1].props.disarmed_until == "160", "caster must be disarmed for 60 ticks")
    assert(ally_path.props.hp == "5000", "ally in path must not take damage")

    -- Both enemy_hit and enemy_splash take 400 phys damage, 36-tick stun, and velocity reset
    local expected_dmg = 400 * (100 / 180)
    assert_near(tonumber(enemy_hit.props.hp), 5000 - expected_dmg, 1e-4)
    assert_near(tonumber(enemy_splash.props.hp), 5000 - expected_dmg, 1e-4)
    assert(enemy_hit.props.stunned_until == "136" and enemy_splash.props.stunned_until == "136")
    assert(enemy_hit.vx == 0 and enemy_hit.vy == 0)
    assert(enemy_far.props.hp == "5000" and enemy_far.props.stunned_until == "0")
end)

run_test("fury_reward enforces ally lock in team games, unlocks in 1v1, and forces crit when fury_active", function()
    local env = make_server_env(false)
    local CF = env.CharacterFactory

    -- Team game: Arya has living ally (id=2) and fury_active="false" -> blocked without cooldown/mana
    env.spawn_entity(1, "arya", "1", 0, 0)
    env.spawn_entity(2, "default", "1", -20, 0)
    local enemy = env.spawn_entity(3, "default", "2", 5, 0)

    local ok, err = CF.execute_skill(1, "fury_reward", 1, 0)
    assert(ok == false and err:find("bloqueada"))
    assert(enemy.props.hp == "5000")

    -- Activate fury -> succeeds, forces crit (500 * 2.25 * 100/180), and clears fury_active
    env.entities[1].props.fury_active = "true"
    with_fixed_random(0.99, function()
        ok = CF.execute_skill(1, "fury_reward", 1, 0)
        assert(ok == true)
    end)
    local expected_crit_dmg = 500 * (100 / 180) * 2.25
    assert_near(tonumber(enemy.props.hp), 5000 - expected_crit_dmg, 1e-4)
    assert(env.entities[1].props.fury_active == "false", "fury_active must reset after use")

    -- 1v1 mode (remove ally): unlocks even with fury_active="false"
    env.entities[2] = nil
    CF.update_tick(500) -- past cooldown
    with_fixed_random(0.99, function()
        ok = CF.execute_skill(1, "fury_reward", 1, 0)
        assert(ok == true, "fury_reward should unlock in 1v1 without allies")
    end)
end)

run_test("shield and whirlwind_dash apply defensive shield and AoE physical damage", function()
    local env = make_server_env(false)
    local CF = env.CharacterFactory

    CF.update_tick(50)
    local caster = env.spawn_entity(1, "arya", "1", 0, 0)
    caster.props.skills_list = caster.props.skills_list .. ",shield"
    local enemy = env.spawn_entity(2, "default", "2", 10, 0)

    assert(CF.execute_skill(1, "shield", 0, 0) == true)
    assert(caster.props.shield == "1000")
    assert(caster.props.shield_active == "1")
    assert(caster.props.shield_end_tick == "200") -- 50 + 150

    with_fixed_random(0.99, function()
        assert(CF.execute_skill(1, "whirlwind_dash", 1, 0) == true)
    end)
    assert(caster.props.dashing_until == "56", "dash lasts 6 ticks (50 + 6)")
    local expected_dmg = 450 * (100 / 180)
    assert_near(tonumber(enemy.props.hp), 5000 - expected_dmg, 1e-4)
end)

run_test("main.lua on_action enforces CC/death guards and character swap 999", function()
    local env = make_server_env(true)
    local p1 = env.join_player(1, 0, 0)
    local p2 = env.join_player(2, 4, 0)
    assert(p1.props.team == "1" and p2.props.team == "2")

    env.step_ticks(1, 10)

    -- Invalid slot
    local ok, err = on_action(1, 99, 1, 0)
    assert(ok == false and err:find("invalid slot"))

    -- Stunned blocks on_action until tick >= stunned_until
    p1.props.stunned_until = "15"
    ok, err = on_action(1, 1, 1, 0)
    assert(ok == false and err:find("Stun"))

    -- Paralyzed blocks on_action
    p1.props.stunned_until = "0"
    p1.props.paralyzed_until = "15"
    ok, err = on_action(1, 1, 1, 0)
    assert(ok == false and err:find("paralisado"))

    -- Disarmed blocks on_action
    p1.props.paralyzed_until = "0"
    p1.props.disarmed_until = "15"
    ok, err = on_action(1, 1, 1, 0)
    assert(ok == false and err:find("desarmado"))

    -- Advance past tick 15: CC expires and slot 1 (slash) executes
    env.step_ticks(11, 15)
    with_fixed_random(0.99, function()
        ok = on_action(1, 1, 1, 0)
        assert(ok == true)
    end)
    assert(tonumber(p2.props.hp) < 5500)

    -- O slash aplica cast_lock_ticks (casting_until = 24): expira o lock aqui para
    -- não interferir nas asserções de move_speed dos próximos ticks
    p1.props.casting_until = "0"

    -- Swap character via ability_id == 999 cycles arya -> default -> mage -> warrior -> arya
    assert(on_move_intent(1, -1, 0) == true)
    assert_near(p1.vx, -2.2, 1e-5, "arya base move_speed")

    assert(on_action(1, 999, 0, 0) == true)
    assert(p1.props.character_name == "default")
    env.step_ticks(16, 16)
    assert_near(p1.vx, -2.0, 1e-5, "intent speed updates to default move_speed=2.0")

    assert(on_action(1, 999, 0, 0) == true)
    assert(p1.props.character_name == "mage")
    env.step_ticks(17, 17)
    assert_near(p1.vx, -2.0, 1e-5, "intent speed updates to mage move_speed=2.0")

    assert(on_action(1, 999, 0, 0) == true)
    assert(p1.props.character_name == "warrior")
    env.step_ticks(18, 18)
    assert_near(p1.vx, -1.9, 1e-5, "intent speed updates to warrior move_speed=1.9")

    assert(on_action(1, 999, 0, 0) == true)
    assert(p1.props.character_name == "arya")

    -- Dead player cannot swap or cast
    env.RespawnSystem.mark_dead(1)
    ok, err = on_action(1, 999, 0, 0)
    assert(ok == false and err:find("morto"))
    ok, err = on_action(1, 1, 1, 0)
    assert(ok == false and err:find("morto"))
end)

run_test("End-to-end duel: blade_throw stun/disarm -> ally kill triggers Arya passive -> fury_reward kill -> respawn -> leave", function()
    local env = make_server_env(true)
    local p1 = env.join_player(1, 0, 0)     -- Team 1 (Arya)
    local p2 = env.join_player(2, 10, 0)    -- Team 2 (Arya)
    local p3 = env.join_player(3, 55, 0)    -- Team 1 (Arya)

    assert(p1.props.team == "1" and p2.props.team == "2" and p3.props.team == "1")

    -- Swap p2 to Mage so it has ranged fireball
    assert(on_action(2, 999, 0, 0) == true) -- default
    assert(on_action(2, 999, 0, 0) == true) -- mage
    assert(p2.props.character_name == "mage")

    env.step_ticks(1, 10)

    -- 1. p1 casts blade_throw (slot 4) hitting p2: stuns p2 (36 ticks), disarms p1 (60 ticks)
    with_fixed_random(0.99, function()
        assert(on_action(1, 4, 1, 0) == true)
    end)
    assert(p2.props.stunned_until == "46")
    assert(p1.props.disarmed_until == "70")
    assert(on_action(2, 1, 1, 0) == false, "stunned p2 cannot cast")
    assert(on_action(1, 1, 1, 0) == false, "disarmed p1 cannot cast")

    -- 2. Advance to tick 70 (both stun and disarm expired)
    env.step_ticks(11, 70)

    -- 3. Low-HP p3 gets eliminated by p2's fireball -> KDA updates + p1 (allied Arya) gets passive paralysis + fury
    p3.props.hp = "100"
    with_fixed_random(0.99, function()
        assert(on_action(2, 1, 1, 0) == true) -- fireball hits p3 at x=55 (10 + 0.7 * 64 = 54.8)
    end)
    assert(p3.props.hp == "0" and p3.props.is_dead == "true")
    assert(p3.props.deaths == "1" and p2.props.kills == "1")
    assert(p1.props.fury_active == "true")
    assert(p1.props.paralyzed_until == "160") -- 70 + 90
    assert(on_action(1, 2, 1, 0) == false, "paralyzed p1 cannot cast fury_reward yet")

    -- 4. Advance to tick 160: paralysis expires, p1 moves next to p2 and finishes p2 with fury_reward (slot 2)
    env.step_ticks(71, 160)
    p2.x, p2.y = 5, 0
    p2.props.hp = "200"
    with_fixed_random(0.99, function()
        assert(on_action(1, 2, 1, 0) == true)
    end)
    assert(p2.props.hp == "0" and p2.props.is_dead == "true")
    assert(p2.props.deaths == "1" and p1.props.kills == "1")
    assert(p1.props.fury_active == "false")

    -- 5. Advance to tick 460 (300 ticks after tick 160): both p3 (died at 70) and p2 (died at 160) have respawned
    env.step_ticks(161, 460)
    assert(p3.props.is_dead == "false" and p3.props.hp == p3.props.max_hp)
    assert(p2.props.is_dead == "false" and p2.props.hp == p2.props.max_hp)

    -- 6. p3 leaves team 1 (now team1=1, team2=1); next join p4 gets balanced onto team 1
    on_player_leave(3)
    assert(env.entities[3] == nil)
    local p4 = env.join_player(4, -10, 0)
    assert(p4.props.team == "1", "team balancing should allocate p4 to team 1 after p3 left")
end)

run_test("server publishes skill_ranges from data/skills and the client defaults never drift from it", function()
    local env = make_server_env(false)
    local SkillRanges = require("skill_ranges")
    SkillRanges.reset()

    -- Cada personagem publica alcance:raio das próprias skills (somente as que têm alcance)
    local expected_by_char = {
        arya = { "slash", "fury_reward", "whirlwind_dash", "blade_throw" },
        mage = { "fireball" },
    }
    local id = 0
    for char_name, skills in pairs(expected_by_char) do
        id = id + 1
        local ent = env.spawn_entity(id, char_name, "1", 0, 0)
        local published = SkillRanges.parse(ent.props.skill_ranges)
        for _, skill_name in ipairs(skills) do
            local data = require("data.skills." .. skill_name)
            assert(published[skill_name], char_name .. " must publish skill_ranges for " .. skill_name)
            assert_near(published[skill_name].range, data.range, 1e-3, skill_name .. " published range")
            assert_near(published[skill_name].aoe, data.aoe_radius, 1e-3, skill_name .. " published aoe")
        end
    end

    -- Skill sem alcance (shield) não entra na propriedade
    local built = SkillRanges.parse(env.CharacterFactory.build_skill_ranges({ "slash", "shield", "nao_existe" }))
    assert(built.slash and built.shield == nil and built.nao_existe == nil,
        "skills without range (shield) or unknown skills must not be published")
    assert(env.CharacterFactory.build_skill_ranges({}) == "", "no skills -> empty string")

    -- Anti-deriva: os padrões embutidos no cliente têm que ser iguais aos data/skills/*.lua
    for name, def in pairs(SkillRanges.DEFAULTS) do
        local data = require("data.skills." .. name)
        assert_near(def.range, data.range, 1e-3, "client default range drifted from server for " .. name)
        assert_near(def.aoe, data.aoe_radius, 1e-3, "client default aoe drifted from server for " .. name)
    end

    -- Anti-deriva de cooldowns e mana_cost em SkillRanges.SKILL_META (ticks a 30 Hz -> segundos)
    for name, meta in pairs(SkillRanges.SKILL_META) do
        local data = require("data.skills." .. name)
        assert_near(meta.cooldown * 30, data.cooldown, 1e-3, "client SKILL_META cooldown drifted from server for " .. name)
        assert_near(meta.mana_cost, data.mana_cost or 0, 1e-3, "client SKILL_META mana_cost drifted from server for " .. name)
    end
end)

run_test("cast_lock_ticks: attacks root via casting_until while whirlwind_dash and shield do not", function()
    local env = make_server_env(false)
    local CF = env.CharacterFactory

    CF.update_tick(200)
    local e = env.spawn_entity(1, "arya", "1", 0, 0)
    e.props.skills_list = e.props.skills_list .. ",shield"
    assert(e.props.casting_until == "0", "casting_until must be initialized to 0")

    -- Slash: cast_lock_ticks = 9 -> casting_until = 209, velocity zerada
    with_fixed_random(0.99, function()
        assert(CF.execute_skill(1, "slash", 1, 0) == true)
    end)
    assert(e.props.casting_until == "209", "slash must set casting_until = tick + 9")
    assert(e.vx == 0 and e.vy == 0, "cast lock must zero velocity")

    -- Fury reward (1v1: sem aliados na entidade -> desbloqueada): cast_lock_ticks = 24
    with_fixed_random(0.99, function()
        assert(CF.execute_skill(1, "fury_reward", 1, 0) == true)
    end)
    assert(e.props.casting_until == "224", "fury_reward must set casting_until = tick + 24")

    -- Blade throw: cast_lock_ticks = 24
    with_fixed_random(0.99, function()
        assert(CF.execute_skill(1, "blade_throw", 1, 0) == true)
    end)
    assert(e.props.casting_until == "224", "blade_throw must set casting_until = tick + 24")

    -- Expira o cast lock e avança tick
    CF.update_tick(300)
    assert(e.props.casting_until == "0", "casting_until must reset to 0 after expiry")

    -- Whirlwind dash: mobilidade via dashing_until, SEM casting_until
    with_fixed_random(0.99, function()
        assert(CF.execute_skill(1, "whirlwind_dash", 1, 0) == true)
    end)
    assert(e.props.casting_until == "0", "whirlwind_dash must not set casting_until")
    assert(e.props.dashing_until == "306", "whirlwind_dash must keep dashing_until mobility")

    -- Shield: buff instantâneo, sem cast lock
    CF.update_tick(400)
    assert(CF.execute_skill(1, "shield", 0, 0) == true)
    assert(e.props.casting_until == "0", "shield must not set casting_until")
end)

run_test("on_move_intent/on_tick root the caster during casting_until and resume the held intent after", function()
    local env = make_server_env(true)
    local p1 = env.join_player(1, 0, 0)  -- Time 1 (Arya)
    local p2 = env.join_player(2, 40, 0) -- Time 2, longe para não colidir

    env.step_ticks(1, 5)

    -- Slash no tick 5 -> casting_until = 14 (5 + 9)
    with_fixed_random(0.99, function()
        assert(on_action(1, 1, 1, 0) == true)
    end)
    assert(p1.props.casting_until == "14")

    -- Intenção de movimento durante o cast lock: aceita, mas zera velocidade
    assert(on_move_intent(1, 1, 0) == true)
    assert(p1.vx == 0 and p1.vy == 0, "cast lock must zero velocity on move intent")

    -- Ticks 6..13: enraizado, não avança
    env.step_ticks(6, 13)
    assert_near(p1.x, 0, 1e-4, "caster must not move while casting_until is active")
    assert(p1.vx == 0 and p1.vy == 0)

    -- Tick 14: lock expira -> intenção registrada retoma o movimento sem novo input
    env.step_ticks(14, 16)
    assert(p1.x > 0.5, "movement must resume right after cast lock expires")

    -- Whirlwind dash (slot 3): mobilidade preservada via dashing_until, sem cast lock
    with_fixed_random(0.99, function()
        assert(on_action(1, 3, 1, 0) == true)
    end)
    assert(p1.props.casting_until == "0", "whirlwind_dash must not set casting_until")
    assert(tostring(p1.props.dashing_until) == "22", "dash must last 6 ticks (16 + 6)")

    -- Durante o dash, o impulso físico prevalece sobre a intenção de movimento
    on_move_intent(1, -1, 0)
    env.step_ticks(17, 18)
    assert(p1.vx > 5, "dash velocity must prevail during whirlwind_dash, got vx=" .. tostring(p1.vx))
end)

run_test("whirlwind_dash cancels an active casting_until and does not freeze after the dash", function()
    local env = make_server_env(true)
    local p1 = env.join_player(1, 0, 0)    -- Time 1 (Arya)
    local p2 = env.join_player(2, 0, -40)  -- Time 2, em outra faixa para não colidir

    env.step_ticks(1, 5)

    -- Fury reward (slot 2) no tick 5 -> casting_until = 29 (5 + 24)
    with_fixed_random(0.99, function()
        assert(on_action(1, 2, 1, 0) == true)
    end)
    assert(p1.props.casting_until == "29")

    -- Whirlwind dash (slot 3) ainda no tick 5: mobilidade cancela o cast lock
    with_fixed_random(0.99, function()
        assert(on_action(1, 3, 1, 0) == true)
    end)
    assert(p1.props.casting_until == "0", "whirlwind_dash must clear casting_until")
    assert(tostring(p1.props.dashing_until) == "11", "dash must last 6 ticks (5 + 6)")

    -- Fim do dash no tick 11: o lock restante de fury_reward não pode congelar o jogador
    env.step_ticks(6, 11)
    assert(on_move_intent(1, 1, 0) == true)
    assert(p1.vx > 0, "movement must resume right after dash ends, got vx=" .. tostring(p1.vx))
end)

print(string.format("\n>>> Phase 3: All %d Skills & Combat Flow tests passed! <<<", passed))
