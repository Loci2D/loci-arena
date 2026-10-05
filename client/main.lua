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
local GAME_WIDTH, GAME_HEIGHT = 1280, 720

-- Connection config
local SERVER_IP = os.getenv("LOCI_SERVER_IP") or "127.0.0.1"
local SERVER_PORT = tonumber(os.getenv("LOCI_SERVER_PORT")) or 8080

-- UI & State variables
local connection_status = "Connecting..."
local rejection_msg = ""
local rejection_timer = 0
local visual_fx = {}
local show_debug_overlay = false

-- Sistema de projéteis do cliente
local projectiles = {}

-- Camera state (tracked directly in world coordinates)
local cam_x, cam_y = 0, 0

-- Sistema de Respawn (cliente-side usando dt confiável do Love2D)
local RESPAWN_TIME = 10  -- Tempo em segundos para respawn
local death_time = 0  -- Timestamp quando o jogador morreu

local VISUAL_SCALE = 8 -- Pixels per Meter (escala para desenho)

-- Server authoritative arena boundaries: [-500, +500] (1000x1000 pixels)
local ARENA_MIN = -500
local ARENA_MAX = 500
local ARENA_SIZE = ARENA_MAX - ARENA_MIN

function love.load(arg)
    -- Linear filter ensures smooth sub-pixel interpolation without snapping jitter
    love.graphics.setDefaultFilter("linear", "linear")
    
    push:setupScreen(GAME_WIDTH, GAME_HEIGHT, 1280, 720, {
        fullscreen = false,
        resizable = true,
        pixelperfect = false
    })

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

    connection_status = "Connected to " .. SERVER_IP .. ":" .. SERVER_PORT .. " (" .. player_name .. ")"

    -- Event hooks
    loci.on_entity_spawned = function(entity)
        print(string.format("[Event] Entity spawned: ID %s at (%.1f, %.1f)", tostring(entity.id), entity.x, entity.y))
    end

    loci.on_entity_despawned = function(entity_id)
        print("[Event] Entity despawned: ID " .. tostring(entity_id))
    end

    loci.on_property_changed = function(entity, key, old_val, new_val)
        -- Hook for HUD/UI state updates (HP, score, buffs)
    end

    loci.on_action_cast = function(entity, ability_id, dir_x, dir_y)
        -- Efeito visual removido (não mostramos mais o raio amarelo)
    end

    loci.on_intent_rejected = function(reason)
        rejection_msg = reason
        rejection_timer = 2.5
    end
end

local last_sent_dx, last_sent_dy = 0, 0

local function update_movement()
    local my_entity = loci.get_my_entity()
    local is_dead = my_entity and (my_entity.is_dead or (my_entity.properties and my_entity.properties["is_dead"] == "true"))

    -- Se estiver morto, não enviar movimentos para o servidor
    if is_dead then
        return
    end

    local dx, dy = 0, 0
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then dy = dy - 1 end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then dy = dy + 1 end
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dx = dx - 1 end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dx = dx + 1 end

    if dx ~= last_sent_dx or dy ~= last_sent_dy then
        last_sent_dx = dx
        last_sent_dy = dy
        loci.send_move(dx, dy)
    end
end

-- Sistema de projéteis
local PROJECTILE_SPEED = 400.0      -- Velocidade em pixels/segundo
local PROJECTILE_RADIUS = 8.0 * VISUAL_SCALE  -- Raio de colisão (aumentado de 2 para 8)
local PROJECTILE_RANGE = 200.0 * VISUAL_SCALE  -- Alcance máximo

local function spawn_projectile(x, y, dir_x, dir_y, owner_id)
    table.insert(projectiles, {
        x = x,
        y = y,
        dir_x = dir_x,
        dir_y = dir_y,
        owner_id = owner_id,
        lifetime = 0,
        max_lifetime = PROJECTILE_RANGE / PROJECTILE_SPEED,
        active = true
    })
end

