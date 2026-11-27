-- Loci Arena - Love2D Client
-- Entrypoint for the game client connecting to the authoritative loci2d server.

package.path = package.path .. ";./loci2d/?.lua;./loci2d/lib/?.lua;./client/loci2d/?.lua;./client/loci2d/lib/?.lua;./src/?.lua;./client/src/?.lua;./?.lua;./lib/?.lua"
package.cpath = package.cpath .. ";./loci2d/lib/?.so;./loci2d/?.so;./client/loci2d/lib/?.so;./client/loci2d/?.so;./?.so;./lib/?.so"

local ok, loci = pcall(require, "loci_client")
if not ok then
    ok, loci = pcall(require, "loci2d.loci_client")
    if not ok then
        error("Could not load loci_client SDK module. Details: " .. tostring(loci))
    end
end

local push = require("src.push")
local kda_ui = require("kda_ui")
local virtual_joystick = require("virtual_joystick")
local procedural_anim = require("src.procedural_anim")
local sprite_anim = require("src.sprite_anim")
local MovementSync = require("src.movement_sync")
local LocalPrediction = require("src.local_prediction")
local AudioSystem = require("src.audio_system")
local SkillRanges = require("src.skill_ranges")
local AutoAim = require("src.auto_aim")
local SessionStore = require("src.session_store")
local ConnectScreen = require("src.ui.connect_screen")
local VfxSystem = require("src.vfx_system")
local GAME_WIDTH, GAME_HEIGHT = 1280, 720

-- Configurar push no sistema de joystick para conversão de coordenadas
virtual_joystick.set_push(push)

-- Connection config
local SERVER_IP = os.getenv("LOCI_SERVER_IP") or "127.0.0.1"
local SERVER_PORT = tonumber(os.getenv("LOCI_SERVER_PORT")) or 8080
local CONNECT_TIMEOUT_SEC = 6.0

-- UI & State variables
local client_state = "in_game" -- "connect_screen" | "connecting" | "in_game"
local is_mobile_os = false
local current_server_ip = SERVER_IP
local current_server_port = SERVER_PORT
local current_player_name = nil
local connect_started_at = 0
local last_saved_session_token = nil
local connection_status = "Connecting..."
local connected_status_label = ""
local is_connection_lost = false
local movement_sync = MovementSync.new()
local rejection_msg = ""
local rejection_timer = 0
local show_debug_overlay = false
local show_character_sheet = false
local show_touch_controls = true

-- HUD Fonts (criadas uma vez)
local font_hud_small = nil
local font_hud_normal = nil

-- Sprites e texturas de personagens (padrão 32x32px)
local SPRITE_BASE_SIZE = 32
-- 🔍 ZOOM DO PERSONAGEM: ajuste SPRITE_SCALE para controlar o tamanho visual na tela.
--   1 = 32px  (tamanho nativo do sprite, compacto)
--   2 = 64px  (atual — bom equilíbrio visual para arena)
--   4 = 128px (equivalente ao sprite 16x16 antigo multiplicado por 8)
local SPRITE_SCALE = 2
local placeholder_canvases = {}

local function create_character_placeholder(r, g, b, accent_r, accent_g, accent_b)
    local canvas = love.graphics.newCanvas(SPRITE_BASE_SIZE, SPRITE_BASE_SIZE)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    -- Corpo estilizado de 32x32 com proporção e silhueta para arena:
    -- Borda externa escura para contraste contra o chão da arena
    love.graphics.setColor(0.08, 0.08, 0.1, 0.95)
    love.graphics.rectangle("fill", 5, 4, 22, 27, 4, 4)

    -- Preenchimento principal do corpo
    love.graphics.setColor(r, g, b, 1)
    love.graphics.rectangle("fill", 6, 5, 20, 25, 3, 3)

    -- Detalhe de iluminação no topo da cabeça
    love.graphics.setColor(math.min(1, r * 1.3), math.min(1, g * 1.3), math.min(1, b * 1.3), 0.7)
    love.graphics.rectangle("fill", 8, 6, 16, 4, 2, 2)

    -- Indicador de frente / Facing (olhos / visor voltado para a direita)
    -- Quando facing = 1, olha para a direita. Quando facing = -1, é espelhado no eixo X via escala negativa e pivô ox=16.
    love.graphics.setColor(0.05, 0.05, 0.05, 0.95)
    love.graphics.rectangle("fill", 15, 10, 9, 6, 1, 1)

    -- Visor / Brilho do olho
    love.graphics.setColor(accent_r, accent_g, accent_b, 1)
    love.graphics.rectangle("fill", 17, 11, 6, 4)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle("fill", 20, 11, 2, 2)

    -- Detalhe da cintura / cinto
    love.graphics.setColor(0.12, 0.12, 0.16, 0.85)
    love.graphics.rectangle("fill", 7, 21, 18, 2)

    -- Pés / Botas na base (y=27 a 31)
    love.graphics.setColor(0.15, 0.15, 0.2, 1)
    love.graphics.rectangle("fill", 7, 27, 7, 4, 1, 1)
    love.graphics.rectangle("fill", 17, 27, 8, 4, 1, 1)

    love.graphics.setCanvas()
    canvas:setFilter("nearest", "nearest")
    return canvas
end

-- Paleta de cores distintivas para os robôs placeholders dos 6 arquétipos da arena 3v3
local ARCHETYPE_PALETTES = {
    tank = { 0.35, 0.45, 0.58 },     -- Aço Ardósia / Azul Blindado (Warrior)
    fighter = { 0.85, 0.30, 0.22 },  -- Carmesim de Combate (Arya / Default)
    marksman = { 0.18, 0.68, 0.32 }, -- Verde Esmeralda / Caçador (Archer)
    mage = { 0.58, 0.22, 0.88 },     -- Violeta Arcano (Mage)
    healer = { 0.94, 0.76, 0.18 },   -- Dourado Solar / Sagrado (Cleric)
    support = { 0.10, 0.72, 0.75 },  -- Turquesa Tático / Ciano (Enchanter)
}

local TEAM_VISOR_COLORS = {
    me = { 0.20, 0.95, 1.00 },       -- Ciano elétrico (Jogador local)
    team1 = { 0.30, 0.80, 1.00 },    -- Azul celeste (Aliado / Time 1)
    team2 = { 1.00, 0.30, 0.25 },    -- Vermelho vibrante (Inimigo / Time 2)
}

local function normalize_archetype_key(role, char_name)
    local r = string.lower(tostring(role or ""))
    local c = string.lower(tostring(char_name or ""))
    if r == "tank" or c == "warrior" then
        return "tank"
    elseif r == "marksman" or r == "archer" or c == "archer" then
        return "marksman"
    elseif r == "mage" or c == "mage" then
        return "mage"
    elseif r == "healer" or r == "cleric" or c == "cleric" then
        return "healer"
    elseif r == "support" or r == "enchanter" or c == "enchanter" then
        return "support"
    else
        return "fighter" -- Arya, default, fighter fallback
    end
end

local function init_placeholders()
    placeholder_canvases["me"] = create_character_placeholder(0.2, 0.6, 0.95, 0.3, 0.9, 1.0)
    placeholder_canvases["enemy"] = create_character_placeholder(0.9, 0.3, 0.25, 1.0, 0.85, 0.2)
    placeholder_canvases["dead"] = create_character_placeholder(0.35, 0.35, 0.38, 0.5, 0.5, 0.5)

    -- Robôs customizados por arquétipo com visores de identificação de time
    for arch_key, body_rgb in pairs(ARCHETYPE_PALETTES) do
        for team_key, visor_rgb in pairs(TEAM_VISOR_COLORS) do
            local key = arch_key .. "_" .. team_key
            placeholder_canvases[key] = create_character_placeholder(
                body_rgb[1], body_rgb[2], body_rgb[3],
                visor_rgb[1], visor_rgb[2], visor_rgb[3]
            )
        end
    end
end

local function get_placeholder_for_entity(ent, is_me, is_dead)
    if is_dead then
        return placeholder_canvases["dead"]
    end
    local role = (type(ent.get) == "function" and ent:get("role", "")) or ent.role or (ent.properties and ent.properties["role"]) or ""
    local char_name = (type(ent.get) == "function" and ent:get("character_name", "")) or ent.character_name or (ent.properties and ent.properties["character_name"]) or ""
    local arch_key = normalize_archetype_key(role, char_name)

    local team_key = "team2"
    if is_me then
        team_key = "me"
    else
        local team = tostring((type(ent.get) == "function" and ent:get("team", "2")) or ent.team or (ent.properties and ent.properties["team"]) or "2")
        team_key = (team == "1") and "team1" or "team2"
    end

    local key = arch_key .. "_" .. team_key
    return placeholder_canvases[key] or (is_me and placeholder_canvases["me"] or placeholder_canvases["enemy"])
end

local function get_entity_skill_by_slot(entity, slot_index)
    if not entity or not slot_index then return nil end
    local list_str = (type(entity.get) == "function" and entity:get("skills_list", ""))
        or entity.skills_list
        or (entity.properties and entity.properties["skills_list"])
        or ""
    if not list_str or list_str == "" then return nil end

    local idx = 1
    for skill in string.gmatch(list_str, "[^,]+") do
        if idx == slot_index then
            return string.lower(skill)
        end
        idx = idx + 1
    end
    return nil
end

-- Camera state (tracked directly in world coordinates)
local cam_x, cam_y = 0, 0

local VISUAL_SCALE = 8 -- Pixels per Meter (escala para desenho)

-- Server authoritative arena boundaries: [-500, +500] (1000x1000 pixels)
local ARENA_MIN = -500
local ARENA_MAX = 500
local ARENA_SIZE = ARENA_MAX - ARENA_MIN

-- A engine clampa o centro do colisor circular (raio 2.0) dentro de [-500, +500].
-- A predição local do cliente precisa respeitar o mesmo limite seguro para não
-- desenhar o próprio jogador além da barreira enquanto a tecla fica pressionada.
-- Espelha intencionalmente `server/scripts/default_arena/core/arena_bounds.lua`
-- porque o cliente Love2D e o VFS sandbox do servidor não compartilham módulos Lua;
-- manter sincronizado se o mapa ou o raio do colisor mudarem.
local PLAYER_COLLIDER_RADIUS = 2.0
local PREDICTED_SAFE_MIN_X = ARENA_MIN + PLAYER_COLLIDER_RADIUS
local PREDICTED_SAFE_MAX_X = ARENA_MAX - PLAYER_COLLIDER_RADIUS
local PREDICTED_SAFE_MIN_Y = ARENA_MIN + PLAYER_COLLIDER_RADIUS
local PREDICTED_SAFE_MAX_Y = ARENA_MAX - PLAYER_COLLIDER_RADIUS

local function clamp_arena_coords(x, y)
    local cx = math.max(PREDICTED_SAFE_MIN_X, math.min(PREDICTED_SAFE_MAX_X, x or 0))
    local cy = math.max(PREDICTED_SAFE_MIN_Y, math.min(PREDICTED_SAFE_MAX_Y, y or 0))
    return cx, cy
end

VfxSystem.configure({
    visual_scale = VISUAL_SCALE,
    sprite_base_size = SPRITE_BASE_SIZE,
    sprite_scale = SPRITE_SCALE,
    clamp_fn = clamp_arena_coords,
})
VfxSystem.reset()

