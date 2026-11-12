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
local MovementSync = require("src.movement_sync")
local GAME_WIDTH, GAME_HEIGHT = 1280, 720

-- Fontes para efeitos visuais (criadas uma vez)
local font_damage_normal = love.graphics.newFont(18)
local font_damage_critical = love.graphics.newFont(24)

-- Configurar push no sistema de joystick para conversão de coordenadas
virtual_joystick.set_push(push)

-- Connection config
local SERVER_IP = os.getenv("LOCI_SERVER_IP") or "127.0.0.1"
local SERVER_PORT = tonumber(os.getenv("LOCI_SERVER_PORT")) or 8080

-- UI & State variables
local connection_status = "Connecting..."
local connected_status_label = ""
local is_connection_lost = false
local movement_sync = MovementSync.new()
local rejection_msg = ""
local rejection_timer = 0
local visual_fx = {}
local floating_damage = {}
local show_debug_overlay = false
local show_character_sheet = false
local show_touch_controls = true

-- Sprites e texturas de personagens (padrão 32x32px)
local SPRITE_BASE_SIZE = 32
-- 🔍 ZOOM DO PERSONAGEM: ajuste SPRITE_SCALE para controlar o tamanho visual na tela.
--   1 = 32px  (tamanho nativo do sprite, compacto)
--   2 = 64px  (atual — bom equilíbrio visual para arena)
--   4 = 128px (equivalente ao sprite 16x16 antigo multiplicado por 8)
local SPRITE_SCALE = 2
local character_sprites = {}
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

local function init_placeholders()
    placeholder_canvases["me"] = create_character_placeholder(0.2, 0.6, 0.95, 0.3, 0.9, 1.0)
    placeholder_canvases["enemy"] = create_character_placeholder(0.9, 0.3, 0.25, 1.0, 0.85, 0.2)
    placeholder_canvases["dead"] = create_character_placeholder(0.35, 0.35, 0.38, 0.5, 0.5, 0.5)
end

local DIRECTIONS_8 = {
    "east", "south-east", "south", "south-west",
    "west", "north-west", "north", "north-east"
}

local function load_character_sprite(character_name)
    if not character_name or character_name == "" then return nil end
    local key = string.lower(character_name)
    if character_sprites[key] ~= nil then
        local cached = character_sprites[key]
        return (cached ~= false and cached) or nil
    end

    local found_info = nil

    -- 1. Tenta carregar pasta com conjunto de 8 direções do Pixelab (ex: assets/sprites/arya/south.png)
    local dir_folder_candidates = {
        "assets/sprites/" .. key,
        "client/assets/sprites/" .. key
    }
    for _, folder in ipairs(dir_folder_candidates) do
        if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(folder .. "/south.png") then
            local rot_images = {}
            local loaded_any = false
            for _, dir in ipairs(DIRECTIONS_8) do
                local p = folder .. "/" .. dir .. ".png"
                if love.filesystem.getInfo(p) then
                    local ok, img = pcall(love.graphics.newImage, p)
                    if ok and img then
                        img:setFilter("nearest", "nearest")
                        rot_images[dir] = img
                        loaded_any = true
                    end
                end
            end
            if loaded_any then
                local def_img = rot_images["south"] or rot_images["east"]
                found_info = {
                    has_rotations = true,
                    rotations = rot_images,
                    image = def_img,
                    width = def_img and def_img:getWidth() or SPRITE_BASE_SIZE,
                    height = def_img and def_img:getHeight() or SPRITE_BASE_SIZE
                }
                print(string.format("[Client] Loaded 8-direction sprite set for '%s' from %s/", character_name, folder))
                break
            end
        end
    end

    -- 2. Fallback: carregar PNG único (ex: assets/sprites/arya.png)
    if not found_info then
        local possible_paths = {
            "assets/sprites/" .. key .. ".png",
            "assets/sprites/" .. character_name .. ".png",
            "client/assets/sprites/" .. key .. ".png"
        }

        for _, path in ipairs(possible_paths) do
            if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path) then
                local ok_img, img = pcall(love.graphics.newImage, path)
                if ok_img and img then
                    img:setFilter("nearest", "nearest")
                    local w = img:getWidth()
                    local h = img:getHeight()
                    print(string.format("[Client] Loaded character sprite '%s' (%dx%d) for '%s'", path, w, h, character_name))
                    found_info = {
                        has_rotations = false,
                        image = img,
                        width = w,
                        height = h
                    }
                    break
                end
            end
        end
    end

    character_sprites[key] = found_info or false
    return found_info
