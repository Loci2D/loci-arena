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

-- Connection config
local SERVER_IP = os.getenv("LOCI_SERVER_IP") or "127.0.0.1"
local SERVER_PORT = tonumber(os.getenv("LOCI_SERVER_PORT")) or 8080

-- World scale: Simulation units (meters) to screen pixels
local WORLD_SCALE = 16.0

-- UI & State variables
local connection_status = "Connecting..."
local rejection_msg = ""
local rejection_timer = 0
local visual_fx = {}
local show_debug_overlay = false

-- Camera state (tracked directly in world coordinates)
local cam_x, cam_y = 0, 0

function love.load(arg)
    -- Linear filter allows smooth sub-pixel movement without pixel snapping jitter
    love.graphics.setDefaultFilter("linear", "linear")
    
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
        table.insert(visual_fx, {
            x = entity and entity.x or 0,
            y = entity and entity.y or 0,
            dir_x = dir_x,
            dir_y = dir_y,
            ability_id = ability_id,
            lifetime = 0.35,
            max_lifetime = 0.35
        })
    end

    loci.on_intent_rejected = function(reason)
        rejection_msg = reason
        rejection_timer = 2.5
    end
end

local last_sent_dx, last_sent_dy = 0, 0

local function update_movement()
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

function love.update(dt)
    -- Process incoming network packets and internal entity lerp
    loci.update(dt)
    
    local my_entity = loci.get_my_entity()
    if my_entity then
        update_movement()
        -- Lock camera directly to local player to eliminate asynchronous lerp jitter
        cam_x = my_entity.x
        cam_y = my_entity.y
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
end

function love.keypressed(key)
    if key == "f3" then
        show_debug_overlay = not show_debug_overlay
    elseif key == "space" then
        -- Primary action intent
        local mx, my = love.mouse.getPosition()
        local sw, sh = love.graphics.getDimensions()
        local world_target_x = (mx - sw / 2) / WORLD_SCALE + cam_x
        local world_target_y = (my - sh / 2) / WORLD_SCALE + cam_y
        
        local me = loci.get_my_entity()
        local origin_x = me and me.x or cam_x
        local origin_y = me and me.y or cam_y
        local dir_x = world_target_x - origin_x
        local dir_y = world_target_y - origin_y
        local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
        if len > 0 then
            dir_x, dir_y = dir_x / len, dir_y / len
        else
            dir_x, dir_y = 1, 0
        end

        loci.send_action(1, dir_x, dir_y)
    end
end

function love.draw()
    local sw, sh = love.graphics.getDimensions()
    local center_x = sw / 2
    local center_y = sh / 2

    -- 1. Arena World Rendering
    love.graphics.push()
    love.graphics.translate(center_x, center_y)
    love.graphics.translate(-cam_x * WORLD_SCALE, -cam_y * WORLD_SCALE)

    -- Draw background grid
    draw_arena_grid()

    -- Draw transient visual effects
    for _, fx in ipairs(visual_fx) do
        local progress = fx.lifetime / fx.max_lifetime
        love.graphics.setColor(1, 0.85, 0.2, progress)
        local fx_start_x = fx.x * WORLD_SCALE
        local fx_start_y = fx.y * WORLD_SCALE
        local fx_end_x = fx_start_x + fx.dir_x * 50
        local fx_end_y = fx_start_y + fx.dir_y * 50
        love.graphics.line(fx_start_x, fx_start_y, fx_end_x, fx_end_y)
        love.graphics.circle("fill", fx_end_x, fx_end_y, 5 * progress)
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

    -- 3. Debug Overlay
    if show_debug_overlay then
        draw_debug(sw, sh)
    end
end

function draw_arena_grid()
    -- Arena floor boundary
    love.graphics.setColor(0.10, 0.12, 0.16, 1)
    love.graphics.rectangle("fill", -100 * WORLD_SCALE, -100 * WORLD_SCALE, 200 * WORLD_SCALE, 200 * WORLD_SCALE)

    -- Playable arena borders (-35 to +35 meters)
    love.graphics.setColor(0.2, 0.25, 0.35, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", -35 * WORLD_SCALE, -35 * WORLD_SCALE, 70 * WORLD_SCALE, 70 * WORLD_SCALE)

    -- Grid lines every 5 meters
    love.graphics.setColor(0.18, 0.22, 0.30, 0.4)
    love.graphics.setLineWidth(1)
    for x = -35 * WORLD_SCALE, 35 * WORLD_SCALE, 5 * WORLD_SCALE do
        love.graphics.line(x, -35 * WORLD_SCALE, x, 35 * WORLD_SCALE)
    end
    for y = -35 * WORLD_SCALE, 35 * WORLD_SCALE, 5 * WORLD_SCALE do
        love.graphics.line(-35 * WORLD_SCALE, y, 35 * WORLD_SCALE, y)
    end

    -- Origin crosshair
    love.graphics.setColor(0.3, 0.4, 0.5, 0.6)
    love.graphics.line(-15, 0, 15, 0)
    love.graphics.line(0, -15, 0, 15)
end

function draw_entity(ent, is_me)
    local radius = 16
    local px = ent.x * WORLD_SCALE
    local py = ent.y * WORLD_SCALE

    if is_me then
        love.graphics.setColor(0.2, 0.6, 1.0, 1)
    else
        love.graphics.setColor(0.9, 0.3, 0.3, 1)
    end

    love.graphics.circle("fill", px, py, radius)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", px, py, radius)

    -- HP Bar
    local hp = tonumber(ent.hp or (ent.properties and ent.properties["hp"]) or 100) or 100
    local max_hp = tonumber(ent.max_hp or (ent.properties and ent.properties["max_hp"]) or 100) or 100
    local bar_w = 40
    local bar_h = 5
    local bar_x = px - bar_w / 2
    local bar_y = py - radius - 12

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
    love.graphics.setColor(0.2, 0.9, 0.3, 1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w * (math.max(0, math.min(1, hp / max_hp))), bar_h)

    -- Player label
    love.graphics.setColor(1, 1, 1, 0.9)
    local label = is_me and "YOU" or ("P" .. tostring(ent.id))
    local font = love.graphics.getFont()
    local tw = font:getWidth(label)
    love.graphics.print(label, px - tw / 2, py - 7)
end

function draw_hud(sw, sh, my_entity)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 10, 10, 360, 55, 6, 6)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Loci Arena", 20, 16)
    love.graphics.setColor(0.7, 0.7, 0.8, 1)
    love.graphics.print(connection_status, 20, 34)

    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.print("WASD: Move  |  Space: Action  |  F3: Debug", 20, sh - 28)

    if rejection_timer > 0 then
        love.graphics.setColor(0.9, 0.2, 0.2, 0.9)
        love.graphics.printf(rejection_msg, 0, 80, sw, "center")
    end
end

function draw_debug(sw, sh)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", sw - 220, 10, 210, 80, 6, 6)

    local ent_count = #loci.get_entities()

    love.graphics.setColor(0.4, 1.0, 0.5, 1)
    love.graphics.print(string.format("FPS: %d", love.timer.getFPS()), sw - 205, 20)
    love.graphics.print(string.format("Sequence: %d", loci._sequence_id or 0), sw - 205, 40)
    love.graphics.print(string.format("Entities: %d", ent_count), sw - 205, 60)
end

function love.quit()
    print("[Client] Closing connection...")
    loci.disconnect("Client exiting")
end
