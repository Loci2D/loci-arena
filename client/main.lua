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
local show_character_sheet = false

-- Screen shake variables
local shake_intensity = 0
local shake_duration = 0
local shake_offset_x = 0
local shake_offset_y = 0

-- Camera state (tracked directly in world coordinates)
local cam_x, cam_y = 0, 0

local VISUAL_SCALE = 2 -- Pixels per unit: arena 1000x1000 -> ~650x650 pixels on screen

-- Server authoritative arena boundaries: [-500, +500] (1000x1000 pixels)
local ARENA_MIN = -500
local ARENA_MAX = 500
local ARENA_SIZE = ARENA_MAX - ARENA_MIN

-- Função para acionar screen shake (definida antes de love.load)
local function trigger_screen_shake(intensity, duration)
    shake_intensity = intensity
    shake_duration = duration
end

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
        -- Detect HP decrease for screen shake feedback
        if key == "hp" then
            local old_hp = tonumber(old_val) or 0
            local new_hp = tonumber(new_val) or 0
            local damage = old_hp - new_hp

            -- Trigger screen shake on significant damage (> 10)
            if damage > 10 then
                trigger_screen_shake(math.min(damage / 100, 1.0) * 8, 0.2)
            end
        end
    end

    loci.on_action_cast = function(entity, ability_id, dir_x, dir_y)
        local ox = entity and entity.x or 0
        local oy = entity and entity.y or 0

        if ability_id == 3 then
            -- Fireball: spawn projectile trail + explosion at impact
            local FIREBALL_SPEED = 320 -- units/sec in screen space
            local FIREBALL_LIFETIME = 0.55
            local FIREBALL_RANGE = 200  -- world units

            -- Read skill data range from server (approx): range 300 * 0.7 = 210 world units
            local impact_x = ox + dir_x * 210
            local impact_y = oy + dir_y * 210

            table.insert(visual_fx, {
                kind       = "fireball",
                x          = ox, y = oy,
                dir_x      = dir_x, dir_y = dir_y,
                impact_x   = impact_x, impact_y = impact_y,
                lifetime   = FIREBALL_LIFETIME,
                max_lifetime = FIREBALL_LIFETIME,
                trail      = {},   -- will be filled each frame
                exploded   = false,
            })
        else
            -- Generic flash for other abilities
            table.insert(visual_fx, {
                kind = "flash",
                x = ox, y = oy,
                dir_x = dir_x, dir_y = dir_y,
                ability_id = ability_id,
                lifetime = 0.35,
                max_lifetime = 0.35
            })
        end
    end

    loci.on_intent_rejected = function(reason)
        rejection_msg = reason
        rejection_timer = 2.5
    end
end

local last_sent_dx, last_sent_dy = 1, 0  -- Começa olhando para direita
local last_nonzero_dx, last_nonzero_dy = 1, 0  -- Mantém última direção de movimento não-zero

-- Sistema de Dash - detecção de double-tap
local last_key_time = {}
local DASH_DOUBLE_TAP_TIME = 0.3  -- segundos entre presses para detectar double-tap
local DASH_COOLDOWN = 0.5  -- segundos entre dashes
local last_dash_time = 0

-- Função para obter direção de ataque com auto-targeting
local function get_attack_direction()
    local my_entity = loci.get_my_entity()
    if not my_entity then
        return 0, -1  -- Default: aiming up
    end

    -- Buscar inimigo mais próximo num raio
    local my_team = my_entity.team or "unknown"
    local all_entities = loci.get_entities()
    local nearest_enemy = nil
    local nearest_dist = math.huge
    local SEARCH_RADIUS = 400  -- Raio de busca de inimigos

    if all_entities then
        for _, ent in ipairs(all_entities) do
            -- Ignorar a si mesmo
            if ent.id ~= my_entity.id then
                -- Verificar se é inimigo (team diferente)
                local ent_team = ent.team or "unknown"
                if ent_team ~= my_team then
                    -- Verificar se está morto
                    local is_dead = ent.is_dead or (ent.properties and ent.properties["is_dead"] == "true")
                    if not is_dead then
                        -- Calcular distância
                        local dx = ent.x - my_entity.x
                        local dy = ent.y - my_entity.y
                        local dist = math.sqrt(dx * dx + dy * dy)

                        -- Se estiver no raio e for o mais próximo
                        if dist < SEARCH_RADIUS and dist < nearest_dist then
                            nearest_dist = dist
                            nearest_enemy = ent
                        end
                    end
                end
            end
        end
    end

    -- Se encontrou inimigo próximo, calcular direção para ele
    if nearest_enemy then
        local dx = nearest_enemy.x - my_entity.x
        local dy = nearest_enemy.y - my_entity.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            return dx / len, dy / len
        end
    end

    -- Fallback: usar última direção de movimento não-zero, ou aponta para cima
    if not last_nonzero_dx or not last_nonzero_dy then
        return 0, -1
    end
    return last_nonzero_dx, last_nonzero_dy
