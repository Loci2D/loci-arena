-- Loci Arena - Authoritative Game Logic (Lua Server Script)
-- This script runs inside the loci2d server environment.
-- Rules, physics modifications, damage and game mechanics must be handled here.

-- Movement speed in units per tick.
-- At 30 Hz server tick rate: 5.0 units/tick = 150 units (pixels) per second.
local SPEED = 3.0

-- =============================================================================
-- Module Loader Polyfill (require)
-- Suporte a múltiplos arquivos e importações modulares no ambiente sandbox do Lua.
-- =============================================================================
local _LOADED = {}
local SEARCH_PATTERNS = {
    "scripts/%s.lua",
    "scripts/%s/init.lua",
    "scripts/default_arena/%s.lua",
    "%s.lua"
}

function require(modname)
    if _LOADED[modname] then
        return _LOADED[modname]
    end

    local clean_name = modname:gsub("%.", "/")
    local chunk, err = nil, nil
    local tried = {}

    for _, pattern in ipairs(SEARCH_PATTERNS) do
        local path = string.format(pattern, clean_name)
        chunk, err = loadfile(path)
        if chunk then
            break
        end
        table.insert(tried, path)
    end

    if not chunk then
        error(string.format("module '%s' not found:\n\tno file '%s'\n\tlast error: %s",
            modname, table.concat(tried, "'\n\tno file '"), tostring(err)))
    end

    local result = chunk()
    _LOADED[modname] = (result ~= nil) and result or true
    return _LOADED[modname]
end

-- Importa os sistemas modulares da arena
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("default_arena.systems.character_factory")
local RespawnSystem = require("default_arena.respawn_system")
local ProjectileSystem = require("default_arena.projectile_system")

-- =============================================================================
-- Obstacle System
-- Spawns static collision obstacles when the first player joins.
-- =============================================================================
local obstacles_spawned = false

-- Obstacle layout: {x, y, radius}
-- Arena is [-500, +500] in both axes.
local OBSTACLE_DEFS = {
    -- Four corner clusters
    { x = -300, y = -300, radius = 30 },
    { x = -260, y = -280, radius = 22 },
    { x =  300, y = -300, radius = 30 },
    { x =  265, y = -270, radius = 22 },
    { x = -300, y =  300, radius = 30 },
    { x = -270, y =  265, radius = 22 },
    { x =  300, y =  300, radius = 30 },
    { x =  270, y =  270, radius = 22 },

    -- Central pillar cross
    { x =    0, y =    0, radius = 28 },
    { x =  -80, y =    0, radius = 20 },
    { x =   80, y =    0, radius = 20 },
    { x =    0, y =  -80, radius = 20 },
    { x =    0, y =   80, radius = 20 },

    -- Mid-lane rocks (horizontal)
    { x = -180, y =  -30, radius = 24 },
    { x =  180, y =   30, radius = 24 },
    { x = -180, y =  150, radius = 20 },
    { x =  180, y = -150, radius = 20 },

    -- Scattered singles
    { x =  -50, y = -200, radius = 18 },
    { x =   60, y =  210, radius = 18 },
    { x = -230, y =   50, radius = 22 },
    { x =  230, y =  -55, radius = 22 },
    { x =  120, y = -340, radius = 26 },
    { x = -130, y =  340, radius = 26 },
}

local function spawn_obstacles()
    if obstacles_spawned then return end
    obstacles_spawned = true

    for i, def in ipairs(OBSTACLE_DEFS) do
        Loci.Commands.spawn_entity({
            blueprint    = "Obstacle",
            position     = { x = def.x, y = def.y },
            entity_type  = "Static",
            move_speed   = 0,
            radius       = def.radius,
            properties   = {
                obstacle_id = tostring(i),
                radius      = tostring(def.radius),
            }
        })
    end

    Loci.Log.info(string.format("[Arena] Spawned %d obstacles", #OBSTACLE_DEFS))
end

function on_tick(current_tick)
    CharacterFactory.update_tick(current_tick)
    RespawnSystem.process_tick(current_tick)
    ProjectileSystem.update_tick(current_tick)
end

function on_player_join(entity_id)
    Loci.Log.info("[Arena] Player joined with entity ID " .. tostring(entity_id))

    -- Spawn map obstacles once on first join
    spawn_obstacles()

    -- Inicializa propriedades básicas de match
    -- Atribui cada jogador a um time único (Free For All) para que habilidades causem dano
    Loci.Commands.set_property(entity_id, "team", tostring(entity_id))
    Loci.Commands.set_property(entity_id, "score", "0")
    Loci.Commands.set_property(entity_id, "kills", "0")
    Loci.Commands.set_property(entity_id, "deaths", "0")
    Loci.Commands.set_property(entity_id, "is_dead", "false")


    -- Instancia o personagem (por padrão warrior, pode ser alternado ou selecionado pelo cliente)
    CharacterFactory.create_character(entity_id, "warrior")
end

function on_move_intent(entity_id, dir_x, dir_y)
    if RespawnSystem.is_dead(entity_id) then
        return false, "Você está morto"
    end

    -- Normalize movement vector so diagonal movement doesn't provide a speed boost
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if len > 0 then
        dir_x = dir_x / len
        dir_y = dir_y / len
    end

    local move_speed = tonumber(Loci.get_entity_property(entity_id, "move_speed") or SPEED) or SPEED

    -- Set server authoritative velocity (displacement per tick)
    Loci.Commands.set_velocity(entity_id, {
        x = dir_x * move_speed,
        y = dir_y * move_speed
    })
    return true
end

function on_action(entity_id, ability_id, aim_x, aim_y)
    Loci.Log.info("[Arena] Action from entity " .. tostring(entity_id) .. " -> Ability: " .. tostring(ability_id))
    
    if RespawnSystem.is_dead(entity_id) then
        return false, "Você está morto"
    end

    -- Busca a habilidade equipada no slot correspondente ao ability_id
    local skill_name = CharacterFactory.get_skill_by_slot(entity_id, ability_id)
    if not skill_name then
        return false, "Ability not equipped or invalid slot"
    end

    -- Executa a habilidade via CharacterFactory
    local success, err = CharacterFactory.execute_skill(entity_id, skill_name, aim_x, aim_y)
    if not success then
        return false, err or "Ability execution failed"
    end

    return true
end

function on_player_leave(entity_id)
    Loci.Log.info("[Arena] Player left: " .. tostring(entity_id))
    CharacterFactory.on_entity_remove(entity_id)
    RespawnSystem.cleanup(entity_id)
    Loci.Commands.destroy_entity(entity_id)
end