local function update_projectiles(dt)
    local entities = loci.get_entities()

    for i = #projectiles, 1, -1 do
        local proj = projectiles[i]
        if not proj.active then
            table.remove(projectiles, i)
            goto continue
        end

        -- Mover projétil
        proj.x = proj.x + proj.dir_x * PROJECTILE_SPEED * dt
        proj.y = proj.y + proj.dir_y * PROJECTILE_SPEED * dt
        proj.lifetime = proj.lifetime + dt

        -- Verificar se expirou
        if proj.lifetime >= proj.max_lifetime then
            table.remove(projectiles, i)
            goto continue
        end

        -- Verificar colisão com entidades
        for _, ent in ipairs(entities) do
            if ent.id ~= proj.owner_id then
                local ent_x = ent.x * VISUAL_SCALE
                local ent_y = ent.y * VISUAL_SCALE

                -- Calcular distância
                local dist = math.sqrt((proj.x - ent_x)^2 + (proj.y - ent_y)^2)

                -- Verificar colisão (raio do projétil + raio do jogador aproximado)
                local collision_threshold = PROJECTILE_RADIUS + 2.0 * VISUAL_SCALE

                if dist < collision_threshold then
                    -- Colisão detectada! Enviar para servidor
                    -- Codificar target_id no ability_id (send_action normaliza aim_x/aim_y)
                    loci.send_action(10000 + ent.id, proj.dir_x, proj.dir_y)
                    print("[Client] Projectile hit entity " .. ent.id .. " at distance " .. dist)

                    -- Remover projétil
                    table.remove(projectiles, i)
                    goto continue
                end
            end
        end

        ::continue::
    end
end

function love.update(dt)
    -- Process incoming network packets and smooth entity interpolation
    loci.update(dt)

    local my_entity = loci.get_my_entity()
    local is_dead = my_entity and (my_entity.is_dead or (my_entity.properties and my_entity.properties["is_dead"] == "true"))

    if my_entity then
        -- Se acabou de morrer, registrar o tempo
        if is_dead and death_time == 0 then
            death_time = love.timer.getTime()
        end

        -- Se estiver morto, verificar respawn
        if is_dead then
            -- Verificar se passou o tempo de respawn
            local time_since_death = love.timer.getTime() - death_time
            if time_since_death >= RESPAWN_TIME then
                -- Solicitar respawn ao servidor
                loci.send_action(1, 0, 0)  -- Enviar ação de respawn (ability_id 1)
                print("[Client] Requesting respawn after " .. time_since_death .. " seconds")
            end
        else
            -- Resetar death_time se reviveu
            death_time = 0
            -- Se estiver vivo, enviar movimentos e trancar câmera no jogador
            update_movement()
            -- Direct camera binding eliminates lag jitter between camera and player
            cam_x = my_entity.x * VISUAL_SCALE
            cam_y = my_entity.y * VISUAL_SCALE
        end
    end

    -- Update rejection message timer
    if rejection_timer > 0 then
        rejection_timer = rejection_timer - dt
    end

    -- Update visual effects
    for i = #visual_fx, 1, -1 do
        visual_fx[i].lifetime = visual_fx[i].lifetime - dt
        if visual_fx[i].lifetime <= 0 then
            table.remove(visual_fx, i)
        end
    end

    -- Update projectiles
    update_projectiles(dt)
end

function love.resize(w, h)
    push:resize(w, h)
end

function love.keypressed(key)
    if key == "f3" then
        show_debug_overlay = not show_debug_overlay
    elseif key == "tab" then
        kda_ui.show()
    elseif key == "space" then
        -- Verificar se o jogador está morto
        local me = loci.get_my_entity()
        local is_dead = me and (me.is_dead or (me.properties and me.properties["is_dead"] == "true"))
        if is_dead then
            print("[Client] Cannot shoot - you are dead!")
            return
        end

        -- Primary action intent directed toward mouse cursor
        local mx, my = push:toGame(love.mouse.getPosition())
        if not mx then return end

        local sw, sh = GAME_WIDTH, GAME_HEIGHT
        local world_target_x = (mx - sw / 2) + cam_x
        local world_target_y = (my - sh / 2) + cam_y

        local origin_x = me and (me.x * VISUAL_SCALE) or cam_x
        local origin_y = me and (me.y * VISUAL_SCALE) or cam_y
        local dir_x = world_target_x - origin_x
        local dir_y = world_target_y - origin_y
        local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
        if len > 0 then
            dir_x, dir_y = dir_x / len, dir_y / len
        else
            dir_x, dir_y = 1, 0
        end

        -- Spawnar projétil (ele se move e verifica colisão frame a frame)
        spawn_projectile(origin_x, origin_y, dir_x, dir_y, me and me.id)
        print("[Client] Projectile spawned at (" .. origin_x .. ", " .. origin_y .. ") direction (" .. dir_x .. ", " .. dir_y .. ")")
    end
end