end

local function update_movement()
    local dx, dy = 0, 0
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then dy = dy - 1 end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then dy = dy + 1 end
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dx = dx - 1 end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dx = dx + 1 end

    -- Normalizar direção para permitir movimento diagonal
    if dx ~= 0 or dy ~= 0 then
        local len = math.sqrt(dx * dx + dy * dy)
        dx = dx / len
        dy = dy / len
        -- Atualizar última direção não-zero
        last_nonzero_dx = dx
        last_nonzero_dy = dy
    end

    last_sent_dx = dx
    last_sent_dy = dy
    loci.send_move(dx, dy)
end

function love.update(dt)
    -- Process incoming network packets and smooth entity interpolation
    loci.update(dt)

    local my_entity = loci.get_my_entity()
    if my_entity then
        update_movement()
        -- Direct camera binding eliminates lag jitter between camera and player
        cam_x = my_entity.x * VISUAL_SCALE
        cam_y = my_entity.y * VISUAL_SCALE
    end

    -- Update rejection message timer
    if rejection_timer > 0 then
        rejection_timer = rejection_timer - dt
    end

    -- Update screen shake
    if shake_duration > 0 then
        shake_duration = shake_duration - dt
        -- Calculate random shake offset based on intensity
        shake_offset_x = (math.random() - 0.5) * 2 * shake_intensity
        shake_offset_y = (math.random() - 0.5) * 2 * shake_intensity
        -- Amortecimento: intensidade diminui com o tempo
        shake_intensity = shake_intensity * 0.9
    else
        shake_offset_x = 0
        shake_offset_y = 0
        shake_intensity = 0
    end

    -- Update visual effects
    for i = #visual_fx, 1, -1 do
        local fx = visual_fx[i]
        fx.lifetime = fx.lifetime - dt

        -- Fireball: accumulate trail particles and check local collision
        if fx.kind == "fireball" and not fx.exploded then
            local progress = fx.lifetime / fx.max_lifetime  -- 1..0
            local travel = 1.0 - progress  -- 0..1
            local cur_x = fx.x + (fx.impact_x - fx.x) * travel
            local cur_y = fx.y + (fx.impact_y - fx.y) * travel

            -- Verificar colisão local com paredes da arena
            local ARENA_MIN = -500
            local ARENA_MAX = 500
            if cur_x < ARENA_MIN or cur_x > ARENA_MAX or cur_y < ARENA_MIN or cur_y > ARENA_MAX then
                -- Explodir na parede
                fx.impact_x = math.max(ARENA_MIN, math.min(ARENA_MAX, cur_x))
                fx.impact_y = math.max(ARENA_MIN, math.min(ARENA_MAX, cur_y))
                fx.exploded = true
                fx.lifetime = 0
            end

            -- Verificar colisão local com obstáculos e players
            local all_entities = loci.get_entities()
            if all_entities then
                for _, ent in ipairs(all_entities) do
                    -- Ignorar o caster (my_entity)
                    if ent.id ~= (my_entity and my_entity.id) then
                        local ent_radius = tonumber(ent.radius or 20)
                        local dx = cur_x - ent.x
                        local dy = cur_y - ent.y
                        local dist = math.sqrt(dx * dx + dy * dy)

                        -- Se colidiu (projétil radius ~8 + entidade radius)
                        if dist < (8 + ent_radius) then
                            -- Explodir no ponto de colisão
                            fx.impact_x = cur_x
                            fx.impact_y = cur_y
                            fx.exploded = true
                            fx.lifetime = 0  -- Explodir imediatamente
                            break
                        end
                    end
                end
            end

            -- add trail point every frame
            table.insert(fx.trail, { x = cur_x, y = cur_y, age = 0 })
        end

        -- Age trail points
        if fx.kind == "fireball" then
            for j = #fx.trail, 1, -1 do
                fx.trail[j].age = fx.trail[j].age + dt
                if fx.trail[j].age > 0.3 then
                    table.remove(fx.trail, j)
                end
            end
        end

        if fx.lifetime <= 0 then
            -- Fireball dies → spawn explosion
            if fx.kind == "fireball" and not fx.exploded then
                table.insert(visual_fx, {
                    kind = "explosion",
                    x = fx.impact_x, y = fx.impact_y,
                    lifetime = 0.45,
                    max_lifetime = 0.45,
                })
            end
            table.remove(visual_fx, i)
        end
    end
