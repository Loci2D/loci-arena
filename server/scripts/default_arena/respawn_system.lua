-- Sistema de Respawn para Loci Arena
-- Revive jogadores mortos a cada 10 segundos

local respawn_system = {}

-- Configurações
local RESPAWN_INTERVAL_TICKS = 300  -- 10 segundos a 30 Hz

-- Estado interno
local current_tick_internal = 0
local dead_players = {}  -- Lista de jogadores mortos, armazena o tick em que morreram

-- Adicionar jogador à lista de mortos
function respawn_system.mark_dead(entity_id)
    dead_players[entity_id] = current_tick_internal
    Loci.Commands.set_property(entity_id, "is_dead", "true")
end

-- Remover jogador da lista de mortos (quando reviver)
function respawn_system.mark_alive(entity_id)
    dead_players[entity_id] = nil
    Loci.Commands.set_property(entity_id, "is_dead", "false")
end

-- Verificar se um jogador está morto
function respawn_system.is_dead(entity_id)
    return dead_players[entity_id] ~= nil
end

-- Reviver um jogador específico
function respawn_system.revive_player(entity_id)
    if dead_players[entity_id] then
        local max_hp = tonumber(Loci.get_entity_property(entity_id, "max_hp") or 100) or 100
        
        -- Restaurar HP
        Loci.Commands.set_property(entity_id, "hp", tostring(max_hp))
        Loci.Commands.set_property(entity_id, "is_dead", "false")

        -- Remover da lista de mortos
        dead_players[entity_id] = nil

        Loci.Log.info("[Respawn] Entity " .. entity_id .. " has been revived!")
        return true
    end
    return false
end

-- Verificar e processar respawn (chamado a cada tick)
function respawn_system.process_tick(current_tick)
    current_tick_internal = current_tick
    local revived_count = 0
    for entity_id, death_tick in pairs(dead_players) do
        -- A cada 10 segundos (300 ticks), reviver o jogador
        if current_tick - death_tick >= RESPAWN_INTERVAL_TICKS then
            respawn_system.revive_player(entity_id)
            revived_count = revived_count + 1
        end
    end

    if revived_count > 0 then
        Loci.Log.info("[Respawn] Revived " .. revived_count .. " players")
    end
end

-- Limpar estado quando jogador sai
function respawn_system.cleanup(entity_id)
    dead_players[entity_id] = nil
end

return respawn_system