function love.keyreleased(key)
    if key == "tab" then
        kda_ui.hide()
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
    love.graphics.translate(-cam_x, -cam_y)

    -- Draw background grid & physical collision boundaries
    draw_arena_grid()

    -- Draw transient visual effects
    for _, fx in ipairs(visual_fx) do
        local progress = fx.lifetime / fx.max_lifetime
        love.graphics.setColor(1, 0.85, 0.2, progress)
        local fx_start_x = fx.x * VISUAL_SCALE
        local fx_start_y = fx.y * VISUAL_SCALE
        local fx_end_x = fx_start_x + fx.dir_x * 50 * VISUAL_SCALE
        local fx_end_y = fx_start_y + fx.dir_y * 50 * VISUAL_SCALE
        love.graphics.line(fx_start_x, fx_start_y, fx_end_x, fx_end_y)
        love.graphics.circle("fill", fx_end_x, fx_end_y, 5 * progress)
    end

    -- Draw projectiles
    love.graphics.setColor(1, 0.5, 0.2, 1)
    for _, proj in ipairs(projectiles) do
        love.graphics.circle("fill", proj.x, proj.y, 3)
    end

    -- Draw all network entities
    local my_entity = loci.get_my_entity()
    local entities = loci.get_entities()
    for _, ent in ipairs(entities) do
        draw_entity(ent, my_entity and (ent.id == my_entity.id))
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
    local hp = tonumber(ent.hp or (ent.properties and ent.properties["hp"]) or 100) or 100

    if is_me then
        if is_dead then
            love.graphics.setColor(0.3, 0.3, 0.3, 1)  -- Cinza escuro quando morto
        else
            love.graphics.setColor(0.2, 0.6, 1.0, 1)
        end
    else
        if is_dead then
            love.graphics.setColor(0.4, 0.2, 0.2, 1)  -- Vermelho escuro quando morto
        else
            love.graphics.setColor(0.9, 0.3, 0.3, 1)
        end
    end

    love.graphics.circle("fill", px, py, radius)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", px, py, radius)

    -- Se morto, desenhar X sobre o jogador
    if is_dead then
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.line(px - radius/2, py - radius/2, px + radius/2, py + radius/2)
        love.graphics.line(px + radius/2, py - radius/2, px - radius/2, py + radius/2)
    end

    -- HP Bar
    local max_hp = tonumber(ent.max_hp or (ent.properties and ent.properties["max_hp"]) or 100) or 100
    local bar_w = 44
    local bar_h = 5
    local bar_x = px - bar_w / 2
    local bar_y = py - radius - 14

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
    love.graphics.setColor(0.2, 0.9, 0.3, 1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w * (math.max(0, math.min(1, hp / max_hp))), bar_h)

    -- Player label
    love.graphics.setColor(1, 1, 1, 0.95)
    local label = is_me and "YOU" or ("P" .. tostring(ent.id))
    if is_dead then
        label = label .. " (DEAD)"
    end
    local font = love.graphics.getFont()
    local tw = font:getWidth(label)
    love.graphics.print(label, px - tw / 2, py - 7)
end

function draw_hud(sw, sh, my_entity)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 10, 10, 360, 55, 6, 6)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Loci Arena", 20, 16)
    love.graphics.setColor(0.7, 0.7, 0.85, 1)
    love.graphics.print(connection_status, 20, 34)

    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.print("WASD: Move  |  Space: Action  |  F3: Debug", 20, sh - 28)

    if rejection_timer > 0 then
        love.graphics.setColor(0.95, 0.25, 0.25, 0.95)
        love.graphics.printf(rejection_msg, 0, 80, sw, "center")
    end
end

function draw_debug(sw, sh)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", sw - 240, 10, 230, 120, 6, 6)

    local ent_count = #loci.get_entities()
    local me = loci.get_my_entity()
    local tick_rate = loci.get_server_tick_rate and loci.get_server_tick_rate() or 30

    love.graphics.setColor(0.4, 1.0, 0.5, 1)
    love.graphics.print(string.format("FPS: %d", love.timer.getFPS()), sw - 225, 20)
    love.graphics.print(string.format("Sequence: %d", loci._sequence_id or 0), sw - 225, 40)
    love.graphics.print(string.format("Entities: %d", ent_count), sw - 225, 60)
    love.graphics.print(string.format("Tick Rate: %d Hz", tick_rate), sw - 225, 80)
    if me then
        love.graphics.print(string.format("Pos: (%.1f, %.1f)", me.x, me.y), sw - 225, 100)
    end
end

function love.quit()
    print("[Client] Closing connection...")
    loci.disconnect("Client exiting")
end