end

function love.resize(w, h)
    push:resize(w, h)
end

function love.keypressed(key)
    -- Só processar double-tap para teclas de movimento
    local is_movement_key = (key == "w" or key == "a" or key == "s" or key == "d" or
                              key == "up" or key == "left" or key == "down" or key == "right")
    
    if is_movement_key then
        -- Sistema de Dash - detecta double-tap
        local current_time = love.timer.getTime()
        local last_time = last_key_time[key] or 0
        
        if current_time - last_time < DASH_DOUBLE_TAP_TIME and current_time - last_dash_time > DASH_COOLDOWN then
            -- Double-tap detectado - executar dash
            local my_entity = loci.get_my_entity()
            if my_entity then
                local dir_x, dir_y = 0, 0
                
                -- Se o player está se movendo, usa direção ATUAL de movimento
                if last_sent_dx ~= 0 or last_sent_dy ~= 0 then
                    dir_x = last_sent_dx
                    dir_y = last_sent_dy
                else
                    -- Se parado, usa a ÚLTIMA direção de movimento não-zero
                    dir_x = last_nonzero_dx
                    dir_y = last_nonzero_dy
                end
                
                -- Normalizar direção
                if dir_x ~= 0 or dir_y ~= 0 then
                    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
                    dir_x = dir_x / len
                    dir_y = dir_y / len
                end
                
                -- Enviar ação de dash (ability 2)
                loci.send_action_direct(2, dir_x, dir_y)
                
                last_dash_time = current_time
            end
        end
        
        last_key_time[key] = current_time
    end

    if key == "f3" then
        show_debug_overlay = not show_debug_overlay
    elseif key == "c" then
        show_character_sheet = not show_character_sheet
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

        -- Auto-targeting para ataque básico (ability 1)
        local my_entity = loci.get_my_entity()
        if my_entity then
            local dir_x, dir_y = get_attack_direction()
            loci.send_action_direct(1, dir_x, dir_y)
        end
    elseif key == "q" then
        -- Skill slot 3 (fireball)
        local me = loci.get_my_entity()
        local is_dead = me and (me.is_dead or (me.properties and me.properties["is_dead"] == "true"))
        if is_dead then
            print("[Client] Cannot cast fireball - you are dead!")
            return
        end

        local my_entity = loci.get_my_entity()
        if my_entity then
            local dir_x, dir_y = get_attack_direction()
            loci.send_action_direct(3, dir_x, dir_y)
        end
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
    love.graphics.translate(-cam_x + shake_offset_x, -cam_y + shake_offset_y)

    -- Draw background grid & physical collision boundaries
    draw_arena_grid()

    -- Draw transient visual effects
    for _, fx in ipairs(visual_fx) do
        local progress = fx.lifetime / fx.max_lifetime  -- 1.0 = fresh, 0.0 = expired

        if fx.kind == "fireball" then
            draw_fireball_fx(fx, progress)
        elseif fx.kind == "explosion" then
            draw_explosion_fx(fx, progress)
        else
            -- Generic flash
            local alpha = progress
            love.graphics.setColor(1, 0.85, 0.2, alpha)
            local fx_sx = fx.x * VISUAL_SCALE
            local fx_sy = fx.y * VISUAL_SCALE
            local fx_ex = fx_sx + fx.dir_x * 50 * VISUAL_SCALE
            local fx_ey = fx_sy + fx.dir_y * 50 * VISUAL_SCALE
            love.graphics.setLineWidth(2)
            love.graphics.line(fx_sx, fx_sy, fx_ex, fx_ey)
            love.graphics.circle("fill", fx_ex, fx_ey, 5 * progress)
        end
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

    -- 4. Character Sheet Overlay (C)
    if show_character_sheet then
        draw_character_sheet(sw, sh, my_entity)
    end

    push:finish()
