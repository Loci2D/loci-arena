-- Sistema de Respawn para Loci Arena
-- Revive jogadores mortos a cada 10 segundos

local respawn_system = {}

-- Configurações
local RESPAWN_INTERVAL_TICKS = 300  -- 10 segundos a 30 Hz
local RESPAWN_HP = 100
local RESPAWN_POSITION_X = 0
local RESPAWN_POSITION_Y = 0

-- Estado interno
local current_tick = 0
local dead_players = {}  -- Lista de jogadores mortos

-- Adicionar jogador à lista de mortos
function respawn_system.mark_dead(entity_id)
    dead_players[entity_id] = true
end

-- Remover jogador da lista de mortos (quando reviver)
function respawn_system.mark_alive(entity_id)
    dead_players[entity_id] = nil
end

-- Verificar se um jogador está morto
function respawn_system.is_dead(entity_id)
    return dead_players[entity_id] or false
end

-- Reviver um jogador específico
function respawn_system.revive_player(entity_id, player_hp_ref, player_is_dead_ref)
    if dead_players[entity_id] then
        -- Restaurar HP
        player_hp_ref[entity_id] = RESPAWN_HP
        player_is_dead_ref[entity_id] = false

        -- Sincronizar com cliente
        Loci.Commands.set_property(entity_id, "hp", tostring(RESPAWN_HP))
        Loci.Commands.set_property(entity_id, "is_dead", "false")

        -- Remover da lista de mortos
        dead_players[entity_id] = nil

        Loci.Log.info("[Respawn] Entity " .. entity_id .. " has been revived!")
        return true
    end
    return false
end

-- Verificar e processar respawn (chamado a cada tick)
function respawn_system.process_tick(player_hp_ref, player_is_dead_ref)
    current_tick = current_tick + 1

    -- A cada 10 segundos, reviver todos os jogadores mortos
    if current_tick >= RESPAWN_INTERVAL_TICKS then
        current_tick = 0

        -- Reviver todos os jogadores mortos
        local revived_count = 0
        for entity_id, _ in pairs(dead_players) do
            respawn_system.revive_player(entity_id, player_hp_ref, player_is_dead_ref)
            revived_count = revived_count + 1
        end

        if revived_count > 0 then
            Loci.Log.info("[Respawn] Revived " .. revived_count .. " players")
        end
    end
end

-- Limpar estado quando jogador sai
function respawn_system.cleanup(entity_id)
    dead_players[entity_id] = nil
end

return respawn_system