local function should_clamp_entity(ent)
    if not ent then return false end
    if VfxSystem.is_projectile_entity(ent) then
        return false
    end
    local ent_type = (ent.get and ent:get("entity_type"))
        or (ent.properties and ent.properties["entity_type"])
    if ent_type ~= nil then
        local t = string.lower(tostring(ent_type))
        return t == "player" or t == "hero" or t == "character"
    end
    local bp = type(ent.blueprint) == "string" and string.lower(ent.blueprint) or ""
    if bp:find("projectile", 1, true) or bp:find("bullet", 1, true) or bp:find("fx", 1, true) then
        return false
    end
    return true
end

local function clamp_entity_to_arena(ent, clamp_recon_error, compensate_overshoot)
    if not ent then return false, false end

    local old_x = ent.x
    local old_y = ent.y
    local clamped_x = false
    local clamped_y = false

    if ent.x then
        if ent.x > PREDICTED_SAFE_MAX_X then
            ent.x = PREDICTED_SAFE_MAX_X
            clamped_x = true
        elseif ent.x < PREDICTED_SAFE_MIN_X then
            ent.x = PREDICTED_SAFE_MIN_X
            clamped_x = true
        end
    end

    if ent.y then
        if ent.y > PREDICTED_SAFE_MAX_Y then
            ent.y = PREDICTED_SAFE_MAX_Y
            clamped_y = true
        elseif ent.y < PREDICTED_SAFE_MIN_Y then
            ent.y = PREDICTED_SAFE_MIN_Y
            clamped_y = true
        end
    end

    -- Zera apenas a componente de velocidade que tenta atravessar o limite em contato
    if ent.x and ent.vx then
        if (ent.x >= PREDICTED_SAFE_MAX_X and ent.vx > 0) or (ent.x <= PREDICTED_SAFE_MIN_X and ent.vx < 0) then
            ent.vx = 0
        end
    end
    if ent.y and ent.vy then
        if (ent.y >= PREDICTED_SAFE_MAX_Y and ent.vy > 0) or (ent.y <= PREDICTED_SAFE_MIN_Y and ent.vy < 0) then
            ent.vy = 0
        end
    end

    -- Ajusta o erro de reconciliação sem descartar correções que apontam para dentro da arena
    -- (ex.: knockback/body-block enquanto o jogador segura tecla contra a parede):
    -- 1) Pós-loci.update (dash / fallback): desconta o overshoot já absorvido pelo clamp
    --    para eliminar o "efeito mola" sem apagar divergências reais para dentro.
    -- 2) Sempre: limita _error ao intervalo válido [SAFE_MIN - x, SAFE_MAX - x] para
    --    bloquear erro residual para fora e preservar correções para dentro.
    if clamp_recon_error then
        if ent.x and ent._error_x and ent._error_x ~= 0 then
            local err_x = ent._error_x
            if compensate_overshoot and clamped_x then
                err_x = err_x - (ent.x - old_x)
            end
            err_x = math.max(PREDICTED_SAFE_MIN_X - ent.x,
                math.min(PREDICTED_SAFE_MAX_X - ent.x, err_x))
            ent._error_x = (math.abs(err_x) < 1e-6) and 0 or err_x
        end
        if ent.y and ent._error_y and ent._error_y ~= 0 then
            local err_y = ent._error_y
            if compensate_overshoot and clamped_y then
                err_y = err_y - (ent.y - old_y)
            end
            err_y = math.max(PREDICTED_SAFE_MIN_Y - ent.y,
                math.min(PREDICTED_SAFE_MAX_Y - ent.y, err_y))
            ent._error_y = (math.abs(err_y) < 1e-6) and 0 or err_y
        end
    end

    return clamped_x, clamped_y
end

-- Replica propositalmente a cinemática padrão de caminhada do `sdk-love2d`
-- (`move_speed * tick_rate * dt`) via `_prediction_handler` em vez de depender só
-- do clamp pós-`loci.update`. Isso aplica `clamp_entity_to_arena` *antes* de `decay_error`
-- e `reconcile_position`, evitando que passos maiores (FPS baixo ou buff de velocidade)
-- ultrapassem ±498 e distorçam a reconciliação contra a parede. Se o SDK passar a expor
-- um hook de pós-predição/clamp antes da reconciliação, esta cópia pode ser removida.
-- A lógica vive em src/local_prediction.lua (inclui o cast lock `casting_until`).
local function predict_local_movement(ent, dx, dy, dt)
    LocalPrediction.predict_local_movement(ent, dx, dy, dt, {
        cur_tick = tonumber(loci._last_state_tick) or 0,
        tick_rate = (loci.get_server_tick_rate and loci.get_server_tick_rate()) or 30.0,
        default_speed = loci.netcode and loci.netcode.default_move_speed,
        clamp = function(e) clamp_entity_to_arena(e, true, false) end,
    })
end