end

-- =====================================================================
-- Fireball VFX helpers
-- =====================================================================

function draw_fireball_fx(fx, progress)
    local VS = VISUAL_SCALE
    local travel = 1.0 - progress
    local cur_x = (fx.x + (fx.impact_x - fx.x) * travel) * VS
    local cur_y = (fx.y + (fx.impact_y - fx.y) * travel) * VS

    -- 1) Trail: fading ember dots
    for _, pt in ipairs(fx.trail) do
        local trail_alpha = math.max(0, 1.0 - pt.age / 0.3)
        local trail_r = 4 * trail_alpha
        -- Outer ember glow (orange-red)
        love.graphics.setColor(1.0, 0.35 + 0.3 * trail_alpha, 0.0, trail_alpha * 0.55)
        love.graphics.circle("fill", pt.x * VS, pt.y * VS, trail_r * 2.5)
        -- Core ember (bright yellow)
        love.graphics.setColor(1.0, 0.95, 0.5, trail_alpha * 0.9)
        love.graphics.circle("fill", pt.x * VS, pt.y * VS, trail_r)
    end

    -- 2) Smoke wisp (grey, slightly behind)
    for j, pt in ipairs(fx.trail) do
        if j % 4 == 0 then
            local smoke_alpha = math.max(0, (1.0 - pt.age / 0.3) * 0.25)
            local smoke_r = 8 * (pt.age / 0.3 + 0.2)
            love.graphics.setColor(0.6, 0.55, 0.5, smoke_alpha)
            love.graphics.circle("fill", pt.x * VS - fx.dir_x * 5, pt.y * VS - fx.dir_y * 5, smoke_r)
        end
    end

    -- 3) Outer glow halo
    love.graphics.setColor(1.0, 0.4, 0.0, 0.18)
    love.graphics.circle("fill", cur_x, cur_y, 22)
    love.graphics.setColor(1.0, 0.65, 0.1, 0.28)
    love.graphics.circle("fill", cur_x, cur_y, 14)

    -- 4) Fireball body (layered circles for depth)
    -- Outer flame ring (orange)
    love.graphics.setColor(1.0, 0.45, 0.0, 0.85)
    love.graphics.circle("fill", cur_x, cur_y, 10)
    -- Mid flame (yellow-orange)
    love.graphics.setColor(1.0, 0.78, 0.15, 0.92)
    love.graphics.circle("fill", cur_x, cur_y, 7)
    -- Inner core (white-yellow)
    love.graphics.setColor(1.0, 0.98, 0.75, 1.0)
    love.graphics.circle("fill", cur_x, cur_y, 3.5)

    -- 5) Spark lines radiating outward from core
    local t = love.timer.getTime()
    local num_sparks = 6
    for s = 1, num_sparks do
        local base_angle = (s / num_sparks) * math.pi * 2 + t * 12
        local spark_len = 8 + 5 * math.sin(t * 20 + s * 1.3)
        local sx2 = cur_x + math.cos(base_angle) * spark_len
        local sy2 = cur_y + math.sin(base_angle) * spark_len
        love.graphics.setColor(1.0, 0.85, 0.2, 0.7)
        love.graphics.setLineWidth(1.5)
        love.graphics.line(cur_x, cur_y, sx2, sy2)
    end

    love.graphics.setLineWidth(1)
end

