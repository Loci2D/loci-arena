-- Loci Arena - Authoritative Game Logic (Lua Server Script)
-- This script runs inside the loci2d server environment.
-- Rules, physics modifications, damage and game mechanics must be handled here.

-- Movement speed in units per tick.
-- At 30 Hz server tick rate: 5.0 units/tick = 150 units (pixels) per second.
local SPEED = 3.0
local _player_join_count = 0

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

function on_tick(current_tick)
    CharacterFactory.update_tick(current_tick)
    RespawnSystem.process_tick(current_tick)
end

function on_player_join(entity_id)
    Loci.Log.info("[Arena] Player joined with entity ID " .. tostring(entity_id))
    
    -- Inicializa propriedades básicas de match
    -- Aloca jogadores em times de forma intercalada (Time 1 e Time 2)
    _player_join_count = _player_join_count + 1
    local team_id = tostring((_player_join_count % 2 == 1) and 1 or 2)
    Loci.Commands.set_property(entity_id, "team", team_id)
    Loci.Commands.set_property(entity_id, "score", "0")
    Loci.Commands.set_property(entity_id, "kills", "0")
    Loci.Commands.set_property(entity_id, "deaths", "0")
    Loci.Commands.set_property(entity_id, "is_dead", "false")

    -- Instancia o personagem (agora definido como Arya para teste)
    CharacterFactory.create_character(entity_id, "arya")
end

function on_move_intent(entity_id, dir_x, dir_y)
    if RespawnSystem.is_dead(entity_id) then
        return false, "Você está morto"
    end

    local paralyzed_until = tonumber(Loci.get_entity_property(entity_id, "paralyzed_until")) or 0
    if CharacterFactory.get_current_tick() < paralyzed_until then
        -- Cancel velocity during paralysis
        Loci.Commands.set_velocity(entity_id, {x = 0, y = 0})
        return false, "Personagem paralisado por choque térmico/emocional."
    end

    local stunned_until = tonumber(Loci.get_entity_property(entity_id, "stunned_until")) or 0
    if CharacterFactory.get_current_tick() < stunned_until then
        Loci.Commands.set_velocity(entity_id, {x = 0, y = 0})
        return false, "Personagem atordoado (Stun)."
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

    local paralyzed_until = tonumber(Loci.get_entity_property(entity_id, "paralyzed_until")) or 0
    if CharacterFactory.get_current_tick() < paralyzed_until then
        return false, "Personagem paralisado por choque térmico/emocional."
    end

    local stunned_until = tonumber(Loci.get_entity_property(entity_id, "stunned_until")) or 0
    if CharacterFactory.get_current_tick() < stunned_until then
        return false, "Personagem atordoado (Stun)."
    end

    local disarmed_until = tonumber(Loci.get_entity_property(entity_id, "disarmed_until")) or 0
    if CharacterFactory.get_current_tick() < disarmed_until then
        return false, "Personagem desarmado (sem espada)."
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