end

local function get_entity_skill_by_slot(entity, slot_index)
    if not entity or not slot_index then return nil end
    local list_str = entity:get("skills_list", "")
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

-- Screen shake state
local shake_duration = 0
local shake_total_duration = 0.2
local shake_intensity = 0

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

local function should_clamp_entity(ent)
    if not ent then return false end
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
local function predict_local_movement(ent, dx, dy, dt)
    if not ent then return end

    local in_dx = dx or 0
    local in_dy = dy or 0
    local len = math.sqrt(in_dx * in_dx + in_dy * in_dy)

    if len > 0 then
        local ndx = in_dx / len
        local ndy = in_dy / len
        local default_speed = (loci.netcode and loci.netcode.default_move_speed) or 3.0
        local raw_speed = (ent.get and (ent:get("move_speed") or ent:get("speed")))
            or (ent.properties and (ent.properties.move_speed or ent.properties.speed))
            or default_speed
        local move_speed = tonumber(raw_speed) or 3.0
        local tick_rate = (loci.get_server_tick_rate and loci.get_server_tick_rate()) or 30.0
        local speed_sec = move_speed * tick_rate

        ent.x = (ent.x or 0) + ndx * speed_sec * dt
        ent.y = (ent.y or 0) + ndy * speed_sec * dt
        ent.vx = ndx * move_speed
        ent.vy = ndy * move_speed
    else
        ent.vx = 0
        ent.vy = 0
    end

    -- Roda antes de decay_error e poll_network: preserva erro corretivo para dentro e bloqueia erro para fora
    clamp_entity_to_arena(ent, true, false)
end