function draw_explosion_fx(fx, progress)
    -- progress 1→0 as explosion fades
    local VS = VISUAL_SCALE
    local ex = fx.x * VS
    local ey = fx.y * VS
    local ease = 1.0 - progress  -- 0=start, 1=end
    local blast_r = ease * 55    -- expanding ring

    -- Shockwave ring
    local ring_alpha = progress * 0.9
    love.graphics.setColor(1.0, 0.55, 0.05, ring_alpha * 0.4)
    love.graphics.setLineWidth(4 * progress)
    love.graphics.circle("line", ex, ey, blast_r)
    love.graphics.setColor(1.0, 0.9, 0.5, ring_alpha * 0.25)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", ex, ey, blast_r * 0.65)

    -- Inner fireball expand-then-fade
    local body_r = (ease < 0.4) and (ease / 0.4 * 22) or (22 * (1.0 - (ease - 0.4) / 0.6))
    if body_r > 0 then
        love.graphics.setColor(1.0, 0.38, 0.0, progress * 0.75)
        love.graphics.circle("fill", ex, ey, body_r)
        love.graphics.setColor(1.0, 0.75, 0.2, progress * 0.9)
        love.graphics.circle("fill", ex, ey, body_r * 0.6)
        love.graphics.setColor(1.0, 0.97, 0.8, progress)
        love.graphics.circle("fill", ex, ey, body_r * 0.28)
    end

    -- Debris sparks flying outward
    local t = love.timer.getTime()
    local num_debris = 10
    for d = 1, num_debris do
        local angle = (d / num_debris) * math.pi * 2 + d * 0.7
        local dist = ease * (30 + d * 5)
        local dx2 = ex + math.cos(angle) * dist
        local dy2 = ey + math.sin(angle) * dist
        local spark_alpha = progress * (1 - ease * 0.5)
        love.graphics.setColor(1.0, 0.7 - d * 0.05, 0.1, spark_alpha)
        love.graphics.circle("fill", dx2, dy2, 2.5 * progress)
    end

    love.graphics.setLineWidth(1)
end

-- =====================================================================

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

    -- Interior grid lines every 100 world units (= 65 screen pixels at scale 0.65)
    local grid_step = 100 * VISUAL_SCALE
    love.graphics.setColor(0.18, 0.22, 0.32, 0.35)
    love.graphics.setLineWidth(1)
    for gx = v_min, v_max, grid_step do
        love.graphics.line(gx, v_min, gx, v_max)
    end
    for gy = v_min, v_max, grid_step do
        love.graphics.line(v_min, gy, v_max, gy)
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
    -- Render obstacles differently
    if ent.blueprint == "Obstacle" or ent.blueprint == "obstacle" then
        local px = ent.x * VISUAL_SCALE
        local py = ent.y * VISUAL_SCALE
        local radius = tonumber(ent.radius or 20) * VISUAL_SCALE

        -- Obstacle: stone block look
        love.graphics.setColor(0.25, 0.28, 0.35, 1.0)
        love.graphics.circle("fill", px, py, radius)
        -- Rim highlight
        love.graphics.setColor(0.42, 0.48, 0.58, 0.9)
        love.graphics.setLineWidth(2.5)
        love.graphics.circle("line", px, py, radius)
        -- Inner texture cross
        love.graphics.setColor(0.18, 0.20, 0.26, 0.7)
        love.graphics.setLineWidth(1)
        love.graphics.line(px - radius * 0.5, py, px + radius * 0.5, py)
        love.graphics.line(px, py - radius * 0.5, px, py + radius * 0.5)
        return
    end

    local radius = 10 * VISUAL_SCALE
    local px = ent.x * VISUAL_SCALE
    local py = ent.y * VISUAL_SCALE

    -- Verificar se está morto
    local is_dead = ent.is_dead or (ent.properties and ent.properties["is_dead"] == "true")

    if is_me then
        if is_dead then
            love.graphics.setColor(0.3, 0.3, 0.3, 1)  -- Cinza escuro
        else
            love.graphics.setColor(0.2, 0.6, 1.0, 1)
        end
    else
        if is_dead then
            love.graphics.setColor(0.4, 0.2, 0.2, 1)  -- Vermelho escuro
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
    local hp = tonumber(ent.hp or (ent.properties and ent.properties["hp"]) or 100) or 100
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
    love.graphics.print("WASD: Move  |  Space: Attack  |  Double-tap WASD: Dash  |  C: Atributos  |  F3: Debug", 20, sh - 28)

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
    loci.disconnect("Client exiting")
end
