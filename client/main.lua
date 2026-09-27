-- Loci Arena - Love2D Client
-- Entrypoint for the game client connecting to the authoritative loci2d server.

-- Setup search paths for the local loci2d SDK
package.path = package.path .. ";./loci2d/?.lua;./loci2d/lib/?.lua;./src/?.lua;./?.lua"
package.cpath = package.cpath .. ";./loci2d/lib/?.so;./loci2d/?.so;./?.so"

local loci = require("loci_client")

-- Connection config
local SERVER_IP = os.getenv("LOCI_SERVER_IP") or "127.0.0.1"
local SERVER_PORT = tonumber(os.getenv("LOCI_SERVER_PORT")) or 8080

-- UI & State variables
local connection_status = "Connecting..."
local rejection_msg = ""
local rejection_timer = 0
local visual_fx = {}
local show_debug_overlay = false

-- Camera state
local cam_x, cam_y = 0, 0
local cam_scale = 1.0

function love.load(arg)
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    print("[Client] Initializing Loci Arena client...")
    local ok, err = loci.init(SERVER_IP, SERVER_PORT, false)
    if not ok then
        connection_status = "Connection error: " .. tostring(err)
        print("[Client] Failed to initialize connection:", err)
        return
    end

    connection_status = "Connected to " .. SERVER_IP .. ":" .. SERVER_PORT

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
            lifetime = 0.3,
            max_lifetime = 0.3
        })
    end

    loci.on_intent_rejected = function(reason)
        rejection_msg = reason
        rejection_timer = 2.5
    end
end

local last_move_x, last_move_y = 0, 0

local function process_input()
    local dx, dy = 0, 0
    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then dy = dy - 1 end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down") then dy = dy + 1 end
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then dx = dx - 1 end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dx = dx + 1 end

    if dx ~= last_move_x or dy ~= last_move_y then
        last_move_x, last_move_y = dx, dy
        loci.send_move(dx, dy)
    end
end

function love.update(dt)
    loci.update(dt)
    process_input()

    -- Update rejection message timer
    if rejection_timer > 0 then
        rejection_timer = rejection_timer - dt
    end

    -- Update particle / visual effects
    for i = #visual_fx, 1, -1 do
        visual_fx[i].lifetime = visual_fx[i].lifetime - dt
        if visual_fx[i].lifetime <= 0 then
            table.remove(visual_fx, i)
        end
    end

    -- Camera smoothly tracks the local player
    local me = loci.get_my_entity()
    if me then
        cam_x = cam_x + (me.x - cam_x) * math.min(1, dt * 10)
        cam_y = cam_y + (me.y - cam_y) * math.min(1, dt * 10)
    end
end

function love.keypressed(key)
    if key == "f3" then
        show_debug_overlay = not show_debug_overlay
    elseif key == "space" then
        -- Primary action intent
        local mx, my = love.mouse.getPosition()
        local sw, sh = love.graphics.getDimensions()
        local world_target_x = (mx - sw / 2) / cam_scale + cam_x
        local world_target_y = (my - sh / 2) / cam_scale + cam_y
        
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

    -- 1. Arena World Rendering
    love.graphics.push()
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(cam_scale, cam_scale)
    love.graphics.translate(-cam_x, -cam_y)

    -- Draw background grid
    draw_arena_grid()

    -- Draw visual fx
    for _, fx in ipairs(visual_fx) do
        local progress = fx.lifetime / fx.max_lifetime
        love.graphics.setColor(1, 0.8, 0.2, progress)
        love.graphics.line(fx.x, fx.y, fx.x + fx.dir_x * 50, fx.y + fx.dir_y * 50)
        love.graphics.circle("fill", fx.x + fx.dir_x * 50, fx.y + fx.dir_y * 50, 6 * progress)
    end

    -- Draw all network entities
    local my_entity = loci.get_my_entity()
    local entities = loci.get_entities()
    for id, ent in pairs(entities) do
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
    love.graphics.setColor(0.15, 0.17, 0.22, 1)
    love.graphics.rectangle("fill", -1000, -1000, 2000, 2000)

    love.graphics.setColor(0.2, 0.24, 0.32, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", -600, -600, 1200, 1200)

    love.graphics.setColor(0.22, 0.26, 0.35, 0.3)
    love.graphics.setLineWidth(1)
    for x = -600, 600, 50 do
        love.graphics.line(x, -600, x, 600)
    end
    for y = -600, 600, 50 do
        love.graphics.line(-600, y, 600, y)
    end
end

function draw_entity(ent, is_me)
    local radius = 18

    if is_me then
        -- Distinct color for local player
        love.graphics.setColor(0.2, 0.6, 1.0, 1)
    else
        love.graphics.setColor(0.9, 0.3, 0.3, 1)
    end

    love.graphics.circle("fill", ent.x, ent.y, radius)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", ent.x, ent.y, radius)

    -- Entity ID & HP Bar
    local hp = tonumber(ent.properties and ent.properties["hp"] or 100) or 100
    local max_hp = tonumber(ent.properties and ent.properties["max_hp"] or 100) or 100
    local bar_w = 40
    local bar_h = 5
    local bar_x = ent.x - bar_w / 2
    local bar_y = ent.y - radius - 12

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
    love.graphics.setColor(0.2, 0.9, 0.3, 1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w * (math.max(0, math.min(1, hp / max_hp))), bar_h)

    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print("P" .. tostring(ent.id), ent.x - 8, ent.y - 7)
end

function draw_hud(sw, sh, my_entity)
    -- Top Banner
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 10, 10, 320, 55, 6, 6)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Loci Arena", 20, 16)
    love.graphics.setColor(0.7, 0.7, 0.8, 1)
    love.graphics.print(connection_status, 20, 34)

    -- Instructions
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.print("WASD: Move  |  Space: Action  |  F3: Debug", 20, sh - 28)

    -- Rejection notification
    if rejection_timer > 0 then
        love.graphics.setColor(0.9, 0.2, 0.2, 0.9)
        love.graphics.printf(rejection_msg, 0, 80, sw, "center")
    end
end

function draw_debug(sw, sh)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", sw - 220, 10, 210, 90, 6, 6)

    love.graphics.setColor(0.4, 1.0, 0.5, 1)
    love.graphics.print(string.format("FPS: %d", love.timer.getFPS()), sw - 205, 20)
    love.graphics.print(string.format("Ping: %d ms", loci.get_ping_ms and loci.get_ping_ms() or 0), sw - 205, 40)
    love.graphics.print(string.format("Tick: %d", loci.get_current_tick and loci.get_current_tick() or 0), sw - 205, 60)
    love.graphics.print(string.format("Entities: %d", loci.get_entities_count and loci.get_entities_count() or 0), sw - 205, 80)
end

function love.quit()
    print("[Client] Closing connection...")
    loci.disconnect()
end