function love.load(arg)
    -- Linear filter ensures smooth sub-pixel interpolation without snapping jitter
    love.graphics.setDefaultFilter("linear", "linear")
    
    push:setupScreen(GAME_WIDTH, GAME_HEIGHT, 1280, 720, {
        fullscreen = false,
        resizable = true,
        pixelperfect = false
    })

    -- Inicializar posições dos controles virtuais para a resolução do jogo
    virtual_joystick.update_with_game_dimensions(GAME_WIDTH, GAME_HEIGHT)

    local random_suffix = tostring(love.math and love.math.random(1000, 9999) or math.random(1000, 9999))
    local player_name = "Player_" .. random_suffix

    print(string.format("[Client] Connecting to %s:%d as '%s'...", SERVER_IP, SERVER_PORT, player_name))
    
    local ok_connect = loci.connect(SERVER_IP, SERVER_PORT, player_name, "loci2d/lib/")
    if not ok_connect then
        ok_connect = loci.connect(SERVER_IP, SERVER_PORT, player_name, "client/loci2d/lib/")
    end

    if not ok_connect then
        connection_status = "Connection error"
        print("[Client] Failed to initialize connection to " .. SERVER_IP .. ":" .. SERVER_PORT)
        return
    end

    is_connection_lost = false
    connected_status_label = "Connected to " .. SERVER_IP .. ":" .. SERVER_PORT .. " (" .. player_name .. ")"
    connection_status = connected_status_label

    if loci.netcode and os.getenv("LOCI_AUTO_EXPORT_CSV") == "1" then
        loci.netcode.auto_export_csv_on_quit = true
    end

    -- Inicializar placeholders padronizados de 32x32px
    init_placeholders()

    -- Pré-carregar sprites disponíveis em assets/sprites/ (padrão 32x32px)
    load_character_sprite("arya")

    -- Registrar predição local com clamp nos limites da arena antes da reconciliação.
    -- Nota: durante dash ativo (`dashing_until`), o SDK desvia para o ramo próprio e não chama
    -- `_prediction_handler`; por isso o clamp pós-`loci.update` em `love.update` cobre o dash.
    if loci.set_prediction_handler then
        loci.set_prediction_handler(predict_local_movement)
    end

    -- Event hooks
    loci.on_entity_spawned = function(entity)
        print(string.format("[Event] Entity spawned: ID %s at (%.1f, %.1f)", tostring(entity.id), entity.x, entity.y))
    end

    loci.on_entity_despawned = function(entity_id)
        print("[Event] Entity despawned: ID " .. tostring(entity_id))
        procedural_anim.clear_state(entity_id)
    end

    loci.on_property_changed = function(entity, key, old_val, new_val)
        -- Hook for HUD/UI state updates (HP, score, buffs)
        if key == "hp" then
            local old_hp = tonumber(old_val) or 0
            local new_hp = tonumber(new_val) or 0
            local damage = old_hp - new_hp

            if damage > 0 then
                -- 1. Screen shake apenas para dano significativo no jogador local
                local my_entity = loci.get_my_entity()
                if my_entity and entity.id == my_entity.id and damage > 50 then
                    shake_total_duration = 0.2
                    shake_duration = 0.2
                    local intensity = math.min(8, 2.5 + (damage / 120))
                    shake_intensity = math.max(shake_intensity, intensity)
                end

                -- 2. Dano flutuante para qualquer entidade (local ou inimiga)
                -- Ataques normais variam de ~150 a 300 de dano após mitigação de defesa;
                -- Golpes com dano >= 350 são críticos reais (multiplicador 2.25x)
                local is_critical = damage >= 350
                local hud_offset_y = (SPRITE_BASE_SIZE * SPRITE_SCALE) + 32 -- Inicia acima da cabeça e HUD do modelo escalado
                table.insert(floating_damage, {
                    value = damage,
                    x = entity.x,
                    y = entity.y,
                    offset_y = hud_offset_y,
                    lifetime = 1.0,
                    max_lifetime = 1.0,
                    is_critical = is_critical,
                    is_shield = false
                })
            end
        elseif key == "shield" then
            local old_shield = tonumber(old_val) or 0
            local new_shield = tonumber(new_val) or 0
            local damage = old_shield - new_shield

            if damage > 0 then
                local my_entity = loci.get_my_entity()
                if my_entity and entity.id == my_entity.id and damage > 50 then
                    shake_total_duration = 0.2
                    shake_duration = 0.2
                    local intensity = math.min(8, 2.5 + (damage / 120))
                    shake_intensity = math.max(shake_intensity, intensity)
                end

                local hud_offset_y = (SPRITE_BASE_SIZE * SPRITE_SCALE) + 32 -- Inicia acima da cabeça e HUD do modelo escalado
                table.insert(floating_damage, {
                    value = damage,
                    x = entity.x,
                    y = entity.y,
                    offset_y = hud_offset_y,
                    lifetime = 1.0,
                    max_lifetime = 1.0,
                    is_critical = false,
                    is_shield = true
                })
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
        local lifetime = 0.35
        if skill_name == "fireball" then
            lifetime = 0.40
        elseif skill_name == "whirlwind_dash" or (not skill_name and ability_id == 3) then
            lifetime = 0.45 -- Whirlwind Dash
        elseif skill_name == "blade_throw" or (not skill_name and ability_id == 4) then
            lifetime = 0.60 -- Blade Throw
        end

        table.insert(visual_fx, {
            x = entity and entity.x or 0,
            y = entity and entity.y or 0,
            dir_x = dx,
            dir_y = dy,
            ability_id = ability_id,
            skill_name = skill_name,
            character_name = character_name,
            lifetime = lifetime,
            max_lifetime = lifetime
        })
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
    local cur_tick = tonumber(loci._last_state_tick) or 0
    local now = (love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    movement_sync:step(my_entity, dx, dy, cur_tick, now, loci)
end

function love.update(dt)
    -- Process incoming network packets and smooth entity interpolation
    loci.update(dt)
    
    local my_entity = loci.get_my_entity()
    if my_entity then
        if is_connection_lost then
            is_connection_lost = false
        end
        if connected_status_label ~= "" and connection_status:find("^Reconnecting") then
            connection_status = connected_status_label
        end
        update_movement(my_entity)

        -- Processar habilidades dos botões virtuais (slots 1 a 4)
        local is_dead = my_entity.is_dead or (my_entity.properties and my_entity.properties["is_dead"] == "true")
        if not is_dead and show_touch_controls then
            local now = love.timer.getTime()

            -- Botões 1 e 2: comportamento original (disparo imediato ao pressionar)
            for slot = 1, 2 do
                if virtual_joystick.is_skill_active(slot) and virtual_joystick.can_trigger_skill(slot, now) then
                    virtual_joystick.trigger_skill(slot, now)

                    -- Usar a direção do joystick de movimento, ou direção padrão se parado
                    local action_dx, action_dy = virtual_joystick.get_move_vector()
                    if math.abs(action_dx) < 0.1 and math.abs(action_dy) < 0.1 then
                        action_dx, action_dy = 0, -1
                    end

                    -- Direção de mira enviada diretamente via vetor do joystick
                    loci.send_action(slot, action_dx, action_dy)
                end
            end

            -- Botões 3 e 4: sempre disparam no release (drag-to-aim)
            local release_events = virtual_joystick.pop_release_events()
            for _, event in ipairs(release_events) do
                local slot = event.skill_id
                if slot >= 3 and slot <= 4 and virtual_joystick.can_trigger_skill(slot, now) then
                    -- Não disparar se foi cancelado (arrastou de volta para a zona de cancelamento)
                    if not event.is_cancelled then
                        virtual_joystick.trigger_skill(slot, now)

                        -- Determinar direção de mira
                        local action_dx, action_dy
                        if event.was_aiming then
                            -- Release-to-cast: usar direção do arrasto
                            action_dx, action_dy = event.aim_dx, event.aim_dy
                        else
                            -- Quick tap: usar direção do joystick de movimento, ou padrão se parado
                            action_dx, action_dy = virtual_joystick.get_move_vector()
                            if math.abs(action_dx) < 0.1 and math.abs(action_dy) < 0.1 then
                                action_dx, action_dy = 0, -1
                            end
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
        procedural_anim.update_walk(dt, ent.id, is_moving, vx, vy)
    end

    if my_entity then
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

    -- Update visual effects (skills)
    for i = #visual_fx, 1, -1 do
        visual_fx[i].lifetime = visual_fx[i].lifetime - dt
        if visual_fx[i].lifetime <= 0 then
            table.remove(visual_fx, i)
        end
    end

    -- Update floating damage numbers
    for i = #floating_damage, 1, -1 do
        local fd = floating_damage[i]
        fd.lifetime = fd.lifetime - dt
        fd.offset_y = fd.offset_y + 50 * dt
        if fd.lifetime <= 0 then
            table.remove(floating_damage, i)
        end
    end

    -- Update screen shake timer
    if shake_duration > 0 then
        shake_duration = shake_duration - dt
        if shake_duration <= 0 then
            shake_duration = 0
            shake_intensity = 0
        end
    end
end

function love.resize(w, h)
    push:resize(w, h)
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
    elseif key == "space" then
        cast_ability_at_mouse(1)
    elseif key == "q" then
        cast_ability_at_mouse(2)
    elseif key == "e" then
        cast_ability_at_mouse(3)
    elseif key == "r" then
        cast_ability_at_mouse(4)
    elseif key == "k" then
        -- Troca de personagem provisória (cicla: arya -> default -> mage -> warrior -> arya)
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
end

function love.keyreleased(key)
    if key == "tab" then
        kda_ui.hide()
    end
end

-- Touch handlers para joysticks virtuais
function love.touchpressed(id, x, y, dx, dy, pressure)
    if not show_touch_controls then return end
    local screen_w, screen_h = love.graphics.getDimensions()
    local real_x = x * screen_w
    local real_y = y * screen_h
    return virtual_joystick.handle_touchpress(id, real_x, real_y)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if not show_touch_controls then return end
    local screen_w, screen_h = love.graphics.getDimensions()
    local real_x = x * screen_w
    local real_y = y * screen_h
    return virtual_joystick.handle_touchmove(id, real_x, real_y)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    if not show_touch_controls then return end
    return virtual_joystick.handle_touchrelease(id)
end

-- Suporte a mouse para testes no desktop (filtra istouch para evitar duplicação no mobile)
function love.mousepressed(x, y, button, istouch, presses)
    if istouch or not show_touch_controls then return end
    if virtual_joystick.handle_mousepressed(x, y, button) then
        return true
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if istouch or not show_touch_controls then return end
    if virtual_joystick.handle_mousemoved(x, y) then
        return true
    end
end

function love.mousereleased(x, y, button, istouch, presses)
    if istouch or not show_touch_controls then return end
    if virtual_joystick.handle_mousereleased(x, y, button) then
        return true
    end
end

function love.draw()
    push:start()

    local sw, sh = GAME_WIDTH, GAME_HEIGHT
    local center_x = sw / 2
    local center_y = sh / 2

    -- 1. Arena World Rendering
    love.graphics.push()
    love.graphics.translate(center_x, center_y)

    -- Apply screen shake offset when active (smooth linear damping over duration)
    local shake_offset_x = 0
    local shake_offset_y = 0
    if shake_duration > 0 and shake_intensity > 0 then
        local current_intensity = shake_intensity * (shake_duration / shake_total_duration)
        shake_offset_x = (love.math.random() - 0.5) * 2 * current_intensity
        shake_offset_y = (love.math.random() - 0.5) * 2 * current_intensity
    end
    love.graphics.translate(-cam_x + shake_offset_x, -cam_y + shake_offset_y)

    -- Draw background grid & physical collision boundaries
    draw_arena_grid()

    -- Draw transient visual effects (Animações e Áreas de Contato)
    for _, fx in ipairs(visual_fx) do
        local progress = fx.lifetime / fx.max_lifetime
        local inv_prog = 1.0 - progress
        local fx_start_x = fx.x * VISUAL_SCALE
        local fx_start_y = (fx.y * VISUAL_SCALE) - (SPRITE_BASE_SIZE * SPRITE_SCALE) / 2 -- Origem no centro do corpo do modelo escalado

        -- Mapeamento de VFX desacoplado por skill_name (com fallback por ability_id / character_name)
        local char_name = string.lower(tostring(fx.character_name or "default"))
        local skill_name = fx.skill_name
        if not skill_name then
            if fx.ability_id == 1 then
                skill_name = (char_name == "mage") and "fireball" or "slash"
            elseif fx.ability_id == 2 then
                skill_name = "fury_reward"
            elseif fx.ability_id == 3 then
                skill_name = "whirlwind_dash"
            elseif fx.ability_id == 4 then
                skill_name = "blade_throw"
            end
        end

        if skill_name == "fireball" then
            -- Fireball: projétil até range * 0.7 (210px) seguido de explosão na área real (aoe_radius = 60px)
            local max_dist = 210
            local travel_t = math.min(1.0, inv_prog / 0.5)
            local travel_dist = max_dist * travel_t
            local fireball_x = fx_start_x + fx.dir_x * travel_dist
            local fireball_y = fx_start_y + fx.dir_y * travel_dist

            if inv_prog <= 0.5 then
                local radius = 18 + 8 * travel_t
                -- Rastro de fogo
                love.graphics.setColor(1.0, 0.4, 0.0, progress * 0.4)
                love.graphics.setLineWidth(3)
                love.graphics.line(fx_start_x, fx_start_y, fireball_x, fireball_y)

                -- Núcleo da bola de fogo em voo
                love.graphics.setColor(1.0, 0.55, 0.1, progress * 0.9)
                love.graphics.circle("fill", fireball_x, fireball_y, radius)
                love.graphics.setColor(1.0, 0.9, 0.3, progress * 0.75)
                love.graphics.circle("fill", fireball_x, fireball_y, radius * 0.6)
                love.graphics.setColor(1.0, 1.0, 0.85, progress * 0.6)
                love.graphics.circle("fill", fireball_x, fireball_y, radius * 0.3)
            else
                -- Explosão expansiva até o raio real da AoE (60px)
                local blast_t = (inv_prog - 0.5) / 0.5
                local blast_alpha = 1.0 - blast_t
                local blast_r = 20 + 40 * blast_t

                love.graphics.setColor(1.0, 0.45, 0.05, blast_alpha * 0.35)
                love.graphics.circle("fill", fireball_x, fireball_y, blast_r)
                love.graphics.setColor(1.0, 0.75, 0.2, blast_alpha * 0.55)
                love.graphics.circle("fill", fireball_x, fireball_y, blast_r * 0.55)
                love.graphics.setColor(1.0, 0.35, 0.05, blast_alpha * 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.circle("line", fireball_x, fireball_y, blast_r)
            end

        elseif skill_name == "slash" then
            -- Slash: Arco cortante frontal metálico/azul claro
            local angle = math.atan2(fx.dir_y, fx.dir_x)
            local radius = 45 * (0.8 + 0.4 * inv_prog)
            love.graphics.setColor(0.9, 0.95, 1.0, progress * 0.9)
            love.graphics.setLineWidth(4)
            love.graphics.arc("line", "open", fx_start_x, fx_start_y, radius, angle - 0.8, angle + 0.8)
            love.graphics.setColor(0.3, 0.7, 1.0, progress * 0.5)
            love.graphics.setLineWidth(8)
            love.graphics.arc("line", "open", fx_start_x, fx_start_y, radius * 0.85, angle - 0.6, angle + 0.6)

        elseif skill_name == "fury_reward" then
            -- Fury Reward: Impacto carmesim/fogo com onda de choque
            local hit_dist = 60 -- (7.5 unidades no mundo * VISUAL_SCALE = 60px na tela)
            local hit_x = fx_start_x + fx.dir_x * hit_dist
            local hit_y = fx_start_y + fx.dir_y * hit_dist
            local r = 50 * (0.5 + 0.8 * inv_prog)
            love.graphics.setColor(1.0, 0.2, 0.2, progress * 0.85)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", hit_x, hit_y, r)
            love.graphics.setColor(1.0, 0.5, 0.1, progress * 0.4)
            love.graphics.circle("fill", hit_x, hit_y, r * 0.6)

        elseif skill_name == "whirlwind_dash" then
            -- Whirlwind Dash: Círculo 360º de corte giratório dourado com lâminas
            local body_offset_y = (SPRITE_BASE_SIZE * SPRITE_SCALE) / 2
            local dash_world_dist = (160 / VISUAL_SCALE) * inv_prog -- Desloca o efeito visual junto com o avanço (20 unidades no mundo)
            local raw_wx = (fx.x or 0) + (fx.dir_x or 0) * dash_world_dist
            local raw_wy = (fx.y or 0) + (fx.dir_y or 0) * dash_world_dist
            local clamped_wx, clamped_wy = clamp_arena_coords(raw_wx, raw_wy)
            local curr_x = clamped_wx * VISUAL_SCALE
            local curr_y = (clamped_wy * VISUAL_SCALE) - body_offset_y
            local r = 65 * (0.7 + 0.5 * inv_prog)
            local spin_angle = inv_prog * math.pi * 5
            love.graphics.setColor(1.0, 0.85, 0.3, progress * 0.85)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", curr_x, curr_y, r)
            love.graphics.setColor(1.0, 0.9, 0.5, progress * 0.6)
            for i = 0, 3 do
                local a = spin_angle + (i * math.pi / 2)
                love.graphics.line(
                    curr_x, curr_y,
                    curr_x + math.cos(a) * r,
                    curr_y + math.sin(a) * r
                )
            end

        elseif skill_name == "blade_throw" then
            -- Blade Throw: Espada viajando até o alvo + impacto expansivo de Stun
            local max_dist = 260
            local travel_dist = max_dist * math.min(1.0, inv_prog * 2.2)
            local blade_x = fx_start_x + fx.dir_x * travel_dist
            local blade_y = fx_start_y + fx.dir_y * travel_dist
            
            -- Rastro de energia do arremesso
            love.graphics.setColor(0.4, 0.8, 1.0, progress * 0.7)
            love.graphics.setLineWidth(2)
            love.graphics.line(fx_start_x, fx_start_y, blade_x, blade_y)

            -- Lâmina em voo
            love.graphics.setColor(1.0, 1.0, 1.0, progress)
            love.graphics.circle("fill", blade_x, blade_y, 7)
            love.graphics.setColor(0.2, 0.6, 1.0, progress)
            love.graphics.circle("line", blade_x, blade_y, 7)

            -- Onda de choque de Stun na área de impacto
            if inv_prog > 0.45 then
                local shock_r = 55 * ((inv_prog - 0.45) / 0.55)
                love.graphics.setColor(1.0, 0.9, 0.2, progress * 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.circle("line", blade_x, blade_y, shock_r)
            end
        else
            -- Efeito padrão
            local fx_end_x = fx_start_x + fx.dir_x * 50 * VISUAL_SCALE
            local fx_end_y = fx_start_y + fx.dir_y * 50 * VISUAL_SCALE
            love.graphics.setColor(1, 0.85, 0.2, progress)
            love.graphics.line(fx_start_x, fx_start_y, fx_end_x, fx_end_y)
            love.graphics.circle("fill", fx_end_x, fx_end_y, 5 * progress)
        end
    end

    -- Draw all network entities
    local my_entity = loci.get_my_entity()
    local entities = loci.get_entities()
    for _, ent in ipairs(entities) do
        draw_entity(ent, my_entity and (ent.id == my_entity.id))
    end

    -- Draw aim indicator (drag-to-aim) enquanto botões 3 ou 4 estão aiming ou cancelando
    if my_entity and show_touch_controls then
        -- Alcance no mundo de cada habilidade (em pixels visuais: range * VISUAL_SCALE)
        local SKILL_RANGES = {
            [3] = 160, -- Whirlwind Dash (20.0 * 8)
            [4] = 260, -- Blade Throw (32.5 * 8)
        }

        for slot = 3, 4 do
            if virtual_joystick.is_aiming(slot) or virtual_joystick.is_skill_cancelled(slot) then
                local aim_dx, aim_dy = virtual_joystick.get_aim_vector(slot)
                if math.abs(aim_dx) > 0.01 or math.abs(aim_dy) > 0.01 then
                    local player_x = my_entity.x * VISUAL_SCALE
                    local player_y = (my_entity.y * VISUAL_SCALE) - (SPRITE_BASE_SIZE * SPRITE_SCALE) / 2 -- Centro do corpo a partir dos pés do modelo escalado
                    local aim_length = SKILL_RANGES[slot] or 200
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
                    local circle_radius = (slot == 4) and 14 or 8
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
    if #floating_damage > 0 then
        local original_font = love.graphics.getFont()
        for _, fd in ipairs(floating_damage) do
            local progress = fd.lifetime / fd.max_lifetime
            local alpha = progress
            local scale = 1.0 + (1.0 - progress) * 0.3

            local text_x = fd.x * VISUAL_SCALE
            local text_y = (fd.y * VISUAL_SCALE) - fd.offset_y

            love.graphics.push()
            love.graphics.translate(text_x, text_y)
            love.graphics.scale(scale, scale)

            if fd.is_shield then
                -- Dano absorvido pelo escudo - azul ciano
                love.graphics.setColor(0.3, 0.75, 1.0, alpha)
                love.graphics.setFont(font_damage_normal)
            elseif fd.is_critical then
                -- Dano crítico - vermelho brilhante, maior
                love.graphics.setColor(1.0, 0.15, 0.15, alpha)
                love.graphics.setFont(font_damage_critical)
            else
                -- Dano normal - branco
                love.graphics.setColor(1.0, 1.0, 1.0, alpha)
                love.graphics.setFont(font_damage_normal)
            end

            local damage_text = string.format("%d", fd.value)
            local tw = love.graphics.getFont():getWidth(damage_text)
            love.graphics.print(damage_text, -tw / 2, 0)

            love.graphics.pop()
        end
        love.graphics.setFont(original_font)
        love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
    end

    love.graphics.pop()

    -- 2. HUD & UI Layer
    draw_hud(sw, sh, my_entity)

    -- 3. KDA UI
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
        local by = 16
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
end

function draw_entity(ent, is_me)
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
    local sprite_info = load_character_sprite(char_name)

    -- Dimensões do sprite / modelo (padrão 32x32px)
    local sprite_w = (sprite_info and sprite_info.width) or SPRITE_BASE_SIZE
    local sprite_h = (sprite_info and sprite_info.height) or SPRITE_BASE_SIZE

    -- Escala de renderização: SPRITE_SCALE pixels por pixel do sprite (32px * 2 = 64px na tela)
    local scale = SPRITE_SCALE

    -- Estado visual e de orientação da entidade (8 direções)
    local anim_state = procedural_anim.get_state(ent.id)
    local ent_dir = anim_state.direction or "south"

    -- Sombra dos pés proporcional ao modelo de 32px ancorada na base (px, py)
    local shadow_radius_x = 13 * scale
    local shadow_radius_y = 4.5 * scale
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.ellipse("fill", px, py, shadow_radius_x, shadow_radius_y)

    -- Pivô nos pés (base central inferior: ox = 16, oy = 32 para modelos 32x32)
    local ox = sprite_w / 2
    local oy = sprite_h

    local draw_x = px
    local draw_y = py -- Posição sólida e alinhada à grade de pixels (sem bobbing procedural)

    if sprite_info then
        -- Seleciona a imagem correta: rotação 8-way do Pixelab ou imagem padrão
        local img_to_draw = (sprite_info.has_rotations and sprite_info.rotations[ent_dir]) or sprite_info.image
        if is_dead then
            love.graphics.setColor(0.5, 0.5, 0.5, 0.75)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end

        -- Para imagem única sem rotações, espelha via facing; para 8 direções do Pixelab, desenha direto sem distorção
        local scale_x = scale
        if not sprite_info.has_rotations then
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
        -- Renderizar placeholder padronizado de 32x32 com indicador de facing
        local ph = is_dead and placeholder_canvases["dead"] or 
                   (is_me and placeholder_canvases["me"] or placeholder_canvases["enemy"])
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

    -- Se morto, desenhar X de morte centrado no corpo
    if is_dead then
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

function draw_hud(sw, sh, my_entity)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 10, 10, 360, 55, 6, 6)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Loci Arena", 20, 16)
    love.graphics.setColor(0.7, 0.7, 0.85, 1)
    love.graphics.print(connection_status, 20, 34)

    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.print("WASD: Mover | Espaço: Ataque | Q: Fúria | E: Dash | R: Stun | K: Trocar | T: Touch UI | C: Ficha", 20, sh - 28)

    if rejection_timer > 0 then
        love.graphics.setColor(0.95, 0.25, 0.25, 0.95)
        love.graphics.printf(rejection_msg, 0, 80, sw, "center")
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
    local move_speed = tonumber(my_entity:get("move_speed", 3.0)) or 3.0
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
    if loci.quit then
        loci.quit()
    end
    loci.disconnect("Client exiting")
    return false
end
