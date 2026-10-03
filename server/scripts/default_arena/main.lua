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

-- Importa o sistema de combate que centraliza a lógica do jogo
local CombatSystem = require("core.combat_system")

function on_player_join(entity_id)
    Loci.Log.info("[Arena] Player joined with entity ID " .. tostring(entity_id))
    
    -- Initialize entity game properties
    Loci.Commands.set_property(entity_id, "team", "1")
    Loci.Commands.set_property(entity_id, "score", "0")

    -- Inicializa os atributos definidos no Game Rules (ex: HP 4000, Def Fis 100, Def Mag 50)
    CombatSystem.init_entity(entity_id, 4000, 100, 50)
end

function on_move_intent(entity_id, dir_x, dir_y)
    -- Normalize movement vector so diagonal movement doesn't provide a speed boost
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if len > 0 then
        dir_x = dir_x / len
        dir_y = dir_y / len
    end

    -- Set server authoritative velocity (displacement per tick)
    Loci.Commands.set_velocity(entity_id, {
        x = dir_x * SPEED,
        y = dir_y * SPEED
    })
    return true
end

function on_action(entity_id, ability_id, aim_x, aim_y)
    Loci.Log.info("[Arena] Action from entity " .. tostring(entity_id) .. " -> Ability: " .. tostring(ability_id))
    
    -- Feature placeholder: Handle skills, spells, dash, attack
    if ability_id == 1 then
        -- Example: Primary attack
        -- Aqui o motor de colisão da Loci2D deve identificar quem foi acertado.
        -- Supondo que você detectou um "target_id", a chamada seria:
        -- CombatSystem.process_hit(entity_id, target_id, 250, CombatSystem.DamageType.PHYSICAL, false)
        return true
    end

    return false, "Ability not implemented or on cooldown"
end

function on_player_leave(entity_id)
    Loci.Log.info("[Arena] Player left: " .. tostring(entity_id))
    Loci.Commands.destroy_entity(entity_id)
end