-- Metadados de habilidades para HUD/Hotbar (alinhados a server/scripts/default_arena/data/skills/*.lua a 30 Hz)
local RESPAWN_DURATION_SECONDS = 10.0 -- 300 ticks a 30 Hz (respawn_system.lua)

local SKILL_HUD_META = {
    slash          = { label = "Slash",    cooldown = 0.5,  mana_cost = 10 },
    fireball       = { label = "Fireball", cooldown = 1.5,  mana_cost = 35 },
    fury_reward    = { label = "Fúria",    cooldown = 5.0,  mana_cost = 0  },
    whirlwind_dash = { label = "Dash",     cooldown = 6.0,  mana_cost = 25 },
    blade_throw    = { label = "Lâmina",   cooldown = 14.0, mana_cost = 45 },
    shield         = { label = "Escudo",   cooldown = 10.0, mana_cost = 20 },
}

local HOTBAR_SLOTS = {
    { slot = 1, key = "Space" },
    { slot = 2, key = "Q" },
    { slot = 3, key = "E" },
    { slot = 4, key = "R" },
}

local cooldown_slots = {
    [1] = { active = false, start_time = 0, duration = 0 },
    [2] = { active = false, start_time = 0, duration = 0 },
    [3] = { active = false, start_time = 0, duration = 0 },
    [4] = { active = false, start_time = 0, duration = 0 },
}

-- Gate de cast por slot (tempo do cliente): evita spam de ações rejeitadas pelo
-- servidor quando uma habilidade é segurada (hold-to-cast) com cooldown > 0.5s.
local skill_cast_gate = {}

local respawn_state = { active = false, start_time = 0, duration = RESPAWN_DURATION_SECONDS }

-- Última direção de movimento conhecida (fallback de mira quando não há input atual)
local last_move_dir_x, last_move_dir_y = 0, -1

local function normalize_dir(dx, dy, min_len)
    local ax, ay = dx or 0, dy or 0
    local len = math.sqrt(ax * ax + ay * ay)
    if len > (min_len or 1e-6) then
        return ax / len, ay / len
    end
    return nil
end

local function update_last_move_dir(dx, dy)
    local ndx, ndy = normalize_dir(dx, dy, 0.01)
    if ndx then
        last_move_dir_x, last_move_dir_y = ndx, ndy
    end
end

local function get_client_time()
    return (love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

local function reset_cooldown_slots()
    for slot = 1, 4 do
        cooldown_slots[slot].active = false
        cooldown_slots[slot].start_time = 0
        cooldown_slots[slot].duration = 0
        skill_cast_gate[slot] = nil
    end
    if virtual_joystick and virtual_joystick.reset_cooldowns then
        virtual_joystick.reset_cooldowns()
    end
end

local function start_slot_cooldown(slot, duration, now)
    if not slot or slot < 1 or slot > 4 then return end
    local cd = tonumber(duration) or 0
    if cd <= 0 then return end
    local t = now or get_client_time()
    cooldown_slots[slot].active = true
    cooldown_slots[slot].start_time = t
    cooldown_slots[slot].duration = cd
    if virtual_joystick and virtual_joystick.trigger_skill then
        virtual_joystick.trigger_skill(slot, t, cd)
    end
end

local function get_slot_cooldown_remaining(slot, current_time)
    local entry = cooldown_slots[slot]
    if not entry or not entry.active then
        return 0
    end
    local now = current_time or get_client_time()
    local rem = (entry.duration or 0) - (now - (entry.start_time or 0))
    if rem <= 0 then
        entry.active = false
        return 0
    end
    return rem
end

local function has_team_allies(my_entity)
    if not my_entity then return false end
    local my_team = tostring((my_entity.get and my_entity:get("team")) or my_entity.team or "1")
    local all_entities = (loci.get_entities and loci.get_entities()) or {}
    for _, other in ipairs(all_entities) do
        if other.id ~= my_entity.id then
            local ent_type = (other.get and other:get("entity_type")) or (other.properties and other.properties["entity_type"])
            local is_player = (ent_type == nil) or (string.lower(tostring(ent_type)) == "player")
            if is_player then
                local other_team = (other.get and other:get("team")) or (other.properties and other.properties["team"])
                if other_team ~= nil and tostring(other_team) == my_team then
                    return true
                end
            end
        end
    end
    return false
end

local function sync_virtual_joystick_slots(my_entity, current_time)
    if not my_entity or not virtual_joystick or not virtual_joystick.sync_skill_slot then
        return
    end
    local now = current_time or get_client_time()
    local mana = tonumber((my_entity.get and my_entity:get("mana", 0)) or my_entity.mana or 0) or 0
    local fury_val = (my_entity.get and my_entity:get("fury_active")) or my_entity.fury_active
    local fury_active = (fury_val == true or fury_val == "true")
    local has_allies = nil

    for slot = 1, 4 do
        local skill_name = SkillRanges.resolve_entity_skill(my_entity, slot)
        local meta = skill_name and (SKILL_HUD_META[skill_name] or SkillRanges.meta(skill_name)) or nil
        local cd_remaining = get_slot_cooldown_remaining(slot, now)
        local cd_total = (meta and meta.cooldown) or 0.5

        local locked_reason = nil
        if skill_name then
            if skill_name == "fury_reward" and not fury_active then
                if has_allies == nil then
                    has_allies = has_team_allies(my_entity)
                end
                if has_allies then
                    locked_reason = "BLOQ."
                end
            end
            if not locked_reason and meta and (meta.mana_cost or 0) > mana then
                locked_reason = "MANA"
            end
        end

        virtual_joystick.sync_skill_slot(slot, {
            enabled = (skill_name ~= nil),
            skill_name = skill_name,
            label = (meta and meta.label) or skill_name,
            cooldown = cd_total,
            cooldown_remaining = cd_remaining,
            cooldown_duration = (cooldown_slots[slot].duration > 0 and cooldown_slots[slot].duration) or cd_total,
            locked_reason = locked_reason,
        })
    end
end

local function get_entity_prop_number(ent, key)
    if not ent then return 0 end
    local raw = (ent.get and ent:get(key)) or ent[key] or (ent.properties and ent.properties[key])
    return tonumber(raw) or 0
end

local function get_active_cc(ent)
    if not ent then return nil, 0 end
    local cur_tick = tonumber(loci._last_state_tick) or 0
    local tick_rate = (loci.get_server_tick_rate and loci.get_server_tick_rate()) or 30.0
    if tick_rate <= 0 then tick_rate = 30.0 end

    local cc_checks = {
        { key = "stunned_until",   label = "STUN" },
        { key = "paralyzed_until", label = "PARALISIA" },
        { key = "disarmed_until",  label = "DESARME" },
    }

    local active_label = nil
    local max_remaining = 0
    for _, cc in ipairs(cc_checks) do
        local until_tick = get_entity_prop_number(ent, cc.key)
        if until_tick > cur_tick then
            local rem = (until_tick - cur_tick) / tick_rate
            if not active_label then
                active_label = cc.label
            end
            if rem > max_remaining then
                max_remaining = rem
            end
        end
    end

    return active_label, max_remaining
end

local function get_safe_top_virtual()
    if love.window and love.window.getSafeArea and love.graphics and love.graphics.getDimensions then
        local _, sy = love.window.getSafeArea()
        local _, gh = love.graphics.getDimensions()
        if sy and sy > 0 and gh and gh > 0 then
            return math.max(14, math.floor((sy / gh) * GAME_HEIGHT) + 8)
        end
    end
    return 14
end

local function start_network_connection(ip, port, player_name, resume_token, use_ui_flow)
    current_server_ip = ip
    current_server_port = tonumber(port) or 8080
    current_player_name = player_name
    last_saved_session_token = nil

    SessionStore.save_connection(current_server_ip, current_server_port, current_player_name)

    print(string.format("[Client] Connecting to %s:%d as '%s'...", current_server_ip, current_server_port, current_player_name))

    local ok_connect
    if resume_token and resume_token ~= "" and loci.resume then
        ok_connect = loci.resume(current_server_ip, current_server_port, current_player_name, resume_token, "loci2d/lib/")
        if not ok_connect then
            ok_connect = loci.resume(current_server_ip, current_server_port, current_player_name, resume_token, "client/loci2d/lib/")
        end
    else
        ok_connect = loci.connect(current_server_ip, current_server_port, current_player_name, "loci2d/lib/")
        if not ok_connect then
            ok_connect = loci.connect(current_server_ip, current_server_port, current_player_name, "client/loci2d/lib/")
        end
    end

    if not ok_connect then
        connection_status = "Connection error"
        print("[Client] Failed to initialize connection to " .. current_server_ip .. ":" .. current_server_port)
        if use_ui_flow then
            client_state = "connect_screen"
            ConnectScreen.set_status("Erro ao iniciar socket/schema para " .. current_server_ip .. ":" .. current_server_port, true, false)
        end
        return false
    end

    is_connection_lost = false
    connected_status_label = "Connected to " .. current_server_ip .. ":" .. current_server_port .. " (" .. current_player_name .. ")"
    connection_status = connected_status_label
    if use_ui_flow then
        client_state = "connecting"
        connect_started_at = get_client_time()
        ConnectScreen.set_status("Conectando a " .. current_server_ip .. ":" .. current_server_port .. "...", false, true)
    else
        client_state = "in_game"
    end
    return true
end

local function return_to_connect_screen(status_msg, is_error)
    if loci.disconnect then
        loci.disconnect("Returned to connect screen")
    end
    SessionStore.clear_session_token()
    last_saved_session_token = nil
    AudioSystem.stop_bgm()
    virtual_joystick.reset()
    kda_ui.hide()
    is_connection_lost = false
    connection_status = "Disconnected"
    client_state = "connect_screen"
    ConnectScreen.set_can_resume(false)
    ConnectScreen.set_status(status_msg or "", is_error == true, false)
end

local function request_swap_hero()
    local me = loci.get_my_entity()
    local is_dead = me and (me.is_dead or (me.properties and me.properties["is_dead"] == "true"))
    if is_dead then
        print("[Client] Não é possível trocar de personagem enquanto estiver morto")
        return
    end

    if connection_status:find("Connected") then
        print("[Client] Solicitando troca de personagem...")
        -- Servidor cicla automaticamente sem precisar do índice
        loci.send_action(999, 0, 0)
        movement_sync:mark_needs_resync()
    else
        print("[Client] Não conectado - não é possível trocar personagem")
    end
end

function love.load(arg)
    -- Linear filter ensures smooth sub-pixel interpolation without snapping jitter
    love.graphics.setDefaultFilter("linear", "linear")

    local os_name = (love.system and love.system.getOS and love.system.getOS()) or ""
    is_mobile_os = (os_name == "Android" or os_name == "iOS")
    local win_w, win_h = GAME_WIDTH, GAME_HEIGHT
    if love.graphics and love.graphics.getDimensions then
        local gw, gh = love.graphics.getDimensions()
        if gw and gh and gw > 0 and gh > 0 then
            win_w, win_h = gw, gh
        end
    end

    push:setupScreen(GAME_WIDTH, GAME_HEIGHT, win_w, win_h, {
        fullscreen = is_mobile_os,
        resizable = true,
        pixelperfect = false
    })

    -- Inicializar fontes do HUD
    font_hud_small = love.graphics.newFont(14)
    font_hud_normal = love.graphics.newFont(18)

    -- Inicializar posições dos controles virtuais para a resolução do jogo
    virtual_joystick.update_with_game_dimensions(GAME_WIDTH, GAME_HEIGHT)
    virtual_joystick.set_hud_state({ safe_top = get_safe_top_virtual() })

    -- Carregar efeitos sonoros (SFX) com fallback procedural para placeholders
    AudioSystem.init()

    local random_suffix = tostring(love.math and love.math.random(1000, 9999) or math.random(1000, 9999))
    local default_name = "Player_" .. random_suffix

    local force_connect_ui = (os.getenv("LOCI_CONNECT_UI") == "1")
    if type(arg) == "table" then
        for _, v in ipairs(arg) do
            if v == "--connect-ui" then
                force_connect_ui = true
                break
            end
        end
    end

    local saved_cfg = SessionStore.load()
    local can_resume_saved = SessionStore.has_valid_token(saved_cfg, 30)
    ConnectScreen.init({
        initial_ip = (os.getenv("LOCI_SERVER_IP") or saved_cfg.last_ip or SERVER_IP),
        initial_port = tonumber(os.getenv("LOCI_SERVER_PORT")) or saved_cfg.last_port or SERVER_PORT,
        initial_name = saved_cfg.player_name or default_name,
        can_resume = can_resume_saved,
        on_connect = function(ip, port, name)
            SessionStore.clear_session_token()
            ConnectScreen.set_can_resume(false)
            start_network_connection(ip, port, name, nil, true)
        end,
        on_resume = function(ip, port, name)
            local cfg = SessionStore.load()
            local token = (cfg.session_host == ip and cfg.session_port == tonumber(port)) and cfg.session_token or nil
            start_network_connection(ip, port, name, token, true)
        end,
    })

    if is_mobile_os or force_connect_ui then
        client_state = "connect_screen"
    else
        -- Fast-path desktop: conecta imediatamente sem abrir tela de IP
        if not start_network_connection(SERVER_IP, SERVER_PORT, default_name, nil, false) then
            return
        end
    end

    if loci.netcode then
        loci.netcode.default_move_speed = 2.0
        if os.getenv("LOCI_AUTO_EXPORT_CSV") == "1" then
            loci.netcode.auto_export_csv_on_quit = true
        end
    end

    -- Inicializar placeholders padronizados de 32x32px
    init_placeholders()

    -- Pré-carregar metadados de sprites disponíveis em assets/sprites/
    sprite_anim.load_character("arya")

    -- Registrar predição local com clamp nos limites da arena antes da reconciliação.
    -- Nota: durante dash ativo (`dashing_until`), o SDK desvia para o ramo próprio e não chama
    -- `_prediction_handler`; por isso o clamp pós-`loci.update` em `love.update` cobre o dash.
    if loci.set_prediction_handler then
        loci.set_prediction_handler(predict_local_movement)
    end

    -- Event hooks
    loci.on_entity_spawned = function(entity)
        print(string.format("[Event] Entity spawned: ID %s at (%.1f, %.1f)", tostring(entity.id), entity.x, entity.y))
        VfxSystem.on_entity_spawned(entity)

        -- Iniciar BGM quando o jogador local spawnar
        local my_entity = loci.get_my_entity()
        if my_entity and entity.id == my_entity.id then
            AudioSystem.play_bgm("arena")
        end
    end

    loci.on_entity_despawned = function(entity_id, last_entity)
        print("[Event] Entity despawned: ID " .. tostring(entity_id))
        VfxSystem.on_entity_despawned(entity_id, last_entity)
        procedural_anim.clear_state(entity_id)
        sprite_anim.clear_entity_state(entity_id)
    end

    loci.on_property_changed = function(entity, key, old_val, new_val)
        -- Hook for HUD/UI state updates (HP, score, buffs)
        if key == "hp" then
            local old_hp = tonumber(old_val) or 0
            local new_hp = tonumber(new_val) or 0
            local damage = old_hp - new_hp

            if damage > 0 then
                local is_critical = damage >= 350
                AudioSystem.play(is_critical and "critical" or "hit")

                -- 1. Screen shake apenas para dano significativo no jogador local
                local my_entity = loci.get_my_entity()
                if my_entity and entity and entity.id == my_entity.id and damage > 50 then
                    VfxSystem.trigger_shake(damage, 0.2)
                end

                -- 2. Dano flutuante para qualquer entidade (local ou inimiga)
                VfxSystem.add_floating_damage(entity, damage, {
                    is_critical = is_critical,
                    is_shield = false,
                })
            end
        elseif key == "shield" then
            local old_shield = tonumber(old_val) or 0
            local new_shield = tonumber(new_val) or 0
            local damage = old_shield - new_shield

            if damage > 0 then
                AudioSystem.play("shield_hit")

                local my_entity = loci.get_my_entity()
                if my_entity and entity and entity.id == my_entity.id and damage > 50 then
                    VfxSystem.trigger_shake(damage, 0.2)
                end

                VfxSystem.add_floating_damage(entity, damage, {
                    is_critical = false,
                    is_shield = true,
                })
            end
        elseif key == "is_dead" then
            local dead = (new_val == true or new_val == "true")
            if entity then
                sprite_anim.set_dead(entity.id, dead)
            end
            local my_entity = loci.get_my_entity()
            if entity and my_entity and entity.id == my_entity.id then
                local was_dead = (old_val == true or old_val == "true")
                if dead and not was_dead then
                    AudioSystem.play("death")
                end
                if dead and not respawn_state.active then
                    respawn_state.active = true
                    respawn_state.start_time = get_client_time()
                    respawn_state.duration = RESPAWN_DURATION_SECONDS
                    reset_cooldown_slots()
                elseif not dead then
                    respawn_state.active = false
                end
            end
        elseif key == "fury_active" then
            if (new_val == true or new_val == "true") and entity then
                local cname = (entity.get and entity:get("character_name"))
                    or entity.character_name
                    or (entity.properties and entity.properties["character_name"])
                sprite_anim.trigger_ally_death(entity.id, cname)
            end
        elseif key == "character_name" then
            if entity then
                sprite_anim.on_character_changed(entity.id, new_val)
            end
            local my_entity = loci.get_my_entity()
            if entity and my_entity and entity.id == my_entity.id then
                reset_cooldown_slots()
            end
        end
    end

    loci.on_action_cast = function(entity, ability_id, dir_x, dir_y)
        -- Ignora meta-ações (ex: troca de personagem)
        if ability_id == 999 then
            return
        end

        -- Alinha direção padrão (1, 0) com o servidor quando a mira for nula
        local dx = tonumber(dir_x) or 0
        local dy = tonumber(dir_y) or 0
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            dx = dx / len
            dy = dy / len
        else
            dx, dy = 1, 0
        end

        local character_name = string.lower(tostring(entity and entity:get("character_name", "default") or "default"))
        local skill_name = get_entity_skill_by_slot(entity, ability_id)
        local audio_skill = skill_name
        if not audio_skill and ability_id == 1 and character_name == "mage" then
            audio_skill = "fireball"
        end
        AudioSystem.play_skill(audio_skill, ability_id)

        local has_sprite_anim = false
        if entity then
            has_sprite_anim = sprite_anim.trigger_action(entity.id, skill_name, ability_id, dx, dy, character_name) == true
        end

        -- Rastrear cooldown local pelo nome real da skill (ou fallback se skills_list ainda não chegou)
        local my_entity = loci.get_my_entity()
        if entity and my_entity and entity.id == my_entity.id then
            procedural_anim.set_facing_vector(entity.id, dx, dy)
            local slot = ability_id
            if slot >= 1 and slot <= 4 then
                local resolved_skill = skill_name or SkillRanges.resolve_entity_skill(entity, slot)
                local meta = resolved_skill and (SKILL_HUD_META[resolved_skill] or SkillRanges.meta(resolved_skill))
                if meta and meta.cooldown and meta.cooldown > 0 then
                    start_slot_cooldown(slot, meta.cooldown, get_client_time())
                end
                sync_virtual_joystick_slots(entity, get_client_time())
            end
        end

        -- Fallback procedural apenas para personagens/habilidades sem animação de sprite
        if not has_sprite_anim then
            VfxSystem.spawn_skill_fx({
                x = entity and entity.x or 0,
                y = entity and entity.y or 0,
                dir_x = dx,
                dir_y = dy,
                ability_id = ability_id,
                skill_name = skill_name,
                character_name = character_name,
                caster_id = entity and entity.id or nil,
            })
        end
    end

    loci.on_intent_rejected = function(reason)
        rejection_msg = reason
        rejection_timer = 2.5
    end

    loci.on_connection_lost = function(reason)
        print("[Client] Conexão instável ou perdida: " .. tostring(reason))
        is_connection_lost = true
        connection_status = "Reconnecting (" .. tostring(reason or "timeout") .. ")..."
        movement_sync:on_connection_lost()
    end

    loci.on_reconnected = function(entity_id)
        print("[Client] Reconexão estabelecida com sucesso! Entity ID: " .. tostring(entity_id))
        is_connection_lost = false
        if connected_status_label ~= "" then
            connection_status = connected_status_label
        end
        movement_sync:on_reconnected()
    end
end

local function read_move_input()
    local dx, dy = 0, 0

    -- Prioridade: joystick virtual (se ativo e visível) > teclado
    if show_touch_controls and virtual_joystick.is_move_active() then
        dx, dy = virtual_joystick.get_move_vector()
    else
        if love.keyboard.isDown("w") or love.keyboard.isDown("up") then dy = dy - 1 end
        if love.keyboard.isDown("s") or love.keyboard.isDown("down") then dy = dy + 1 end
        if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dx = dx - 1 end
        if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dx = dx + 1 end
    end

    return dx, dy
end

local function update_movement(my_entity)
    local dx, dy = read_move_input()
    update_last_move_dir(dx, dy)
    if my_entity and (math.abs(dx) >= 0.1 or math.abs(dy) >= 0.1) then
        procedural_anim.set_facing_vector(my_entity.id, dx, dy)
    end
    local cur_tick = tonumber(loci._last_state_tick) or 0
    local now = (love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    movement_sync:step(my_entity, dx, dy, cur_tick, now, loci)
end

-- Alcance de detecção de auto-aim para o slot:
-- Para o ataque básico (slot 1), utiliza alcance de detecção amplo (estilo MOBA,
-- DEFAULT_MAX_RANGE = 64.0) para que o herói corpo a corpo (ex: Arya) sempre
-- vire e ataque na direção do alvo enquanto se aproxima, evitando golpear no vazio.
-- Para as demais habilidades (slots 2-4), utiliza o alcance autoritativo da skill
-- com fallback para o alcance padrão.
local function auto_aim_range_for_slot(my_entity, slot)
    local skill_name = get_entity_skill_by_slot(my_entity, slot)
    local range = skill_name and SkillRanges.range(skill_name) or nil
    if slot == 1 then
        return math.max(range or 0, AutoAim.DEFAULT_MAX_RANGE)
    end
    return (range and range > 0) and range or AutoAim.DEFAULT_MAX_RANGE
end

-- Resolve a direção de mira para casts rápidos (sem aim manual explícita):
-- 1) inimigo vivo mais próximo de outro time dentro do alcance da habilidade do slot;
-- 2) direção de movimento atual (joystick/teclado);
-- 3) última direção/facing do personagem (fallback dinâmico, evitando norte fixo).
local function resolve_quick_cast_aim(my_entity, slot)
    local aaim_dx, aaim_dy = AutoAim.aim_at_nearest_enemy(my_entity, loci.get_entities(), auto_aim_range_for_slot(my_entity, slot))
    local move_dx, move_dy = read_move_input()
    return procedural_anim.resolve_cast_direction(my_entity and my_entity.id, move_dx, move_dy, aaim_dx, aaim_dy)
end

-- Ataque básico (slot 1) compartilhado entre touch (botão 1 segurado) e
-- teclado (Espaço segurado): dispara no ritmo do cooldown da skill, com
-- auto-aim no inimigo mais próximo e fallback de direção de movimento/facing.
-- `use_button_gate` aplica também o cooldown interno do botão virtual.
local function cast_basic_attack(my_entity, now, use_button_gate)
    if now < (skill_cast_gate[1] or 0) then return end
    if use_button_gate then
        if not virtual_joystick.can_trigger_skill(1, now) then return end
        virtual_joystick.trigger_skill(1, now)
    end

    local skill_name = SkillRanges.resolve_entity_skill(my_entity, 1) or get_entity_skill_by_slot(my_entity, 1)
    local meta = skill_name and (SKILL_HUD_META[skill_name] or SkillRanges.meta(skill_name))
    local cast_interval = (meta and meta.cooldown and meta.cooldown > 0) and meta.cooldown or 0.5
    skill_cast_gate[1] = now + cast_interval
    start_slot_cooldown(1, cast_interval, now)
    sync_virtual_joystick_slots(my_entity, now)

    local action_dx, action_dy = resolve_quick_cast_aim(my_entity, 1)
    loci.send_action(1, action_dx, action_dy)
end

function love.update(dt)
    if client_state == "connect_screen" then
        return
    end

    -- Process incoming network packets and smooth entity interpolation
    loci.update(dt)

    if loci.get_session_token then
        local token = loci.get_session_token()
        if token and token ~= "" and token ~= last_saved_session_token then
            last_saved_session_token = token
            SessionStore.save_session_token(current_server_ip, current_server_port, current_player_name, token)
            ConnectScreen.set_can_resume(true)
        end
    end

    local my_entity = loci.get_my_entity()
    if client_state == "connecting" then
        if my_entity then
            client_state = "in_game"
            ConnectScreen.set_status("", false, false)
        elseif (get_client_time() - connect_started_at) > CONNECT_TIMEOUT_SEC then
            if loci.disconnect then
                loci.disconnect("Connection timeout")
            end
            client_state = "connect_screen"
            ConnectScreen.set_status(
                string.format("Timeout ao conectar em %s:%d. Verifique IP/Wi-Fi.", current_server_ip, current_server_port),
                true, false
            )
            return
        else
            return
        end
    end

    if show_touch_controls then
        virtual_joystick.set_hud_state({
            audio_enabled = AudioSystem.is_enabled(),
            kda_visible = kda_ui.is_visible(),
        })
        for _, hud_ev in ipairs(virtual_joystick.pop_hud_events()) do
            if hud_ev == "kda" then
                kda_ui.toggle()
            elseif hud_ev == "swap_hero" then
                request_swap_hero()
            elseif hud_ev == "toggle_mute" then
                AudioSystem.toggle_mute()
            elseif hud_ev == "disconnect" then
                return_to_connect_screen("Desconectado.", false)
                return
            end
        end
    end

    if my_entity then
        if is_connection_lost then
            is_connection_lost = false
        end
        if connected_status_label ~= "" and connection_status:find("^Reconnecting") then
            connection_status = connected_status_label
        end
        update_movement(my_entity)

        local now = get_client_time()
        sync_virtual_joystick_slots(my_entity, now)

        -- Processar habilidades dos botões virtuais (slots 1 a 4)
        local is_dead = my_entity.is_dead or (my_entity.properties and my_entity.properties["is_dead"] == "true")
        if not is_dead and show_touch_controls then
            local move_dx, move_dy = read_move_input()

            -- Botão 1: ataque básico com mira automática no inimigo mais próximo.
            -- Segurar o botão mantém o personagem atacando (hold-to-cast) no ritmo
            -- do cooldown da skill; cada disparo reavalia o alvo mais próximo.
            -- Fallback de mira: direção de movimento/última direção (facing).
            if virtual_joystick.is_skill_active(1) then
                cast_basic_attack(my_entity, now, true)
            end

            -- Botão 2: quick cast com mira automática no inimigo mais próximo no alcance da skill (fallback: movimento/facing)
            local s2_name = SkillRanges.resolve_entity_skill(my_entity, 2)
            if s2_name and virtual_joystick.is_skill_active(2) and virtual_joystick.can_trigger_skill(2, now) then
                local meta = SKILL_HUD_META[s2_name] or SkillRanges.meta(s2_name)
                local cd_dur = (meta and meta.cooldown) or 0.5
                start_slot_cooldown(2, cd_dur, now)
                sync_virtual_joystick_slots(my_entity, now)
                virtual_joystick.trigger_skill(2, now)
                local action_dx, action_dy = resolve_quick_cast_aim(my_entity, 2)
                loci.send_action(2, action_dx, action_dy)
            end

            -- Botões 3 e 4: sempre disparam no release (drag-to-aim ou quick-tap com fallback de facing)
            local release_events = virtual_joystick.pop_release_events()
            for _, event in ipairs(release_events) do
                local slot = event.skill_id
                local skill_name = SkillRanges.resolve_entity_skill(my_entity, slot)
                if skill_name and slot >= 3 and slot <= 4 and virtual_joystick.can_trigger_skill(slot, now) then
                    -- Não disparar se foi cancelado (arrastou de volta para a zona de cancelamento)
                    if not event.is_cancelled then
                        local meta = SKILL_HUD_META[skill_name] or SkillRanges.meta(skill_name)
                        local cd_dur = (meta and meta.cooldown) or 0.5
                        start_slot_cooldown(slot, cd_dur, now)
                        sync_virtual_joystick_slots(my_entity, now)

                        -- Determinar direção de mira
                        local action_dx, action_dy
                        if event.was_aiming then
                            -- Release-to-cast: usar direção do arrasto e atualizar facing
                            action_dx, action_dy = event.aim_dx, event.aim_dy
                            procedural_anim.set_facing_vector(my_entity.id, action_dx, action_dy)
                        else
                            -- Quick tap: mira automática no inimigo mais próximo no alcance da skill (fallback: movimento/facing)
                            action_dx, action_dy = resolve_quick_cast_aim(my_entity, slot)
                        end

                        loci.send_action(slot, action_dx, action_dy)
                    end
                end
            end
        else
            -- Se estiver morto, descarta eventos de release para evitar disparo fantasma pós-respawn
            if is_dead and show_touch_controls then
                virtual_joystick.pop_release_events()
            end
        end

        -- Segurar Espaço = ataque básico contínuo com auto-aim (paridade com o botão 1 touch)
        if not is_dead and love.keyboard.isDown("space") then
            cast_basic_attack(my_entity, love.timer.getTime(), false)
        end
    else
        movement_sync:on_entity_missing()
    end

    -- Passagem única de clamp por frame (cobre dash local — cujo ramo no SDK ignora
    -- _prediction_handler — além de extrapolação de remotas em jitter) + animação e câmera.
    local clamped_my_entity = false
    local entities = loci.get_entities()
    for _, ent in ipairs(entities) do
        local is_local = my_entity and (ent.id == my_entity.id)
        if is_local then
            clamped_my_entity = true
        end
        if should_clamp_entity(ent) then
            clamp_entity_to_arena(ent, is_local, is_local)
        end
        local is_moving = false
        local vx = ent.vx or 0
        local vy = ent.vy or 0
        local speed = math.sqrt(vx * vx + vy * vy)
        if speed > 0.05 then
            is_moving = true
        end
        local p_state = procedural_anim.update_walk(dt, ent.id, is_moving, vx, vy)
        local char_name = ent.character_name or (ent.properties and ent.properties["character_name"]) or ""
        local is_dead = ent.is_dead or (ent.properties and ent.properties["is_dead"] == "true")
        sprite_anim.update(dt, ent.id, {
            character_name = char_name,
            direction = p_state and p_state.direction or "south",
            facing = p_state and p_state.facing or 1,
            is_moving = is_moving,
            speed = speed,
            is_dead = is_dead
        })
    end

    if my_entity then
        -- Alcances autoritativos publicados pelo servidor (indicador de mira e VFX)
        SkillRanges.update(my_entity.get and my_entity:get("skill_ranges", "") or nil)

        if not clamped_my_entity and should_clamp_entity(my_entity) then
            clamp_entity_to_arena(my_entity, true, true)
        end
        -- Direct camera binding eliminates lag jitter between camera and player
        cam_x = my_entity.x * VISUAL_SCALE
        cam_y = my_entity.y * VISUAL_SCALE
    end

    -- Update rejection message timer
    if rejection_timer > 0 then
        rejection_timer = rejection_timer - dt
    end

    -- Update VFX, floating damage numbers, impact particles and screen shake
    VfxSystem.update(dt)
end

function love.resize(w, h)
    push:resize(w, h)
    virtual_joystick.set_hud_state({ safe_top = get_safe_top_virtual() })
end

local function cast_ability_at_mouse(ability_id)
    local me = loci.get_my_entity()
    local is_dead = me and (me.is_dead or (me.properties and me.properties["is_dead"] == "true"))
    if is_dead then
        print("[Client] Cannot cast - you are dead!")
        return
    end

    local mx, my = push:toGame(love.mouse.getPosition())
    if not mx then return end

    local sw, sh = GAME_WIDTH, GAME_HEIGHT
    local world_target_x = (mx - sw / 2) + cam_x
    local world_target_y = (my - sh / 2) + cam_y

    -- Converte coordenadas de tela/câmera para coordenadas de mundo reais
    local aim_x = world_target_x / VISUAL_SCALE
    local aim_y = world_target_y / VISUAL_SCALE

    loci.send_action_at_position(ability_id, aim_x, aim_y)
end

local LATENCY_PRESETS = { 0, 0.050, 0.100 }
local PACKET_LOSS_PRESETS = { 0, 0.10, 0.25 }

local function cycle_netcode_preset(field, presets)
    if not loci.netcode then return 0 end
    local cur = tonumber(loci.netcode[field]) or 0
    for i, val in ipairs(presets) do
        if math.abs(cur - val) < 1e-4 then
            local next_val = presets[(i % #presets) + 1]
            loci.netcode[field] = next_val
            return next_val
        end
    end
    local next_val = presets[2] or 0
    loci.netcode[field] = next_val
    return next_val
end

function love.keypressed(key)
    if client_state ~= "in_game" then
        ConnectScreen.keypressed(key)
        return
    end

    if key == "f3" then
        show_debug_overlay = not show_debug_overlay
    elseif key == "f4" then
        if loci.export_network_stats_csv then
            local path = loci.export_network_stats_csv()
            if path then
                print("[Client] Telemetria exportada via F4: " .. tostring(path))
            else
                print("[Client] Falha ao exportar telemetria via F4")
            end
        end
    elseif key == "f5" then
        -- Alternar latência simulada por sentido (0ms -> 50ms -> 100ms -> 0ms)
        local next_lat = cycle_netcode_preset("simulate_latency", LATENCY_PRESETS)
        local lat_ms = math.floor(next_lat * 1000 + 0.5)
        print(string.format("[Client] Latência simulada ajustada para: %d ms/sentido (~+%d ms RTT)", lat_ms, lat_ms * 2))
    elseif key == "f6" then
        -- Alternar perda de pacotes simulada (0% -> 10% -> 25% -> 0%)
        local next_loss = cycle_netcode_preset("simulate_packet_loss", PACKET_LOSS_PRESETS)
        print(string.format("[Client] Perda simulada ajustada para: %d%%", math.floor(next_loss * 100 + 0.5)))
    elseif key == "c" then
        show_character_sheet = not show_character_sheet
    elseif key == "t" or key == "f1" then
        show_touch_controls = not show_touch_controls
        if not show_touch_controls then
            virtual_joystick.reset()
        end
    elseif key == "tab" then
        kda_ui.show()
    elseif key == "q" then
        cast_ability_at_mouse(2)
    elseif key == "e" then
        cast_ability_at_mouse(3)
    elseif key == "r" then
        cast_ability_at_mouse(4)
    elseif key == "k" then
        -- Troca de personagem provisória (cicla: arya -> warrior -> archer -> mage -> cleric -> enchanter -> arya)
        request_swap_hero()
    elseif key == "m" then
        local enabled = AudioSystem.toggle_mute()
        print("[Audio] Áudio " .. (enabled and "ativado" or "desativado (mudo)"))
    end
end

function love.textinput(text)
    if client_state ~= "in_game" then
        ConnectScreen.textinput(text)
    end
end

function love.keyreleased(key)
    if client_state ~= "in_game" then return end
    if key == "tab" then
        kda_ui.hide()
    end
end

-- Touch handlers para joysticks virtuais e tela de conexão
-- No Love2D 11.x, love.touchpressed/touchmoved já recebem x, y em coordenadas da janela (0..W, 0..H).
function love.touchpressed(id, x, y, dx, dy, pressure)
    if client_state ~= "in_game" then
        local gx, gy = push:toGame(x, y)
        return ConnectScreen.handle_press(gx, gy)
    end
    if not show_touch_controls then return end
    return virtual_joystick.handle_touchpress(id, x, y)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if client_state ~= "in_game" or not show_touch_controls then return end
    return virtual_joystick.handle_touchmove(id, x, y)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    if client_state ~= "in_game" or not show_touch_controls then return end
    return virtual_joystick.handle_touchrelease(id)
end

-- Suporte a mouse para testes no desktop (filtra istouch para evitar duplicação no mobile)
function love.mousepressed(x, y, button, istouch, presses)
    if istouch then return end
    if client_state ~= "in_game" then
        if button == 1 then
            local gx, gy = push:toGame(x, y)
            return ConnectScreen.handle_press(gx, gy)
        end
        return false
    end
    if not show_touch_controls then return end
    if virtual_joystick.handle_mousepressed(x, y, button) then
        return true
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if istouch or client_state ~= "in_game" or not show_touch_controls then return end
    if virtual_joystick.handle_mousemoved(x, y) then
        return true
    end
end

function love.mousereleased(x, y, button, istouch, presses)
    if istouch or client_state ~= "in_game" or not show_touch_controls then return end
    if virtual_joystick.handle_mousereleased(x, y, button) then
        return true
    end
end

function love.focus(focused)
    if not focused then
        virtual_joystick.reset()
        if client_state == "in_game" and loci.send_move then
            loci.send_move(0, 0)
        end
    elseif client_state == "in_game" and is_connection_lost and loci.resume then
        loci.resume(current_server_ip, current_server_port, current_player_name)
    end
end

-- ============================================================================
-- HUD Functions
-- ============================================================================

-- Desenha barra de HP/Mana/Escudo fixa e status de conexão
local function draw_combat_hud(my_entity)
    local prev_font = love.graphics.getFont()
    love.graphics.setFont(font_hud_small)

    local sw, sh = GAME_WIDTH, GAME_HEIGHT

    if my_entity then
        local hp = tonumber(my_entity:get("hp", 100)) or 100
        local max_hp = tonumber(my_entity:get("max_hp", 100)) or 100
        local mana = tonumber(my_entity:get("mana", 100)) or 100
        local max_mana = tonumber(my_entity:get("max_mana", 100)) or 100
        local shield = tonumber(my_entity:get("shield", 0)) or 0

        local bar_width = 200
        local bar_height = 12
        local x = 20
        local y = 20

        -- Barra de HP
        local hp_pct = math.max(0, math.min(1, max_hp > 0 and (hp / max_hp) or 0))
        love.graphics.setColor(0.2, 0.1, 0.1, 0.8)
        love.graphics.rectangle("fill", x, y, bar_width, bar_height)
        love.graphics.setColor(0.85, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", x, y, bar_width * hp_pct, bar_height)
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.print(string.format("HP: %d/%d", hp, max_hp), x + bar_width + 10, y - 1)

        -- Barra de Escudo (se houver)
        if shield > 0 then
            y = y + 16
            local shield_pct = math.max(0.05, math.min(1, max_hp > 0 and (shield / max_hp) or 1))
            love.graphics.setColor(0.1, 0.1, 0.2, 0.8)
            love.graphics.rectangle("fill", x, y, bar_width, bar_height)
            love.graphics.setColor(0.4, 0.6, 0.95, 1)
            love.graphics.rectangle("fill", x, y, bar_width * shield_pct, bar_height)
            love.graphics.setColor(1, 1, 1, 0.85)
            love.graphics.print(string.format("Escudo: %d", shield), x + bar_width + 10, y - 1)
        end

        -- Barra de Mana
        y = y + 16
        local mana_pct = math.max(0, math.min(1, max_mana > 0 and (mana / max_mana) or 0))
        love.graphics.setColor(0.1, 0.1, 0.2, 0.8)
        love.graphics.rectangle("fill", x, y, bar_width, bar_height)
        love.graphics.setColor(0.2, 0.4, 0.9, 1)
        love.graphics.rectangle("fill", x, y, bar_width * mana_pct, bar_height)
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.print(string.format("Mana: %d/%d", mana, max_mana), x + bar_width + 10, y - 1)
    end

    -- Status de conexão e controles (sempre visível, mesmo antes do spawn)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 10, sh - 62, 680, 52, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Loci Arena", 20, sh - 55)
    love.graphics.setColor(0.7, 0.7, 0.85, 1)
    love.graphics.print(connection_status, 20, sh - 38)
    love.graphics.setColor(1, 1, 1, 0.75)
    local audio_label = AudioSystem.is_enabled() and "M: Som ON" or "M: Mudo"
    love.graphics.print("WASD: Mover | Espaço/Q/E/R: Skills | TAB: Placar | K: Trocar | T: Touch UI | C: Ficha | " .. audio_label, 20, sh - 22)

    if rejection_timer > 0 then
        love.graphics.setColor(0.95, 0.25, 0.25, 0.95)
        love.graphics.printf(rejection_msg, 0, 65, sw, "center")
    end

    if prev_font then
        love.graphics.setFont(prev_font)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Desenha hotbar de habilidades com cooldown, custo de mana, fúria e CC reais
local function draw_hotbar(my_entity)
    if not my_entity then
        return
    end

    local prev_font = love.graphics.getFont()
    local prev_line_width = love.graphics.getLineWidth and love.graphics.getLineWidth() or 1

    local slot_width = 62
    local slot_height = 54
    local padding = 10
    local start_x = 20
    local start_y = 92

    local current_time = get_client_time()
    local cc_label, cc_remaining = get_active_cc(my_entity)

    if cc_label then
        love.graphics.setFont(font_hud_small)
        love.graphics.setColor(0.95, 0.3, 0.3, 0.95)
        love.graphics.print(string.format("CC ATIVO: %s (%.1fs)", cc_label, cc_remaining), start_x, start_y - 18)
    end

    local fury_value = my_entity:get("fury_active")
    local fury_active = fury_value == true or fury_value == "true"

    -- Verificar se há aliados no time (espelha server/scripts/default_arena/data/skills/fury_reward.lua)
    local has_allies = false
    local my_team = tostring((my_entity.get and my_entity:get("team")) or my_entity.team or "1")
    local all_entities = (loci.get_entities and loci.get_entities()) or {}
    for _, other in ipairs(all_entities) do
        if other.id ~= my_entity.id then
            local ent_type = (other.get and other:get("entity_type")) or (other.properties and other.properties["entity_type"])
            local is_player = (ent_type == nil) or (string.lower(tostring(ent_type)) == "player")
            if is_player then
                local other_team = (other.get and other:get("team")) or (other.properties and other.properties["team"])
                if other_team ~= nil and tostring(other_team) == my_team then
                    has_allies = true
                    break
                end
            end
        end
    end

    local mana = tonumber(my_entity:get("mana", 0)) or 0
    local raw_skills_list = my_entity.get and my_entity:get("skills_list", "") or ""
    local char_name = string.lower(tostring((my_entity.get and my_entity:get("character_name", "default")) or "default"))

    for _, entry in ipairs(HOTBAR_SLOTS) do
        local slot = entry.slot
        local x = start_x + (slot - 1) * (slot_width + padding)
        local y = start_y

        local skill_name = get_entity_skill_by_slot(my_entity, slot)
        if not skill_name and raw_skills_list == "" and slot == 1 then
            skill_name = (char_name == "mage") and "fireball" or "slash"
        end

        if not skill_name then
            -- Slot não disponível para o herói atual
            love.graphics.setColor(0.10, 0.10, 0.14, 0.55)
            love.graphics.rectangle("fill", x, y, slot_width, slot_height, 4)
            love.graphics.setColor(0.28, 0.28, 0.35, 0.45)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", x, y, slot_width, slot_height, 4)
            love.graphics.setFont(font_hud_small)
            love.graphics.setColor(0.55, 0.55, 0.65, 0.6)
            love.graphics.print("-", x + slot_width / 2 - 3, y + 14)
            love.graphics.print(entry.key, x + 5, y + slot_height - 17)
        else
            local meta = SKILL_HUD_META[skill_name] or { label = skill_name, cooldown = 0, mana_cost = 0 }
            local cd_remaining = 0
            if cooldown_slots[slot].active then
                local rem = cooldown_slots[slot].duration - (current_time - cooldown_slots[slot].start_time)
                if rem <= 0 then
                    cooldown_slots[slot].active = false
                else
                    cd_remaining = rem
                end
            end

            local is_on_cooldown = cd_remaining > 0
            local no_mana = mana < (meta.mana_cost or 0)
            local is_fury_locked = (skill_name == "fury_reward" and not fury_active and has_allies)

            -- Fundo do slot
            if cc_label then
                love.graphics.setColor(0.55, 0.18, 0.18, 0.85)
            elseif is_fury_locked then
                love.graphics.setColor(0.12, 0.12, 0.16, 0.65)
            elseif is_on_cooldown then
                love.graphics.setColor(0.25, 0.25, 0.35, 0.85)
            elseif no_mana then
                love.graphics.setColor(0.25, 0.20, 0.28, 0.85)
            elseif fury_active then
                love.graphics.setColor(0.80, 0.40, 0.10, 0.85)
            else
                love.graphics.setColor(0.15, 0.15, 0.22, 0.85)
            end
            love.graphics.rectangle("fill", x, y, slot_width, slot_height, 4)

            -- Borda (destaque dourado enquanto Fúria está ativa)
            if fury_active then
                love.graphics.setColor(1.0, 0.65, 0.15, 0.95)
            elseif cc_label then
                love.graphics.setColor(0.95, 0.30, 0.30, 0.90)
            elseif is_fury_locked then
                love.graphics.setColor(0.32, 0.32, 0.38, 0.55)
            else
                love.graphics.setColor(0.45, 0.45, 0.55, 0.70)
            end
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x, y, slot_width, slot_height, 4)

            -- Nome da habilidade e estado (cooldown / falta de mana / bloqueada / pronta)
            love.graphics.setFont(font_hud_small)
            local label_alpha = (is_on_cooldown and 0.65) or (is_fury_locked and 0.45) or 0.95
            love.graphics.setColor(1, 1, 1, label_alpha)
            love.graphics.print(meta.label, x + 5, y + 5)

            if is_fury_locked then
                love.graphics.setColor(0.75, 0.45, 0.45, 0.9)
                love.graphics.print("BLOQ.", x + 5, y + 20)
            elseif is_on_cooldown then
                love.graphics.setColor(0.95, 0.85, 0.4, 1)
                love.graphics.print(string.format("%.1fs", cd_remaining), x + 5, y + 20)
            elseif no_mana then
                love.graphics.setColor(0.65, 0.75, 1.0, 0.95)
                love.graphics.print("MANA", x + 5, y + 20)
            elseif fury_active and skill_name == "fury_reward" then
                love.graphics.setColor(1.0, 0.95, 0.5, 1)
                love.graphics.print("PRONTA!", x + 5, y + 20)
            end

            -- Tecla
            love.graphics.setColor(0.8, 0.8, 0.9, is_fury_locked and 0.45 or 0.85)
            love.graphics.print(entry.key, x + 5, y + slot_height - 17)
        end
    end

    if prev_font then
        love.graphics.setFont(prev_font)
    end
    love.graphics.setLineWidth(prev_line_width)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Desenha contador regressivo de respawn
local function draw_respawn_timer()
    local prev_font = love.graphics.getFont()
    local sw, sh = GAME_WIDTH, GAME_HEIGHT
    local box_w, box_h = 260, 76
    local bx = (sw - box_w) / 2
    local by = (sh - box_h) / 2

    local remaining = math.max(0, respawn_state.duration - (get_client_time() - respawn_state.start_time))

    love.graphics.setColor(0.05, 0.05, 0.08, 0.85)
    love.graphics.rectangle("fill", bx, by, box_w, box_h, 8, 8)
    love.graphics.setColor(0.85, 0.2, 0.2, 1)
    love.graphics.setFont(font_hud_normal)
    love.graphics.printf("YOU DIED", 0, by + 12, sw, "center")
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.setFont(font_hud_small)
    love.graphics.printf(string.format("Respawn em %.1fs", remaining), 0, by + 44, sw, "center")

    if prev_font then
        love.graphics.setFont(prev_font)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function love.draw()
    push:start()

    local sw, sh = GAME_WIDTH, GAME_HEIGHT
    if client_state ~= "in_game" then
        ConnectScreen.draw(sw, sh)
        push:finish()
        return
    end

    local center_x = sw / 2
    local center_y = sh / 2

    -- 1. Arena World Rendering
    love.graphics.push()
    love.graphics.translate(center_x, center_y)

    -- Apply screen shake offset when active (smooth linear damping over duration)
    local shake_offset_x, shake_offset_y = VfxSystem.get_shake_offset()
    love.graphics.translate(-cam_x + shake_offset_x, -cam_y + shake_offset_y)

    -- Draw background grid & physical collision boundaries
    draw_arena_grid()

    -- Draw transient procedural fallback effects & despawn impact VFX
    VfxSystem.draw_world_effects()

    -- Draw all network entities
    local my_entity = loci.get_my_entity()
    local entities = loci.get_entities()
    for _, ent in ipairs(entities) do
        draw_entity(ent, my_entity and (ent.id == my_entity.id))
    end

    -- Draw aim indicator (drag-to-aim) dinâmico conforme o personagem e skills_list ativos
    if my_entity and show_touch_controls then
        for slot = 1, 4 do
            local aim_skill = SkillRanges.resolve_entity_skill(my_entity, slot)
            local skill_range_world = aim_skill and SkillRanges.range(aim_skill) or nil
            if aim_skill and skill_range_world and (virtual_joystick.is_aiming(slot) or virtual_joystick.is_skill_cancelled(slot)) then
                local aim_dx, aim_dy = virtual_joystick.get_aim_vector(slot)
                if math.abs(aim_dx) > 0.01 or math.abs(aim_dy) > 0.01 then
                    local player_x = my_entity.x * VISUAL_SCALE
                    local player_y = (my_entity.y * VISUAL_SCALE) - (SPRITE_BASE_SIZE * SPRITE_SCALE) / 2 -- Centro do corpo a partir dos pés do modelo escalado
                    local aim_length = skill_range_world * VISUAL_SCALE
                    local end_x = player_x + aim_dx * aim_length
                    local end_y = player_y + aim_dy * aim_length

                    -- Verificar se está cancelado
                    local is_cancelled = virtual_joystick.is_skill_cancelled(slot)

                    -- Linha de mira no chão (vermelho se cancelado, amarelo se aiming)
                    if is_cancelled then
                        love.graphics.setColor(1.0, 0.2, 0.2, 0.6)
                    else
                        love.graphics.setColor(1.0, 1.0, 0.3, 0.6)
                    end
                    love.graphics.setLineWidth(3)
                    love.graphics.line(player_x, player_y, end_x, end_y)

                    -- Círculo no final (indicando o alcance ou área de impacto)
                    local circle_radius = SkillRanges.aoe(aim_skill, 1) * VISUAL_SCALE -- raio real da AoE
                    if is_cancelled then
                        love.graphics.setColor(1.0, 0.2, 0.2, 0.3)
                        love.graphics.circle("fill", end_x, end_y, circle_radius)
                        love.graphics.setColor(1.0, 0.2, 0.2, 0.8)
                    else
                        love.graphics.setColor(1.0, 1.0, 0.3, 0.3)
                        love.graphics.circle("fill", end_x, end_y, circle_radius)
                        love.graphics.setColor(1.0, 1.0, 0.3, 0.8)
                    end
                    love.graphics.circle("line", end_x, end_y, circle_radius)

                    -- Pequeno triângulo na direção
                    local arrow_size = 15
                    local angle = math.atan2(aim_dy, aim_dx)
                    if is_cancelled then
                        love.graphics.setColor(1.0, 0.2, 0.2, 0.9)
                    else
                        love.graphics.setColor(1.0, 1.0, 0.3, 0.9)
                    end
                    love.graphics.polygon("fill",
                        end_x,
                        end_y,
                        end_x - math.cos(angle - 0.4) * arrow_size,
                        end_y - math.sin(angle - 0.4) * arrow_size,
                        end_x - math.cos(angle + 0.4) * arrow_size,
                        end_y - math.sin(angle + 0.4) * arrow_size
                    )
                    love.graphics.setLineWidth(1)
                end
            end
        end
    end

    -- Draw floating damage numbers (renderizado sobre os personagens)
    VfxSystem.draw_floating_damage()

    love.graphics.pop()

    -- 2. HUD & UI Layer
    draw_combat_hud(my_entity)
    draw_hotbar(my_entity)

    -- 3. Respawn Timer (se morto)
    local raw_is_dead = my_entity and ((my_entity.get and my_entity:get("is_dead")) or my_entity.is_dead or (my_entity.properties and my_entity.properties["is_dead"]))
    local is_dead = raw_is_dead == true or raw_is_dead == "true"
    if is_dead then
        if not respawn_state.active then
            respawn_state.active = true
            respawn_state.start_time = get_client_time()
            respawn_state.duration = RESPAWN_DURATION_SECONDS
            reset_cooldown_slots()
        end
        draw_respawn_timer()
    else
        respawn_state.active = false
    end

    -- 4. KDA UI
    kda_ui.draw(entities, my_entity)

    -- 4. Debug Overlay
    if show_debug_overlay then
        draw_debug(sw, sh)
    end

    -- 4. Character Sheet Overlay (C)
    if show_character_sheet then
        draw_character_sheet(sw, sh, my_entity)
    end

    -- 5. Virtual Joysticks (quando ativos e visíveis)
    if show_touch_controls then
        virtual_joystick.draw()
    end

    -- 6. Banner de Perda de Conexão / Reconexão (ADR 0002)
    if is_connection_lost then
        local banner_w = 340
        local banner_h = 36
        local bx = (sw - banner_w) / 2
        local by = 56
        love.graphics.setColor(0.85, 0.15, 0.15, 0.92)
        love.graphics.rectangle("fill", bx, by, banner_w, banner_h, 6, 6)
        love.graphics.setColor(0.95, 0.35, 0.35, 0.95)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", bx, by, banner_w, banner_h, 6, 6)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Conexão instável / Reconectando...", 0, by + 9, sw, "center")
    end

    push:finish()
end

function draw_arena_grid()
    local v_min = ARENA_MIN * VISUAL_SCALE
    local v_max = ARENA_MAX * VISUAL_SCALE
    local v_size = ARENA_SIZE * VISUAL_SCALE

    -- Outer void background beyond map bounds
    love.graphics.setColor(0.06, 0.07, 0.10, 1.0)
    love.graphics.rectangle("fill", -1000 * VISUAL_SCALE, -1000 * VISUAL_SCALE, 2000 * VISUAL_SCALE, 2000 * VISUAL_SCALE)

    -- Playable arena floor (matching server MapBounds: [-500, +500])
    love.graphics.setColor(0.10, 0.12, 0.17, 1.0)
    love.graphics.rectangle("fill", v_min, v_min, v_size, v_size)

    -- Interior grid lines every 50 pixels
    love.graphics.setColor(0.18, 0.22, 0.32, 0.35)
    love.graphics.setLineWidth(1)
    for x = v_min, v_max, 50 * VISUAL_SCALE do
        love.graphics.line(x, v_min, x, v_max)
    end
    for y = v_min, v_max, 50 * VISUAL_SCALE do
        love.graphics.line(v_min, y, v_max, y)
    end

    -- Outer collision barrier glow
    love.graphics.setColor(0.25, 0.55, 0.95, 0.25)
    love.graphics.setLineWidth(5)
    love.graphics.rectangle("line", v_min - 2, v_min - 2, v_size + 4, v_size + 4)

    -- Authoritative boundary wall line
    love.graphics.setColor(0.35, 0.65, 1.0, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", v_min, v_min, v_size, v_size)

    -- Origin crosshair at (0, 0)
    love.graphics.setColor(0.4, 0.6, 0.85, 0.7)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(-20, 0, 20, 0)
    love.graphics.line(0, -20, 0, 20)
    love.graphics.setColor(0.6, 0.75, 0.9, 0.6)
    love.graphics.print("(0, 0)", 6, 6)

    -- Draw arena obstacles
    draw_arena_obstacles()
end

function draw_arena_obstacles()
    -- Renderizar obstáculos dinamicamente via SDK (loci.get_obstacles)
    local obstacles = loci.get_obstacles()
    if not obstacles then return end

    for _, obs in ipairs(obstacles) do
        local ox = obs.x * VISUAL_SCALE
        local oy = obs.y * VISUAL_SCALE

        if obs.shape == "circle" then
            local radius = obs.radius * VISUAL_SCALE
            love.graphics.setColor(0.30, 0.40, 0.50, 0.85)
            love.graphics.circle("fill", ox, oy, radius)
            love.graphics.setColor(0.5, 0.6, 0.7, 0.95)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", ox, oy, radius)
        elseif obs.shape == "aabb" then
            local width = obs.width * VISUAL_SCALE
            local height = obs.height * VISUAL_SCALE
            local half_w = width / 2
            local half_h = height / 2
            local bp = tostring(obs.blueprint or "")
            local is_crate = (bp:find("crate", 1, true) ~= nil) or (obs.collision_type == "destructible")
            if is_crate then
                love.graphics.setColor(0.45, 0.35, 0.25, 0.85)
            else
                love.graphics.setColor(0.25, 0.35, 0.45, 0.85)
            end
            love.graphics.rectangle("fill", ox - half_w, oy - half_h, width, height)
            if is_crate then
                love.graphics.setColor(0.60, 0.50, 0.40, 0.95)
            else
                love.graphics.setColor(0.40, 0.50, 0.60, 0.95)
            end
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", ox - half_w, oy - half_h, width, height)
        end
    end
    love.graphics.setLineWidth(1)
end

local TEAM_SHADOW_COLORS = {
    ["1"] = {
        alive = { fill = { 0.15, 0.55, 1.0, 0.40 }, ring = { 0.35, 0.75, 1.0, 0.85 } },
        dead = { fill = { 0.2, 0.5, 0.85, 0.18 }, ring = { 0.35, 0.65, 0.95, 0.35 } },
    },
    ["2"] = {
        alive = { fill = { 1.0, 0.22, 0.22, 0.40 }, ring = { 1.0, 0.45, 0.45, 0.85 } },
        dead = { fill = { 0.85, 0.25, 0.25, 0.18 }, ring = { 0.95, 0.35, 0.35, 0.35 } },
    },
    neutral = {
        alive = { fill = { 0.5, 0.5, 0.5, 0.30 }, ring = { 0.7, 0.7, 0.7, 0.60 } },
        dead = { fill = { 0.5, 0.5, 0.5, 0.15 }, ring = { 0.7, 0.7, 0.7, 0.25 } },
    },
}

local function draw_team_shadow(px, py, rx, ry, team, is_dead)
    -- 1. Sombra base escura para ancoragem e profundidade física no chão da arena
    love.graphics.setColor(0, 0, 0, is_dead and 0.20 or 0.35)
    love.graphics.ellipse("fill", px, py, rx, ry)

    -- 2. Preenchimento translúcido e anel de destaque por time ("1" = Azul, "2" = Vermelho, nil = Neutro)
    local palette = (team and TEAM_SHADOW_COLORS[team]) or TEAM_SHADOW_COLORS.neutral
    local style = is_dead and palette.dead or palette.alive

    love.graphics.setColor(style.fill[1], style.fill[2], style.fill[3], style.fill[4])
    love.graphics.ellipse("fill", px, py, rx, ry)

    love.graphics.setColor(style.ring[1], style.ring[2], style.ring[3], style.ring[4])
    love.graphics.setLineWidth(1.5)
    love.graphics.ellipse("line", px, py, rx, ry)
    love.graphics.setLineWidth(1)
end

function draw_entity(ent, is_me)
    if VfxSystem.is_projectile_entity(ent) then
        VfxSystem.draw_projectile(ent)
        return
    end

    local radius = 2 * VISUAL_SCALE
    local px = ent.x * VISUAL_SCALE
    local py = ent.y * VISUAL_SCALE

    -- Verificar se está morto
    local is_dead = ent.is_dead or (ent.properties and ent.properties["is_dead"] == "true")

    -- Verificar escudo (precisa ser antes da barra de HP)
    local shield_active = (ent.shield_active == "1" or ent.shield_active == 1) or 
                          (ent.properties and (ent.properties["shield_active"] == "1" or ent.properties["shield_active"] == 1))
    local shield_value = tonumber(ent.shield or (ent.properties and ent.properties["shield"])) or 0

    local char_name = ent.character_name or (ent.properties and ent.properties["character_name"]) or ""

    -- Estado visual e de orientação da entidade (8 direções)
    local anim_state = procedural_anim.get_state(ent.id)
    local ent_dir = anim_state.direction or "south"

    -- Obter frame animado, pivô real nos pés (ox, oy) e altura visual estável (visual_h)
    local img_to_draw, ox, oy, has_8way, visual_h = sprite_anim.get_frame({
        entity_id = ent.id,
        character_name = char_name,
        direction = ent_dir,
        is_dead = is_dead,
        is_moving = anim_state.is_moving
    })

    -- Dimensões visuais do sprite / modelo (ox = w/2, sprite_h = altura útil para HUD/barra de HP)
    local sprite_w = ox and (ox * 2) or SPRITE_BASE_SIZE
    local sprite_h = visual_h or oy or SPRITE_BASE_SIZE

    -- Escala de renderização: SPRITE_SCALE pixels por pixel do sprite (32px * 2 = 64px na tela)
    local scale = SPRITE_SCALE

    -- Sombra dos pés proporcional ao modelo de 32px ancorada na base (px, py)
    local shadow_radius_x = 13 * scale
    local shadow_radius_y = 4.5 * scale
    local raw_team = ent.team or (ent.properties and ent.properties["team"])
    local team = raw_team ~= nil and tostring(raw_team) or nil
    draw_team_shadow(px, py, shadow_radius_x, shadow_radius_y, team, is_dead)

    -- Pivô nos pés (base central inferior: ox = w/2, oy = h)
    ox = ox or (sprite_w / 2)
    oy = oy or sprite_h

    local draw_x = px
    local draw_y = py -- Posição sólida e alinhada à grade de pixels (sem bobbing procedural)

    if img_to_draw then
        if is_dead then
            love.graphics.setColor(0.5, 0.5, 0.5, 0.75)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end

        -- Para imagem única sem rotações, espelha via facing; para 8 direções do Pixelab, desenha direto sem distorção
        local scale_x = scale
        if not has_8way then
            scale_x = scale * (anim_state.facing or 1)
        end

        love.graphics.draw(
            img_to_draw,
            draw_x,
            draw_y,
            0, -- Sem rotação/tilt (preserva nitidez e grade de pixels)
            scale_x,
            scale,
            ox, oy
        )
    else
        -- Renderizar placeholder padronizado de 32x32 com cor por arquétipo e indicador de facing
        local ph = get_placeholder_for_entity(ent, is_me, is_dead)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            ph,
            draw_x,
            draw_y,
            0, -- Sem rotação/tilt
            scale * (anim_state.facing or 1),
            scale,
            ox, oy
        )
    end

    -- Se morto e sem animação própria de morte, desenhar X procedural centrado no corpo
    if is_dead and not sprite_anim.has_state(char_name, "death") then
        local cy = py - (sprite_h / 2) * scale
        local cross_size = 12 * scale
        love.graphics.setColor(1, 0, 0, 0.85)
        love.graphics.setLineWidth(3)
        love.graphics.line(px - cross_size, cy - cross_size, px + cross_size, cy + cross_size)
        love.graphics.line(px + cross_size, cy - cross_size, px - cross_size, cy + cross_size)
    end

    -- Barra de HP posicionada acima da cabeça do modelo de 32px (top_y = py - sprite_height * scale)
    local hp = tonumber(ent.hp or (ent.properties and ent.properties["hp"]) or 100) or 100
    local max_hp = tonumber(ent.max_hp or (ent.properties and ent.properties["max_hp"]) or 100) or 100
    local bar_w = 44
    local bar_h = 5
    local bar_x = px - bar_w / 2
    local top_y = py - (sprite_h * scale)
    local bar_y = top_y - 14

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
    
    -- Barra de HP (verde normal)
    love.graphics.setColor(0.2, 0.9, 0.3, 1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w * (math.max(0, math.min(1, hp / max_hp))), bar_h)

    -- Barra de Escudo sobreposta (azul ciano com borda de destaque)
    if shield_active and shield_value > 0 then
        local shield_ratio = math.max(0, math.min(1, shield_value / max_hp))
        love.graphics.setColor(0.2, 0.7, 1.0, 0.85)
        love.graphics.rectangle("fill", bar_x, bar_y, bar_w * shield_ratio, bar_h)
        love.graphics.setColor(0.4, 0.85, 1.0, 0.9)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", bar_x - 1, bar_y - 1, bar_w + 2, bar_h + 2)
    end

    -- Player label
    love.graphics.setColor(1, 1, 1, 0.95)
    local label = is_me and "YOU" or ("P" .. tostring(ent.id))
    if is_dead then
        label = label .. " (DEAD)"
    end
    local font = love.graphics.getFont()
    local tw = font:getWidth(label)
    local label_y = bar_y - 14
    love.graphics.print(label, px - tw / 2, label_y)

    -- Status effects (Stun / Desarme)
    local stunned_until = tonumber(ent.stunned_until or (ent.properties and ent.properties["stunned_until"])) or 0
    local disarmed_until = tonumber(ent.disarmed_until or (ent.properties and ent.properties["disarmed_until"])) or 0
    if not is_dead then
        local status_y = label_y - 14
        if stunned_until > 0 then
            love.graphics.setColor(1.0, 0.9, 0.2, 0.95)
            local txt = "* STUNNED *"
            local tw_s = font:getWidth(txt)
            love.graphics.print(txt, px - tw_s / 2, status_y)
        elseif disarmed_until > 0 then
            love.graphics.setColor(1.0, 0.4, 0.4, 0.95)
            local txt = "[DESARMADA]"
            local tw_d = font:getWidth(txt)
            love.graphics.print(txt, px - tw_d / 2, status_y)
        end
    end
end

function draw_debug(sw, sh)
    local box_w = 275
    local box_h = 258
    love.graphics.setColor(0, 0, 0, 0.80)
    love.graphics.rectangle("fill", sw - (box_w + 10), 10, box_w, box_h, 6, 6)
    love.graphics.setColor(0.2, 0.8, 0.4, 0.85)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", sw - (box_w + 10), 10, box_w, box_h, 6, 6)

    local ent_count = #loci.get_entities()
    local me = loci.get_my_entity()

    -- Métricas de Telemetria do SDK (Zero-GC, Card #70)
    local ping = (loci.get_ping and loci.get_ping()) or 0
    local jitter = (loci.get_jitter and loci.get_jitter()) or 0
    local loss = (loci.get_packet_loss and loci.get_packet_loss()) or 0
    local measured_hz = (loci.get_tick_hz and loci.get_tick_hz()) or 0
    local tick_hz = (measured_hz > 0 and measured_hz) or (loci.get_server_tick_rate and loci.get_server_tick_rate()) or 30

    local lx = sw - box_w
    local cur_y = 20

    love.graphics.setColor(0.4, 1.0, 0.5, 1)
    love.graphics.print(string.format("FPS: %d", love.timer.getFPS()), lx, cur_y); cur_y = cur_y + 18
    love.graphics.print(string.format("Sequence: %d", loci._sequence_id or 0), lx, cur_y); cur_y = cur_y + 18
    love.graphics.print(string.format("Entities: %d", ent_count), lx, cur_y); cur_y = cur_y + 18
    if me then
        love.graphics.print(string.format("Pos: (%.1f, %.1f)", me.x, me.y), lx, cur_y); cur_y = cur_y + 18
    end
    love.graphics.print(string.format("Touch UI: %s [T]", show_touch_controls and "ON" or "OFF"), lx, cur_y); cur_y = cur_y + 18

    -- Seção de Telemetria de Rede (RFC 3550 & ADR 0002)
    cur_y = cur_y + 4
    love.graphics.setColor(0.3, 0.85, 1.0, 1)
    love.graphics.print(string.format("Ping: %d ms", math.floor(ping + 0.5)), lx, cur_y); cur_y = cur_y + 18
    love.graphics.print(string.format("Jitter: %.1f ms", jitter), lx, cur_y); cur_y = cur_y + 18
    love.graphics.print(string.format("Loss: %.1f%%", loss), lx, cur_y); cur_y = cur_y + 18
    love.graphics.print(string.format("Tick Rate: %.1f Hz", tick_hz), lx, cur_y); cur_y = cur_y + 18

    -- Atalhos de Diagnóstico
    cur_y = cur_y + 4
    love.graphics.setColor(0.85, 0.85, 0.4, 1)
    local sim_lat = (loci.netcode and loci.netcode.simulate_latency) or 0
    local sim_loss = (loci.netcode and loci.netcode.simulate_packet_loss) or 0
    if sim_lat > 0 or sim_loss > 0 then
        local lat_ms = math.floor(sim_lat * 1000 + 0.5)
        love.graphics.print(string.format("Sim: %dms/way (+%dms RTT) | %d%%", lat_ms, lat_ms * 2, math.floor(sim_loss * 100 + 0.5)), lx, cur_y); cur_y = cur_y + 18
    else
        love.graphics.print("Sim: OFF [F5:Lat F6:Loss]", lx, cur_y); cur_y = cur_y + 18
    end
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.print("Export CSV: [F4]", lx, cur_y)
end

function draw_character_sheet(sw, sh, my_entity)
    if not my_entity then return end

    local x = 10
    local y = 75
    local w = 330
    local h = 335

    -- Background panel
    love.graphics.setColor(0.07, 0.09, 0.14, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)

    -- Border
    love.graphics.setColor(0.28, 0.45, 0.72, 0.8)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", x, y, w, h, 8, 8)

    -- Header bar
    love.graphics.setColor(0.14, 0.19, 0.28, 0.95)
    love.graphics.rectangle("fill", x + 1, y + 1, w - 2, 32, 7, 7)

    love.graphics.setColor(1.0, 0.85, 0.35, 1.0)
    local name = tostring(my_entity:get("character_name", my_entity.name or "Herói"))
    local role = string.upper(tostring(my_entity:get("role", "FIGHTER")))
    love.graphics.print(string.format("%s [%s]", name, role), x + 14, y + 9)

    love.graphics.setColor(0.65, 0.75, 0.9, 0.8)
    love.graphics.print("[C] Fechar", x + w - 75, y + 9)

    -- Atributos da entidade
    local hp = tonumber(my_entity:get("hp", 100)) or 100
    local max_hp = tonumber(my_entity:get("max_hp", 100)) or 100
    local mana = tonumber(my_entity:get("mana", 100)) or 100
    local max_mana = tonumber(my_entity:get("max_mana", 100)) or 100
    local phys_def = tonumber(my_entity:get("phys_def", 0)) or 0
    local mag_def = tonumber(my_entity:get("mag_def", 0)) or 0
    local move_speed = tonumber(my_entity:get("move_speed", 2.0)) or 2.0
    local hp_regen = tonumber(my_entity:get("hp_regen", 0)) or 0
    local mana_regen = tonumber(my_entity:get("mana_regen", 0)) or 0
    local fragile = tostring(my_entity:get("fragile", "0")) == "1"
    local skills_list = tostring(my_entity:get("skills_list", "-"))

    local cur_y = y + 44

    -- Barra de Vida (HP)
    love.graphics.setColor(0.85, 0.9, 0.95, 1)
    love.graphics.print(string.format("Vida: %d / %d", hp, max_hp), x + 14, cur_y)
    cur_y = cur_y + 16
    local hp_pct = math.max(0, math.min(1, max_hp > 0 and (hp / max_hp) or 0))
    love.graphics.setColor(0.12, 0.14, 0.18, 1)
    love.graphics.rectangle("fill", x + 14, cur_y, w - 28, 10, 3, 3)
    love.graphics.setColor(0.2, 0.85, 0.35, 1)
    love.graphics.rectangle("fill", x + 14, cur_y, (w - 28) * hp_pct, 10, 3, 3)
    cur_y = cur_y + 18

    -- Barra de Mana
    love.graphics.setColor(0.85, 0.9, 0.95, 1)
    love.graphics.print(string.format("Mana: %d / %d", mana, max_mana), x + 14, cur_y)
    cur_y = cur_y + 16
    local mana_pct = math.max(0, math.min(1, max_mana > 0 and (mana / max_mana) or 0))
    love.graphics.setColor(0.12, 0.14, 0.18, 1)
    love.graphics.rectangle("fill", x + 14, cur_y, w - 28, 10, 3, 3)
    love.graphics.setColor(0.25, 0.60, 0.95, 1)
    love.graphics.rectangle("fill", x + 14, cur_y, (w - 28) * mana_pct, 10, 3, 3)
    cur_y = cur_y + 20

    -- Linha separadora
    love.graphics.setColor(0.25, 0.32, 0.45, 0.6)
    love.graphics.line(x + 14, cur_y, x + w - 14, cur_y)
    cur_y = cur_y + 10

    -- Mitigações e Defesas
    local phys_mit = (phys_def / (phys_def + 100)) * 100
    local mag_mit = (mag_def / (mag_def + 100)) * 100

    love.graphics.setColor(0.9, 0.7, 0.4, 1)
    love.graphics.print("Defesa Física:", x + 14, cur_y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("%d (%.1f%% mitig.)", phys_def, phys_mit), x + 135, cur_y)
    cur_y = cur_y + 20

    love.graphics.setColor(0.6, 0.8, 1.0, 1)
    love.graphics.print("Defesa Mágica:", x + 14, cur_y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("%d (%.1f%% mitig.)", mag_def, mag_mit), x + 135, cur_y)
    cur_y = cur_y + 20

    love.graphics.setColor(0.7, 0.9, 0.7, 1)
    love.graphics.print("Velocidade:", x + 14, cur_y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("%.1f px/tick", move_speed), x + 135, cur_y)
    cur_y = cur_y + 20

    love.graphics.setColor(0.8, 0.85, 0.95, 1)
    love.graphics.print("Regeneração:", x + 14, cur_y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("+%d HP/s | +%d MP/s", hp_regen, mana_regen), x + 135, cur_y)
    cur_y = cur_y + 20

    -- Habilidades equipadas
    love.graphics.setColor(1.0, 0.85, 0.35, 1)
    love.graphics.print("Habilidade [Espaço]:", x + 14, cur_y)
    love.graphics.setColor(0.9, 0.9, 0.9, 1)
    love.graphics.print(skills_list, x + 160, cur_y)
    cur_y = cur_y + 22

    -- Status de combate
    if fragile then
        love.graphics.setColor(0.95, 0.25, 0.25, 0.95)
        love.graphics.print("STATUS: FRÁGIL (+30% dano)", x + 14, cur_y)
    else
        love.graphics.setColor(0.4, 0.85, 0.5, 0.9)
        love.graphics.print("STATUS: NORMAL", x + 14, cur_y)
    end
end

function love.quit()
    print("[Client] Closing connection...")
    AudioSystem.stop_bgm()
    if loci.quit then
        loci.quit()
    end
    loci.disconnect("Client exiting")
    return false
end
