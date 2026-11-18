-- Unit tests for client modules: ProceduralAnim and VirtualJoystick (Phase 4 of Issue #59)

package.path = "./client/src/?.lua;./client/?.lua;./?.lua;" .. package.path

local function assert_near(actual, expected, eps, msg)
    eps = eps or 1e-4
    if math.abs((actual or 0) - expected) > eps then
        error(string.format("%s: expected %.6f, got %.6f (eps=%.6f)", msg or "assert_near", expected, actual or 0, eps), 2)
    end
end

local passed = 0
local function run_test(name, fn)
    fn()
    passed = passed + 1
    print("  [PASS] " .. name)
end

print("=== Phase 4: Client Modules Unit Tests ===")

-- ----------------------------------------------------------------------------
-- ProceduralAnim tests
-- ----------------------------------------------------------------------------
run_test("ProceduralAnim computes 8-way directions, facing, legacy mode, and state cleanup", function()
    package.loaded["procedural_anim"] = nil
    local ProceduralAnim = require("procedural_anim")

    local s0 = ProceduralAnim.get_state(1)
    assert(s0.direction == "south" and s0.facing == 1 and s0.is_moving == false)

    -- Cardinal & diagonal directions
    local cases = {
        { vx = 1, vy = 0, dir = "east", facing = 1 },
        { vx = 1, vy = 1, dir = "south-east", facing = 1 },
        { vx = 0, vy = 1, dir = "south", facing = 1 },
        { vx = -1, vy = 1, dir = "south-west", facing = -1 },
        { vx = -1, vy = 0, dir = "west", facing = -1 },
        { vx = -1, vy = -1, dir = "north-west", facing = -1 },
        { vx = 0, vy = -1, dir = "north", facing = -1 }, -- keeps previous facing
        { vx = 1, vy = -1, dir = "north-east", facing = 1 },
    }
    for _, c in ipairs(cases) do
        local st = ProceduralAnim.update_walk(0.016, 1, true, c.vx, c.vy)
        assert(st.direction == c.dir, string.format("expected %s, got %s", c.dir, tostring(st.direction)))
        assert(st.facing == c.facing, string.format("expected facing %d, got %d", c.facing, st.facing))
        assert(st.tilt_angle == 0 and st.bob_offset == 0 and st.squash_x == 1 and st.squash_y == 1)
    end

    -- Stopping preserves last direction
    local stopped = ProceduralAnim.update_walk(0.016, 1, false, 0, 0)
    assert(stopped.is_moving == false and stopped.direction == "north-east")

    -- Legacy facing_dir signature
    local leg_left = ProceduralAnim.update_walk(0.016, 2, true, -1)
    assert(leg_left.direction == "west" and leg_left.facing == -1)
    local fx, fy = ProceduralAnim.get_facing_vector(2)
    assert_near(fx, -1.0, 1e-4, "legacy left facing vector dx")
    assert_near(fy, 0.0, 1e-4, "legacy left facing vector dy")

    local leg_right = ProceduralAnim.update_walk(0.016, 2, true, 1)
    assert(leg_right.direction == "east" and leg_right.facing == 1)
    fx, fy = ProceduralAnim.get_facing_vector(2)
    assert_near(fx, 1.0, 1e-4, "legacy right facing vector dx")
    assert_near(fy, 0.0, 1e-4, "legacy right facing vector dy")

    -- resolve_cast_direction: stopped fallback uses last direction/facing instead of hardcoded (0, -1),
    -- and integrates cleanly with active movement and auto-aim target vector
    ProceduralAnim.update_walk(0.016, 1, true, 0, 1) -- move south
    ProceduralAnim.update_walk(0.016, 1, false, 0, 0) -- stop
    local cdx, cdy = ProceduralAnim.resolve_cast_direction(1, 0, 0)
    assert_near(cdx, 0.0, 1e-4, "stopped cast dx uses last facing (south)")
    assert_near(cdy, 1.0, 1e-4, "stopped cast dy uses last facing (south)")

    -- Active movement overrides stopped facing
    cdx, cdy = ProceduralAnim.resolve_cast_direction(1, -1, 0)
    assert_near(cdx, -1.0, 1e-4, "active movement cast dx")
    assert_near(cdy, 0.0, 1e-4, "active movement cast dy")

    -- Auto-aim target vector takes priority when provided (Card #92 integration)
    cdx, cdy = ProceduralAnim.resolve_cast_direction(1, 0, 0, 3, 4)
    assert_near(cdx, 0.6, 1e-4, "auto-aim cast dx")
    assert_near(cdy, 0.8, 1e-4, "auto-aim cast dy")

    -- clear_state resets entity
    ProceduralAnim.clear_state(1)
    assert(ProceduralAnim.get_state(1).direction == "south")
end)

-- ----------------------------------------------------------------------------
-- VirtualJoystick tests
-- ----------------------------------------------------------------------------
run_test("VirtualJoystick dynamic movement stick activates in bottom-left, clamps radius, and supports multitouch", function()
    package.loaded["virtual_joystick"] = nil
    local VJ = require("virtual_joystick")
    VJ.set_push(nil)
    VJ.update(1280, 720)
    VJ.reset()

    -- Outside bottom-left quadrant must NOT activate movement joystick
    assert(VJ.handle_touchpress("t_bad1", 700, 500) == false) -- right half
    assert(VJ.handle_touchpress("t_bad2", 200, 200) == false) -- top half
    assert(VJ.is_move_active() == false)

    -- Press in bottom-left (200, 500), drag 150px right (clamped to radius=75 -> dx=1.0, dy=0)
    assert(VJ.handle_touchpress("t_move", 200, 500) == true)
    assert(VJ.is_move_active() == true)
    assert(VJ.handle_touchmove("t_move", 350, 500) == true)
    local dx, dy = VJ.get_move_vector()
    assert_near(dx, 1.0, 1e-4, "clamped joystick dx")
    assert_near(dy, 0.0, 1e-4, "clamped joystick dy")

    -- Different touch ID does not affect move joystick
    assert(VJ.handle_touchmove("t_other", 200, 450) == false)
    dx, dy = VJ.get_move_vector()
    assert_near(dx, 1.0, 1e-4)

    -- Partial drag (37.5px up -> dy=-0.5)
    assert(VJ.handle_touchmove("t_move", 200, 462.5) == true)
    dx, dy = VJ.get_move_vector()
    assert_near(dx, 0.0, 1e-4)
    assert_near(dy, -0.5, 1e-4)

    -- Release resets active and vector
    assert(VJ.handle_touchrelease("t_move") == true)
    assert(VJ.is_move_active() == false)
    dx, dy = VJ.get_move_vector()
    assert_near(dx, 0.0, 1e-4)
    assert_near(dy, 0.0, 1e-4)
end)

run_test("VirtualJoystick drag-to-aim, cancellation, quick tap, and non-aiming button release", function()
    package.loaded["virtual_joystick"] = nil
    local VJ = require("virtual_joystick")
    VJ.set_push(nil)
    VJ.update(1280, 720)
    VJ.reset()

    -- Button 3 center: (1280*0.80 = 1024, 720*0.68 = 489.6), radius=50, support_aiming=true
    local b3x, b3y = 1024, 489.6

    -- 1. Drag-to-aim release
    assert(VJ.handle_touchpress("t3", b3x, b3y) == true)
    assert(VJ.is_skill_active(3) == true)
    assert(VJ.is_skill_in_deadzone(3) == true)
    assert(VJ.is_aiming(3) == false)

    -- Drag 60px right (past aim_deadzone=15 and cancel_deadzone=37.5)
    assert(VJ.handle_touchmove("t3", b3x + 60, b3y) == true)
    assert(VJ.is_skill_in_deadzone(3) == false)
    assert(VJ.is_aiming(3) == true)
    assert(VJ.is_skill_cancelled(3) == false)
    local adx, ady = VJ.get_aim_vector(3)
    assert_near(adx, 1.0, 1e-4)
    assert_near(ady, 0.0, 1e-4)

    assert(VJ.handle_touchrelease("t3") == true)
    local events = VJ.pop_release_events()
    assert(#events == 1)
    assert(events[1].skill_id == 3 and events[1].was_aiming == true and events[1].is_cancelled == false)
    assert_near(events[1].aim_dx, 1.0, 1e-4)
    assert(#VJ.pop_release_events() == 0, "pop_release_events must clear queue")

    -- 2. Drag out then drag back to center cancels cast
    assert(VJ.handle_touchpress("t3b", b3x, b3y) == true)
    VJ.handle_touchmove("t3b", b3x, b3y - 60)
    assert(VJ.is_aiming(3) == true)
    VJ.handle_touchmove("t3b", b3x + 5, b3y)
    assert(VJ.is_skill_cancelled(3) == true and VJ.is_aiming(3) == false)
    VJ.handle_touchrelease("t3b")
    events = VJ.pop_release_events()
    assert(#events == 1 and events[1].is_cancelled == true and events[1].was_aiming == false)

    -- 3. Quick tap inside deadzone
    assert(VJ.handle_touchpress("t3c", b3x, b3y) == true)
    VJ.handle_touchrelease("t3c")
    events = VJ.pop_release_events()
    assert(#events == 1 and events[1].was_aiming == false and events[1].is_cancelled == false)

    -- 4. Botão 1 (hold_to_cast): permanece ativo mesmo arrastando para fora do raio
    --    (ataque contínuo enquanto segurado); botão 2 sem aiming cancela ao sair do raio
    assert(VJ.handle_mousepressed(1152, 612, 1) == true)
    assert(VJ.is_skill_1_active() == true)
    VJ.handle_mousemoved(1152 + 100, 612)
    assert(VJ.is_skill_1_active() == true, "button 1 hold_to_cast must stay active while held")
    VJ.handle_mousereleased(1152 + 100, 612, 1)
    assert(VJ.is_skill_1_active() == false, "button 1 must deactivate on release")

    -- Botão 2 (sem aiming e sem hold_to_cast) desativa ao sair do raio
    assert(VJ.handle_mousepressed(1152, 432, 1) == true)
    assert(VJ.is_skill_2_active() == true)
    VJ.handle_mousemoved(1152 + 100, 432)
    assert(VJ.is_skill_2_active() == false, "button without aiming must deactivate when dragged outside radius")
    assert(VJ.handle_mousepressed(1152, 612, 2) == false, "right-click must be ignored")
end)

run_test("VirtualJoystick cooldowns and push coordinate transform", function()
    package.loaded["virtual_joystick"] = nil
    local VJ = require("virtual_joystick")
    VJ.update(1280, 720)
    VJ.reset()

    -- Cooldown (0.5s)
    assert(VJ.can_trigger_skill_2(1.0) == true)
    VJ.trigger_skill_2(1.0)
    assert(VJ.can_trigger_skill_2(1.4) == false)
    assert(VJ.can_trigger_skill_2(1.5) == true)

    -- Push coordinate mapping (e.g., 2x window -> game coords)
    VJ.set_push({
        toGame = function(_, x, y)
            return x * 0.5, y * 0.5
        end
    })
    -- Screen coords (2304, 1224) -> game coords (1152, 612) = Button 1 center
    assert(VJ.handle_touchpress("t_push", 2304, 1224) == true)
    assert(VJ.is_skill_active(1) == true)
    VJ.handle_touchrelease("t_push")
    VJ.set_push(nil)

    -- Real skill cooldown synchronization (whirlwind_dash=6.0s, blade_throw=14.0s) and disabled slot blocking
    VJ.reset()
    VJ.sync_skill_slot(3, {
        enabled = true,
        skill_name = "whirlwind_dash",
        label = "Dash",
        cooldown = 6.0,
        cooldown_remaining = 4.2,
        cooldown_duration = 6.0,
    })
    assert(VJ.can_trigger_skill(3, 10.0) == false, "slot on active server cooldown must block trigger")
    local st3 = VJ.get_skill_state(3)
    assert(st3.skill_name == "whirlwind_dash" and math.abs(st3.action_cooldown - 6.0) < 1e-6 and math.abs(st3.cooldown_remaining - 4.2) < 1e-6)

    -- While on cooldown, dragging button 3 must not enter aiming state
    assert(VJ.handle_touchpress("t_cd_drag", 1024, 489.6) == true)
    VJ.handle_touchmove("t_cd_drag", 1024 + 60, 489.6)
    assert(VJ.is_aiming(3) == false, "button on cooldown must not enter drag-to-aim")
    VJ.handle_touchrelease("t_cd_drag")
    VJ.pop_release_events()

    -- Unequipped slot (e.g. slot 4 on mage/default/warrior) blocks press activation and trigger
    VJ.sync_skill_slot(4, { enabled = false, skill_name = nil, cooldown_remaining = 0 })
    assert(VJ.can_trigger_skill(4, 20.0) == false, "disabled/unequipped slot must not trigger")
    assert(VJ.handle_touchpress("t_dis", 960, 612) == true)
    assert(VJ.is_skill_active(4) == false, "disabled slot must consume touch without activating")
end)

-- ----------------------------------------------------------------------------
-- SkillRanges tests (alcances publicados pelo servidor com fallback embutido)
-- ----------------------------------------------------------------------------
run_test("SkillRanges parses the server property, ignores malformed entries and falls back to defaults", function()
    package.loaded["skill_ranges"] = nil
    local SkillRanges = require("skill_ranges")

    -- parse(): entradas válidas, espaços e números decimais
    local parsed = SkillRanges.parse("slash=16:7, fireball=64.5:9,dash=40:10")
    assert_near(parsed.slash.range, 16, 1e-9, "slash range")
    assert_near(parsed.slash.aoe, 7, 1e-9, "slash aoe")
    assert_near(parsed.fireball.range, 64.5, 1e-9, "fireball range")
    assert_near(parsed.dash.aoe, 10, 1e-9, "dash aoe")

    -- parse(): vazio/nil/lixo nunca quebra e entradas inválidas são descartadas
    assert(next(SkillRanges.parse("")) == nil and next(SkillRanges.parse(nil)) == nil, "empty -> {}")
    local bad = SkillRanges.parse("bad,x=1,y=a:b,z=-1:2,w=1:2:3,ok=5:2")
    assert(bad.bad == nil and bad.x == nil and bad.y == nil and bad.z == nil and bad.w == nil, "malformed entries dropped")
    assert(bad.ok and bad.ok.range == 5 and bad.ok.aoe == 2, "valid entry kept next to malformed ones")

    -- Sem nada publicado: usa os padrões embutidos (todas as skills com alcance)
    SkillRanges.reset()
    for _, name in ipairs({ "slash", "fury_reward", "whirlwind_dash", "blade_throw", "fireball" }) do
        assert(SkillRanges.range(name) and SkillRanges.range(name) > 0, "default range for " .. name)
        assert(SkillRanges.aoe(name) and SkillRanges.aoe(name) > 0, "default aoe for " .. name)
    end
    assert(SkillRanges.range("unknown_skill") == nil, "unknown skill has no default")
    assert(SkillRanges.range("unknown_skill", 12) == 12, "explicit fallback is returned for unknown skill")

    -- update(): o valor publicado pelo servidor vence o padrão; lixo posterior não apaga o que já valia
    local default_slash = SkillRanges.range("slash")
    SkillRanges.update("slash=99:33")
    assert_near(SkillRanges.range("slash"), 99, 1e-9, "published slash range overrides default")
    assert_near(SkillRanges.aoe("slash"), 33, 1e-9, "published slash aoe overrides default")
    assert(SkillRanges.range("fireball") == SkillRanges.DEFAULTS.fireball.range, "skills not published keep the default")
    SkillRanges.update("???")
    assert_near(SkillRanges.range("slash"), 99, 1e-9, "garbage update keeps the last valid value")
    SkillRanges.update(nil)
    assert_near(SkillRanges.range("slash"), 99, 1e-9, "nil update keeps the last valid value")
    SkillRanges.update("fireball=80:12")
    assert_near(SkillRanges.range("fireball"), 80, 1e-9, "new character skill_ranges updates published")
    assert_near(SkillRanges.range("slash"), default_slash, 1e-9, "old character keys are cleared on valid update")
    SkillRanges.reset()
    assert_near(SkillRanges.range("slash"), default_slash, 1e-9, "reset() returns to the defaults")
end)

-- ---------------------------------------------------------------------------
-- 5. SessionStore: persistencia de servidor e session_token
-- ---------------------------------------------------------------------------
run_test("SessionStore persists connection, session_token and validates grace age", function()
    local fs_files = {}
    local prev_love = _G.love
    _G.love = {
        filesystem = {
            getInfo = function(name) return fs_files[name] ~= nil and { type = "file" } or nil end,
            read = function(name) return fs_files[name] end,
            write = function(name, content) fs_files[name] = content; return true end,
        }
    }

    local SessionStore = require("src.session_store")
    local initial = SessionStore.load()
    assert(initial.last_ip == "127.0.0.1" and initial.last_port == 8080, "defaults loaded")
    assert(not SessionStore.has_valid_token(initial, 30, 1000), "no token initially")

    SessionStore.save_session_token("192.168.0.2", 8080, "AryaPlayer", "tok_abc", 1000)
    local reloaded = SessionStore.load()
    assert(reloaded.last_ip == "192.168.0.2" and reloaded.player_name == "AryaPlayer", "connection fields persisted")
    assert(reloaded.session_token == "tok_abc", "session_token persisted")
    assert(SessionStore.has_valid_token(reloaded, 30, 1020), "token valid within 30s grace period")
    assert(not SessionStore.has_valid_token(reloaded, 30, 1045), "token expired after 30s grace period")

    SessionStore.clear_session_token()
    local cleared = SessionStore.load()
    assert(cleared.session_token == nil and not SessionStore.has_valid_token(cleared, 30, 1005), "token cleared")

    _G.love = prev_love
end)

-- ---------------------------------------------------------------------------
-- 6. ConnectScreen: presets, edicao de campos, validacao e callbacks
-- ---------------------------------------------------------------------------
run_test("ConnectScreen handles presets, textinput, validation and connect/resume callbacks", function()
    local ConnectScreen = require("src.ui.connect_screen")
    local connected_args, resumed_args = nil, nil

    ConnectScreen.init({
        initial_ip = "127.0.0.1",
        initial_port = 8080,
        initial_name = "Tester",
        can_resume = true,
        on_connect = function(ip, port, name) connected_args = { ip, port, name } end,
        on_resume = function(ip, port, name) resumed_args = { ip, port, name } end,
    })

    -- Preset 2 (LAN 192.168.0.2)
    assert(ConnectScreen.handle_press(600, 240) == true, "preset 2 hit")
    local ip, port, name = ConnectScreen.get_values()
    assert(ip == "192.168.0.2" and port == 8080 and name == "Tester", "preset updated ip/port")

    -- Focar campo nome, digitar e apagar
    assert(ConnectScreen.handle_press(400, 400) == true, "name input hit")
    assert(ConnectScreen.textinput("1") == true, "textinput appended")
    local _, _, updated_name = ConnectScreen.get_values()
    assert(updated_name == "Tester1", "name updated via textinput")
    assert(ConnectScreen.keypressed("backspace") == true, "backspace handled")
    local _, _, after_bs = ConnectScreen.get_values()
    assert(after_bs == "Tester", "backspace removed char")

    -- Botao Conectar e Retomar Sessao
    assert(ConnectScreen.handle_press(400, 520) == true, "connect button hit")
    assert(connected_args and connected_args[1] == "192.168.0.2" and connected_args[2] == 8080, "on_connect invoked")
    assert(ConnectScreen.handle_press(750, 520) == true, "resume button hit")
    assert(resumed_args and resumed_args[1] == "192.168.0.2" and resumed_args[3] == "Tester", "on_resume invoked")
end)

-- ---------------------------------------------------------------------------
-- 7. Paridade Touch (VirtualJoystick HUD bar + kda_ui.toggle)
-- ---------------------------------------------------------------------------
run_test("VirtualJoystick top HUD bar emits KDA/swap/mute/disconnect without moving joystick", function()
    local VirtualJoystick = require("virtual_joystick")
    local kda_ui = require("kda_ui")

    VirtualJoystick.set_push(nil)
    VirtualJoystick.update(1280, 720)
    VirtualJoystick.set_hud_state({ safe_top = 14, audio_enabled = true, kda_visible = false })

    -- Centro superior: 4 botoes (72 + 10 + 78 + 10 + 72 + 10 + 72 = 324 -> start_x = 478)
    assert(VirtualJoystick.handle_touchpress(1, 500, 25) == true, "KDA button hit")
    assert(VirtualJoystick.handle_touchpress(2, 580, 25) == true, "Heroi button hit")
    assert(VirtualJoystick.handle_touchpress(3, 660, 25) == true, "Som button hit")
    assert(VirtualJoystick.handle_touchpress(4, 740, 25) == true, "Sair button hit")
    assert(not VirtualJoystick.is_move_active(), "HUD bar taps must not activate movement joystick")

    local evs = VirtualJoystick.pop_hud_events()
    assert(#evs == 4 and evs[1] == "kda" and evs[2] == "swap_hero" and evs[3] == "toggle_mute" and evs[4] == "disconnect",
        "HUD events emitted in expected order")

    local was_visible = kda_ui.is_visible()
    assert(kda_ui.toggle() == (not was_visible), "kda_ui.toggle flips state")
    assert(kda_ui.toggle() == was_visible, "kda_ui.toggle restores state")
end)

run_test("ConnectScreen invokes love.keyboard.setTextInput(true/false) on focus and blur", function()
    local ConnectScreen = require("src.ui.connect_screen")
    local text_input_calls = {}
    local prev_love = _G.love
    _G.love = {
        keyboard = {
            setTextInput = function(enabled)
                table.insert(text_input_calls, enabled)
            end
        }
    }

    ConnectScreen.init({ initial_ip = "127.0.0.1", initial_port = 8080, initial_name = "Tester" })
    assert(ConnectScreen.handle_press(400, 320) == true, "ip input hit")
    assert(text_input_calls[#text_input_calls] == true, "setTextInput(true) called when input focused")

    assert(ConnectScreen.handle_press(100, 100) == false, "outside click blurs")
    assert(text_input_calls[#text_input_calls] == false, "setTextInput(false) called when blurred")

    _G.love = prev_love
end)

-- ---------------------------------------------------------------------------
-- 8. AutoAim: mira automática no inimigo vivo mais próximo
-- ---------------------------------------------------------------------------
run_test("AutoAim targets nearest living enemy of another team within range", function()
    package.loaded["auto_aim"] = nil
    local AutoAim = require("auto_aim")

    local function ent(id, x, y, team, is_dead, entity_type)
        return {
            id = id, x = x, y = y,
            team = team,
            is_dead = is_dead,
            properties = entity_type and { entity_type = entity_type } or nil,
        }
    end

    local me = ent(1, 0, 0, "1", false)
    local entities = {
        me,
        ent(2, 0, 10, "2", false),   -- inimigo a 10u (norte)
        ent(3, 30, 0, "2", false),   -- inimigo mais longe a 30u (leste)
        ent(4, 0, -8, "1", false),   -- aliado mais perto: ignorado
        ent(5, 0, 5, "2", true),     -- inimigo morto: ignorado
        ent(6, 0, 4, "2", false, "projectile"), -- não-jogador: ignorado
        ent(7, 0, 6, nil, false),    -- sem time: ignorado
    }

    -- Inimigo válido mais próximo é o id 2 (dist 10 < 30)
    local target = AutoAim.find_nearest_enemy(me, entities, 20)
    assert(target and target.id == 2, "nearest enemy must be entity 2, got " .. tostring(target and target.id))

    -- Vetor normalizado aponta para (0, +1)
    local dx, dy = AutoAim.aim_at_nearest_enemy(me, entities, 20)
    assert_near(dx, 0.0, 1e-6, "aim dx")
    assert_near(dy, 1.0, 1e-6, "aim dy")

    -- Diagonal normalizada
    entities[2].x, entities[2].y = 30, 40
    entities[3].x, entities[3].y = 300, 0 -- fora de qualquer range
    dx, dy = AutoAim.aim_at_nearest_enemy(me, entities, 100)
    assert_near(dx, 0.6, 1e-6, "diagonal aim dx")
    assert_near(dy, 0.8, 1e-6, "diagonal aim dy")

    -- Fora de alcance -> nil (fallback do chamador assume)
    dx, dy = AutoAim.aim_at_nearest_enemy(me, entities, 10)
    assert(dx == nil and dy == nil, "out of range must return nil")

    -- Sem time próprio -> nunca mira (não dá para distinguir inimigos)
    local teamless = ent(9, 0, 0, nil, false)
    assert(AutoAim.find_nearest_enemy(teamless, entities, 100) == nil, "caster without team must not aim")

    -- Alvo na mesma posição do caster -> nil (vetor degenerado)
    local stacked = ent(10, 0, 0, "2", false)
    assert(AutoAim.aim_at_nearest_enemy(me, { me, stacked }, 50) == nil, "stacked target must not aim")

    -- Suporta entidades com API ent:get(key) (estilo SDK do cliente)
    local sdk_me = {
        id = 20, x = 0, y = 0,
        get = function(_, key)
            return ({ team = "1", is_dead = "false" })[key]
        end,
    }
    local sdk_enemy = {
        id = 21, x = 0, y = -12,
        get = function(_, key)
            return ({ team = "2", is_dead = "false" })[key]
        end,
    }
    dx, dy = AutoAim.aim_at_nearest_enemy(sdk_me, { sdk_me, sdk_enemy }, 20)
    assert_near(dx, 0.0, 1e-6, "sdk aim dx")
    assert_near(dy, -1.0, 1e-6, "sdk aim dy")

    -- Suporta tabelas de entidades associativas/mapas indexadas por ID (pairs)
    local map_entities = {
        [99] = me,
        [101] = ent(101, 0, 15, "2", false),
        [102] = ent(102, 50, 0, "2", false),
    }
    local map_target = AutoAim.find_nearest_enemy(me, map_entities, 50)
    assert(map_target and map_target.id == 101, "map_entities must target id 101")

    -- Caster ou inimigo com time vazio ("") -> ignorado
    local empty_team_me = ent(30, 0, 0, "", false)
    assert(AutoAim.find_nearest_enemy(empty_team_me, entities, 100) == nil, "caster with empty team must not aim")
    local empty_team_enemy = ent(31, 0, 5, "", false)
    assert(AutoAim.find_nearest_enemy(me, { me, empty_team_enemy }, 50) == nil, "enemy with empty team must not be aimed")

    -- Inimigo com hp <= 0 é ignorado como morto mesmo sem is_dead explícito
    local hp_zero_enemy = { id = 32, x = 0, y = 5, team = "2", hp = 0 }
    assert(AutoAim.find_nearest_enemy(me, { me, hp_zero_enemy }, 50) == nil, "enemy with hp <= 0 must be ignored as dead")
end)

print(string.format("\n>>> Phase 4: All %d Client Module unit tests passed! <<<", passed))
