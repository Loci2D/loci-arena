-- Unit tests for CharacterFactory and RespawnSystem (Phase 2 of Issue #59)
-- Covers character data loading/fallback, skill slots, mana/cooldown checks,
-- tick regeneration & CC/dash/shield expiration, Arya passive on ally death,
-- and RespawnSystem death tracking, 300-tick respawn timer, and cleanup.

package.path = "./server/scripts/default_arena/?.lua;./?.lua;" .. package.path

local function make_env()
    local props = {}
    local velocities = {}
    local velocity_calls = {}
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
            set_velocity = function(id, vec)
                velocities[id] = { x = vec.x, y = vec.y }
                table.insert(velocity_calls, { id = id, x = vec.x, y = vec.y })
            end,
        },
    }

    -- Clear module state so each test runs in an isolated sandbox
    package.loaded["core.combat_system"] = nil
    package.loaded["respawn_system"] = nil
    package.loaded["systems.character_factory"] = nil
    for k in pairs(package.loaded) do
        if k:match("^data%.skills%.") or k:match("^data%.characters%.") then
            package.loaded[k] = nil
        end
    end

    local CombatSystem = require("core.combat_system")
    local RespawnSystem = require("respawn_system")
    local CharacterFactory = require("systems.character_factory")

    return {
        props = props,
        velocities = velocities,
        velocity_calls = velocity_calls,
        logs = logs,
        CombatSystem = CombatSystem,
        RespawnSystem = RespawnSystem,
        CharacterFactory = CharacterFactory,
    }
end

local passed = 0
local function run_test(name, fn)
    fn()
    passed = passed + 1
    print("  [PASS] " .. name)
end

print("=== Phase 2: CharacterFactory & RespawnSystem Unit Tests ===")

