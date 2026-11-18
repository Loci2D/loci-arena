-- Unit tests for CombatSystem (Phase 1 of Issue #59)
-- Covers mitigation, damage types (physical/magical/true), crits, fragility,
-- shield absorption/expiration, lethal damage, KDA updates, and death hooks.

package.path = "./server/scripts/default_arena/?.lua;./?.lua;" .. package.path

local function assert_near(actual, expected, eps, msg)
    eps = eps or 1e-6
    if math.abs((actual or 0) - expected) > eps then
        error(string.format("%s: expected %.6f, got %.6f (eps=%.6f)", msg or "assert_near", expected, actual or 0, eps), 2)
    end
end

local function make_env()
    local props = {}
    local logs = {}

    local function ensure_entity(id)
        if not props[id] then
            props[id] = {}
        end
        return props[id]
    end

    _G.Loci = {
        Log = {
            info = function(msg) table.insert(logs, { level = "info", msg = msg }) end,
            warn = function(msg) table.insert(logs, { level = "warn", msg = msg }) end,
            error = function(msg) table.insert(logs, { level = "error", msg = msg }) end,
        },
        get_entity_property = function(id, key)
            local ent = props[id]
            return ent and ent[key] or nil
        end,
        Commands = {
            set_property = function(id, key, value)
                ensure_entity(id)[key] = tostring(value)
            end,
            set_velocity = function() end,
        },
    }

    -- Reset module state between test cases so RespawnSystem / CharacterFactory start clean
    package.loaded["core.combat_system"] = nil
    package.loaded["respawn_system"] = nil
    package.loaded["systems.character_factory"] = nil

    local CombatSystem = require("core.combat_system")
    local RespawnSystem = require("respawn_system")
    local CharacterFactory = require("systems.character_factory")

    return {
        props = props,
        logs = logs,
        CombatSystem = CombatSystem,
        RespawnSystem = RespawnSystem,
        CharacterFactory = CharacterFactory,
    }
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

local passed = 0
local function run_test(name, fn)
    fn()
    passed = passed + 1
    print("  [PASS] " .. name)
end

print("=== Phase 1: CombatSystem Unit Tests ===")

run_test("Constants and DamageType enum match specification", function()
    local env = make_env()
    local CS = env.CombatSystem
    assert(CS.CONST.DEFENSE_K == 100)
    assert(CS.CONST.CRIT_CHANCE_BASE == 0.10)
    assert(CS.CONST.CRIT_MULTIPLIER == 2.25)
    assert(CS.CONST.FRAGILITY_MULT == 1.30)
    assert(CS.DamageType.PHYSICAL == 1)
    assert(CS.DamageType.MAGICAL == 2)
    assert(CS.DamageType.TRUE == 3)
end)

run_test("init_entity initializes base stats and status flags as strings", function()
    local env = make_env()
    local CS = env.CombatSystem

    CS.init_entity(10, 2500, 120, 80)

    local p = env.props[10]
    assert(p.max_hp == "2500")
    assert(p.hp == "2500")
    assert(p.phys_def == "120")
    assert(p.mag_def == "80")
    assert(p.fragile == "0")
    assert(p.shield == "0")
    assert(p.shield_active == "0")
    assert(p.shield_end_tick == "0")
end)

run_test("calculate_mitigation handles negative, zero, and diminishing returns values", function()
    local env = make_env()
    local CS = env.CombatSystem

    assert_near(CS.calculate_mitigation(-50), 0.0, 1e-6, "negative defense clamps to 0")
    assert_near(CS.calculate_mitigation(0), 0.0, 1e-6, "zero defense")
    assert_near(CS.calculate_mitigation(100), 0.5, 1e-6, "100 defense -> 50% mitigation")
    assert_near(CS.calculate_mitigation(300), 0.75, 1e-6, "300 defense -> 75% mitigation")
end)

run_test("process_hit rejects missing or already dead targets", function()
    local env = make_env()
    local CS = env.CombatSystem

    -- Entity without hp property
    local res_missing = CS.process_hit(1, 99, 100, CS.DamageType.PHYSICAL)
    assert(res_missing.success == false and res_missing.reason == "target_dead")

    -- Entity with 0 hp
    CS.init_entity(2, 1000, 0, 0)
    env.props[2].hp = "0"
    local res_zero = CS.process_hit(1, 2, 100, CS.DamageType.PHYSICAL)
    assert(res_zero.success == false and res_zero.reason == "target_dead")

    -- Entity with negative hp
    env.props[2].hp = "-15"
    local res_neg = CS.process_hit(1, 2, 100, CS.DamageType.PHYSICAL)
    assert(res_neg.success == false and res_neg.reason == "target_dead")
end)

run_test("process_hit selects correct defense for PHYSICAL, MAGICAL, and TRUE damage", function()
    local env = make_env()
    local CS = env.CombatSystem

    CS.init_entity(1, 5000, 0, 0)
    CS.init_entity(2, 5000, 100, 300) -- phys mitigation = 50%, mag mitigation = 75%

    with_fixed_random(0.99, function()
        -- Physical: 400 * (1 - 0.50) = 200
        local r_phys = CS.process_hit(1, 2, 400, CS.DamageType.PHYSICAL, false)
        assert(r_phys.success == true and r_phys.was_critical == false and r_phys.lethal == false)
        assert_near(r_phys.damage_dealt, 200)
        assert_near(tonumber(env.props[2].hp), 4800)

        -- Magical: 400 * (1 - 0.75) = 100
        local r_mag = CS.process_hit(1, 2, 400, CS.DamageType.MAGICAL, false)
        assert(r_mag.success == true and r_mag.was_critical == false)
        assert_near(r_mag.damage_dealt, 100)
        assert_near(tonumber(env.props[2].hp), 4700)

        -- True damage: ignores phys_def=100 and mag_def=300 -> full 400
        local r_true = CS.process_hit(1, 2, 400, CS.DamageType.TRUE, false)
        assert(r_true.success == true and r_true.was_critical == false)
        assert_near(r_true.damage_dealt, 400)
        assert_near(tonumber(env.props[2].hp), 4300)
    end)
end)

run_test("process_hit applies critical multiplier via force_crit and RNG threshold", function()
    local env = make_env()
    local CS = env.CombatSystem

    CS.init_entity(1, 5000, 0, 0)
    CS.init_entity(2, 5000, 100, 0) -- 50% phys mitigation

    -- force_crit overrides high RNG roll
    with_fixed_random(0.99, function()
        local r = CS.process_hit(1, 2, 200, CS.DamageType.PHYSICAL, true)
        -- 200 * 0.5 * 2.25 = 225
        assert(r.was_critical == true)
        assert_near(r.damage_dealt, 225)
        assert_near(tonumber(env.props[2].hp), 4775)
    end)

    -- RNG <= CRIT_CHANCE_BASE (0.10) triggers crit
    with_fixed_random(0.10, function()
        local r = CS.process_hit(1, 2, 200, CS.DamageType.PHYSICAL)
        assert(r.was_critical == true)
        assert_near(r.damage_dealt, 225)
    end)

    -- RNG > CRIT_CHANCE_BASE does not crit
    with_fixed_random(0.11, function()
        local r = CS.process_hit(1, 2, 200, CS.DamageType.PHYSICAL)
        assert(r.was_critical == false)
        assert_near(r.damage_dealt, 100)
    end)
end)

run_test("process_hit applies fragility modifier and stacks with critical hit", function()
    local env = make_env()
    local CS = env.CombatSystem

    CS.init_entity(1, 5000, 0, 0)
    CS.init_entity(2, 5000, 0, 0)
    env.props[2].fragile = "1"

    with_fixed_random(0.99, function()
        -- Normal + fragile: 100 * 1.30 = 130
        local r1 = CS.process_hit(1, 2, 100, CS.DamageType.TRUE, false)
        assert_near(r1.damage_dealt, 130)

        -- Crit + fragile: 100 * 2.25 * 1.30 = 292.5
        local r2 = CS.process_hit(1, 2, 100, CS.DamageType.TRUE, true)
        assert(r2.was_critical == true)
        assert_near(r2.damage_dealt, 292.5)
    end)
end)

run_test("apply_shield, partial absorption, full shield break, and clear_shield", function()
    local env = make_env()
    local CS = env.CombatSystem

    CS.init_entity(1, 2000, 0, 0)
    CS.init_entity(2, 2000, 100, 0) -- 50% phys mitigation

    CS.apply_shield(2, 500, 150, 1000)
    assert(env.props[2].shield == "500")
    assert(env.props[2].shield_active == "1")
    assert(env.props[2].shield_end_tick == "1150")

    with_fixed_random(0.99, function()
        -- Partial absorption: 600 phys -> 300 post-mitigation; shield absorbs 300, leaves 200
        local r1 = CS.process_hit(1, 2, 600, CS.DamageType.PHYSICAL, false)
        assert_near(r1.shield_absorbed, 300)
        assert_near(r1.damage_dealt, 0)
        assert(env.props[2].shield == "200")
        assert(env.props[2].shield_active == "1")
        assert(env.props[2].shield_end_tick == "1150")
        assert(env.props[2].hp == "2000")

        -- Overflow break: 500 true damage against 200 shield -> 200 absorbed, 300 HP damage
        local r2 = CS.process_hit(1, 2, 500, CS.DamageType.TRUE, false)
        assert_near(r2.shield_absorbed, 200)
        assert_near(r2.damage_dealt, 300)
        assert(env.props[2].shield == "0")
        assert(env.props[2].shield_active == "0")
        assert(env.props[2].shield_end_tick == "0")
        assert_near(tonumber(env.props[2].hp), 1700)
    end)

    -- clear_shield explicitly clears an active shield
    CS.apply_shield(2, 1000, 90, 2000)
    assert(env.props[2].shield_active == "1")
    CS.clear_shield(2)
    assert(env.props[2].shield == "0")
    assert(env.props[2].shield_active == "0")
    assert(env.props[2].shield_end_tick == "0")
end)

run_test("lethal damage clamps HP to 0, updates KDA, marks dead, and calls on_entity_die", function()
    local env = make_env()
    local CS = env.CombatSystem

    CS.init_entity(1, 1000, 0, 0)
    CS.init_entity(2, 500, 0, 0)
    env.props[1].kills = "2"
    env.props[2].deaths = "1"

    local dead_hook_calls = {}
    local die_hook_calls = {}
    local orig_mark_dead = env.RespawnSystem.mark_dead
    local orig_on_die = env.CharacterFactory.on_entity_die

    env.RespawnSystem.mark_dead = function(id)
        table.insert(dead_hook_calls, id)
        return orig_mark_dead(id)
    end
    env.CharacterFactory.on_entity_die = function(id)
        table.insert(die_hook_calls, id)
        return orig_on_die(id)
    end

    with_fixed_random(0.99, function()
        -- Overkill damage (900 > 500 HP) must clamp HP to 0
        local r = CS.process_hit(1, 2, 900, CS.DamageType.TRUE, false)
        assert(r.success == true)
        assert(r.lethal == true)
        assert_near(r.damage_dealt, 900)
        assert(env.props[2].hp == "0")
        assert(env.props[2].is_dead == "true")
        assert(env.props[2].deaths == "2", "target deaths should increment from 1 to 2")
        assert(env.props[1].kills == "3", "attacker kills should increment from 2 to 3")
        assert(#dead_hook_calls == 1 and dead_hook_calls[1] == 2)
        assert(#die_hook_calls == 1 and die_hook_calls[1] == 2)
        assert(env.RespawnSystem.is_dead(2) == true)
    end)
end)

run_test("lethal self-damage or nil attacker increments deaths without awarding kill", function()
    local env = make_env()
    local CS = env.CombatSystem

    CS.init_entity(5, 100, 0, 0)
    env.props[5].kills = "0"
    env.props[5].deaths = "0"

    with_fixed_random(0.99, function()
        -- Self-kill must not award a kill to attacker == target
        local r_self = CS.process_hit(5, 5, 200, CS.DamageType.TRUE, false)
        assert(r_self.lethal == true)
        assert(env.props[5].deaths == "1")
        assert(env.props[5].kills == "0", "self-kill must not increment own kills")
    end)

    -- Nil attacker (e.g., environmental hazard) with unset deaths starts at 1
    CS.init_entity(6, 100, 0, 0)
    with_fixed_random(0.99, function()
        local r_env = CS.process_hit(nil, 6, 100, CS.DamageType.TRUE, false)
        assert(r_env.lethal == true)
        assert(env.props[6].deaths == "1")
    end)
end)

print(string.format("\n>>> Phase 1: All %d CombatSystem unit tests passed! <<<", passed))