run_test("All character definitions have valid attributes and loadable skills", function()
    local env = make_env()
    local CF = env.CharacterFactory

    for _, char_name in ipairs({ "arya", "default", "mage", "warrior" }) do
        local data = CF.load_character(char_name)
        assert(type(data) == "table", "failed to load character: " .. char_name)
        assert(type(data.name) == "string" and #data.name > 0)
        assert(type(data.role) == "string" and #data.role > 0)
        assert(type(data.attributes) == "table")
        assert(data.attributes.max_hp > 0)
        assert(data.attributes.move_speed > 0)
        assert(type(data.skills) == "table" and #data.skills > 0)

        for _, skill_id in ipairs(data.skills) do
            local skill = CF.load_skill(skill_id)
            assert(type(skill) == "table" and skill.id == skill_id,
                string.format("character '%s' references missing skill '%s'", char_name, tostring(skill_id)))
        end
    end
end)

run_test("create_character initializes attributes, falls back to default, and avoids duplicate active tracking", function()
    local env = make_env()
    local CF = env.CharacterFactory

    assert(CF.create_character(1, "arya") == true)
    assert(env.props[1].character_name == "arya")
    assert(env.props[1].role == "tank")
    assert(env.props[1].max_hp == "5500" and env.props[1].hp == "5500")
    assert(env.props[1].phys_def == "130" and env.props[1].mag_def == "50")
    assert(env.props[1].mana == "100" and env.props[1].max_mana == "100")
    assert(env.props[1].move_speed == "3.2")
    assert(env.props[1].hp_regen == "20" and env.props[1].mana_regen == "10")
    assert(env.props[1].skills_list == "slash,fury_reward,whirlwind_dash,blade_throw")
    assert(env.props[1].fury_active == "false")

    -- Re-creating same entity must not duplicate it in active_entities (regen ticks once)
    assert(CF.create_character(1, "arya") == true)
    env.props[1].hp = "5000"
    CF.update_tick(30)
    assert(env.props[1].hp == "5020", "regen should apply exactly once (+20), got " .. tostring(env.props[1].hp))

    -- Unknown character falls back to default
    assert(CF.create_character(2, "unknown_hero_xyz") == true)
    assert(env.props[2].character_name == "default")
    assert(env.props[2].max_hp == "5000")
    assert(env.props[2].skills_list == "slash")
end)

run_test("has_skill and get_skill_by_slot handle valid, missing, and out-of-range slots", function()
    local env = make_env()
    local CF = env.CharacterFactory

    CF.create_character(1, "arya")

    assert(CF.has_skill(1, "slash") == true)
    assert(CF.has_skill(1, "blade_throw") == true)
    assert(CF.has_skill(1, "fireball") == false)
    assert(CF.has_skill(999, "slash") == false) -- no skills_list

    assert(CF.get_skill_by_slot(1, 1) == "slash")
    assert(CF.get_skill_by_slot(1, 2) == "fury_reward")
    assert(CF.get_skill_by_slot(1, 3) == "whirlwind_dash")
    assert(CF.get_skill_by_slot(1, 4) == "blade_throw")
    assert(CF.get_skill_by_slot(1, 0) == nil)
    assert(CF.get_skill_by_slot(1, 5) == nil)
    assert(CF.get_skill_by_slot(999, 1) == nil)
end)

run_test("can_cast and execute_skill enforce ownership, death, mana, cooldown, and rollback on failure", function()
    local env = make_env()
    local CF = env.CharacterFactory

    local exec_calls = {}
    local should_succeed = true
    package.loaded["data.skills.test_bolt"] = {
        id = "test_bolt",
        mana_cost = 30,
        cooldown = 21,
        on_execute = function(entity_id, aim_x, aim_y, skill_data)
            table.insert(exec_calls, { id = entity_id, ax = aim_x, ay = aim_y, skill = skill_data.id })
            if not should_succeed then
                return false, "Blocked by rule"
            end
            return true
        end,
    }

    CF.create_character(1, "default")
    env.props[1].skills_list = "slash,test_bolt"
    env.props[1].mana = "80"

    -- Unknown skill
    local ok, err = CF.execute_skill(1, "does_not_exist", 1, 0)
    assert(ok == false and err:find("not found"))

    -- Unowned skill
    ok, err = CF.execute_skill(1, "fireball", 1, 0)
    assert(ok == false and err:find("does not possess"))

    -- Failed on_execute must NOT consume mana or trigger cooldown
    should_succeed = false
    ok, err = CF.execute_skill(1, "test_bolt", 1, 0)
    assert(ok == false and err == "Blocked by rule")
    assert(env.props[1].mana == "80", "mana must not be consumed when on_execute fails")
    assert(#exec_calls == 1)

    -- Successful execution at tick 100 consumes 30 mana (50 left) and starts cooldown until tick 121
    CF.update_tick(100)
    should_succeed = true
    ok, err = CF.execute_skill(1, "test_bolt", 0.5, -0.5)
    assert(ok == true and err == nil)
    assert(env.props[1].mana == "50")
    assert(#exec_calls == 2 and exec_calls[2].ax == 0.5 and exec_calls[2].ay == -0.5)

    -- On cooldown at tick 119 (even with sufficient mana=50)
    CF.update_tick(119)
    ok, err = CF.execute_skill(1, "test_bolt", 1, 0)
    assert(ok == false and err == "Skill is on cooldown")

    -- Cooldown expires at tick 121: second cast succeeds and leaves 20 mana (cooldown until tick 142)
    CF.update_tick(121)
    ok, err = CF.execute_skill(1, "test_bolt", 1, 0)
    assert(ok == true and env.props[1].mana == "20")

    -- Ready at tick 142, but insufficient mana (20 < 30)
    CF.update_tick(142)
    ok, err = CF.execute_skill(1, "test_bolt", 1, 0)
    assert(ok == false and err == "Insufficient mana")

    -- Refill mana, kill entity -> blocked by death
    env.props[1].mana = "100"
    env.props[1].hp = "0"
    ok, err = CF.execute_skill(1, "test_bolt", 1, 0)
    assert(ok == false and err == "Entity is dead")
end)

run_test("update_tick handles 30-tick HP/mana regen caps and status/dash/shield expiration", function()
    local env = make_env()
    local CF = env.CharacterFactory
    local CS = env.CombatSystem

    CF.create_character(1, "arya") -- max_hp=5500, hp_regen=20, max_mana=100, mana_regen=10
    env.props[1].hp = "5490"
    env.props[1].mana = "95"
    env.props[1].stunned_until = "10"
    env.props[1].disarmed_until = "12"
    env.props[1].paralyzed_until = "15"
    env.props[1].dashing_until = "18"
    CS.apply_shield(1, 500, 20, 0) -- shield_end_tick = 20

    -- Tick 9: nothing expired yet, no regen
    CF.update_tick(9)
    assert(env.props[1].hp == "5490" and env.props[1].mana == "95")
    assert(env.props[1].stunned_until == "10")

    -- Tick 10: stun expires
    CF.update_tick(10)
    assert(env.props[1].stunned_until == "0")
    assert(env.props[1].disarmed_until == "12")

    -- Tick 12: disarm expires
    CF.update_tick(12)
    assert(env.props[1].disarmed_until == "0")

    -- Tick 15: paralysis expires
    CF.update_tick(15)
    assert(env.props[1].paralyzed_until == "0")

    -- Tick 18: dash expires and zeroes velocity
    local vel_before = #env.velocity_calls
    CF.update_tick(18)
    assert(env.props[1].dashing_until == "0")
    assert(#env.velocity_calls == vel_before + 1)
    assert(env.velocities[1].x == 0 and env.velocities[1].y == 0)

    -- Tick 20: shield expires
    CF.update_tick(20)
    assert(env.props[1].shield == "0")
    assert(env.props[1].shield_active == "0")
    assert(env.props[1].shield_end_tick == "0")

    -- Tick 30: regen applies and clamps to max_hp / max_mana
    CF.update_tick(30)
    assert(env.props[1].hp == "5500", "hp regen must clamp to max_hp")
    assert(env.props[1].mana == "100", "mana regen must clamp to max_mana")

    -- Dead entity skips regen and status expiration; on_entity_remove unregisters entity
    env.props[1].hp = "100"
    env.props[1].mana = "10"
    env.props[1].is_dead = "true"
    env.props[1].stunned_until = "5"
    CF.update_tick(60)
    assert(env.props[1].hp == "100", "dead entity must not regenerate hp")
    assert(env.props[1].mana == "10", "dead entity must not regenerate mana")
    assert(env.props[1].stunned_until == "5", "dead entity skips status expiration loop")

    env.props[1].is_dead = "false"
    CF.on_entity_remove(1)
    CF.update_tick(90)
    assert(env.props[1].hp == "100", "removed entity must no longer regenerate")
end)

run_test("CharacterFactory.on_entity_die activates Arya passive only for living allied Aryas", function()
    local env = make_env()
    local CF = env.CharacterFactory

    CF.create_character(1, "warrior") -- dying ally (team 1)
    env.props[1].team = "1"

    CF.create_character(2, "arya")    -- living allied Arya (team 1) -> should trigger
    env.props[2].team = "1"
    env.props[2].is_dead = "false"

    CF.create_character(3, "arya")    -- dead allied Arya (team 1) -> must NOT trigger
    env.props[3].team = "1"
    env.props[3].is_dead = "true"

    CF.create_character(4, "arya")    -- enemy Arya (team 2) -> must NOT trigger
    env.props[4].team = "2"
    env.props[4].is_dead = "false"

    CF.create_character(5, "mage")    -- living allied non-Arya (team 1) -> must NOT trigger
    env.props[5].team = "1"
    env.props[5].is_dead = "false"

    CF.update_tick(200)
    env.props[1].is_dead = "true"
    CF.on_entity_die(1)

    assert(env.props[2].paralyzed_until == "230", "living allied Arya must be paralyzed for 30 ticks")
    assert(env.props[2].fury_active == "true", "living allied Arya must activate fury")
    assert(env.props[3].fury_active == "false", "dead Arya must not trigger passive")
    assert(env.props[4].fury_active == "false", "enemy Arya must not trigger passive")
    assert(env.props[5].fury_active == "false", "non-Arya ally must not trigger passive")
end)

run_test("RespawnSystem tracks death, clears status/shields, revives after 300 ticks, and cleans up", function()
    local env = make_env()
    local RS = env.RespawnSystem

    env.props[1] = {
        max_hp = "5500",
        hp = "0",
        stunned_until = "999",
        disarmed_until = "999",
        paralyzed_until = "999",
        dashing_until = "999",
        shield = "400",
        shield_active = "1",
        shield_end_tick = "999",
    }
    env.props[2] = { max_hp = "4000", hp = "0" }
    env.props[3] = { max_hp = "6000", hp = "0" }

    RS.process_tick(100)
    RS.mark_dead(1)
    RS.mark_dead(1) -- idempotent call
    assert(RS.is_dead(1) == true)
    assert(env.props[1].is_dead == "true")
    assert(env.props[1].stunned_until == "0")
    assert(env.props[1].disarmed_until == "0")
    assert(env.props[1].paralyzed_until == "0")
    assert(env.props[1].dashing_until == "0")
    assert(env.props[1].shield == "0")
    assert(env.props[1].shield_active == "0")
    assert(env.props[1].shield_end_tick == "0")

    -- Player 2 dies at tick 100 as well; Player 3 dies at tick 150 then disconnects
    RS.mark_dead(2)
    RS.process_tick(150)
    RS.mark_dead(3)
    RS.cleanup(3)
    assert(RS.is_dead(3) == false)

    -- Tick 399 (299 ticks elapsed): still dead
    RS.process_tick(399)
    assert(RS.is_dead(1) == true and RS.is_dead(2) == true)
    assert(env.props[1].hp == "0" and env.props[2].hp == "0")

    -- Tick 400 (300 ticks elapsed): both 1 and 2 revive safely
    RS.process_tick(400)
    assert(RS.is_dead(1) == false and RS.is_dead(2) == false)
    assert(env.props[1].is_dead == "false" and env.props[1].hp == "5500")
    assert(env.props[2].is_dead == "false" and env.props[2].hp == "4000")

    -- Tick 450: cleaned-up entity 3 is not revived
    RS.process_tick(450)
    assert(env.props[3].hp == "0")

    -- Manual mark_alive removes dead state and clears active flags
    RS.mark_dead(1)
    env.props[1].stunned_until = "500"
    env.props[1].shield = "100"
    RS.mark_alive(1)
    assert(RS.is_dead(1) == false)
    assert(env.props[1].is_dead == "false")
    assert(env.props[1].stunned_until == "0")
    assert(env.props[1].shield == "0")

    -- Fallback max_hp=100 when max_hp property is missing
    env.props[4] = { hp = "0" }
    RS.process_tick(500)
    RS.mark_dead(4)
    RS.process_tick(800)
    assert(env.props[4].hp == "100" and env.props[4].is_dead == "false")
end)

print(string.format("\n>>> Phase 2: All %d CharacterFactory & RespawnSystem unit tests passed! <<<", passed))
