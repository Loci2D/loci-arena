-- Sistema de Respawn para Loci Arena
-- Revive jogadores mortos a cada 10 segundos

local respawn_system = {}

-- Configurações
local RESPAWN_INTERVAL_TICKS = 300  -- 10 segundos a 30 Hz

-- Estado interno
local current_tick_internal = 0
local dead_players = {}  -- Lista array de jogadores mortos: { {id=1, death_tick=0}, ... }

-- Encontra o índice de um jogador morto
local function find_dead_player_index(entity_id)
    for i, p in ipairs(dead_players) do
        if p.id == entity_id then return i end
    end
    return nil
end

-- Adicionar jogador à lista de mortos
function respawn_system.mark_dead(entity_id)
    if not find_dead_player_index(entity_id) then
        table.insert(dead_players, {id = entity_id, death_tick = current_tick_internal})
    end
    Loci.Commands.set_property(entity_id, "is_dead", "true")
end

-- Remover jogador da lista de mortos (quando reviver)
function respawn_system.mark_alive(entity_id)
    local idx = find_dead_player_index(entity_id)
    if idx then
        table.remove(dead_players, idx)
    end
    Loci.Commands.set_property(entity_id, "is_dead", "false")
end

-- Verificar se um jogador está morto
function respawn_system.is_dead(entity_id)
    return find_dead_player_index(entity_id) ~= nil
end

-- Reviver um jogador específico
function respawn_system.revive_player(entity_id)
    local idx = find_dead_player_index(entity_id)
    if idx then
        local max_hp = tonumber(Loci.get_entity_property(entity_id, "max_hp") or 100) or 100
        
        -- Restaurar HP
        Loci.Commands.set_property(entity_id, "hp", tostring(max_hp))
        Loci.Commands.set_property(entity_id, "is_dead", "false")

        -- Remover da lista de mortos
        table.remove(dead_players, idx)

        Loci.Log.info("[Respawn] Entity " .. entity_id .. " has been revived!")
        return true
    end
    return false
end

-- Verificar e processar respawn (chamado a cada tick)
function respawn_system.process_tick(current_tick)
    current_tick_internal = current_tick
    local revived_count = 0
    
    -- Iterar de trás pra frente pois podemos remover elementos
    for i = #dead_players, 1, -1 do
        local p = dead_players[i]
        -- A cada 10 segundos (300 ticks), reviver o jogador
        if current_tick - p.death_tick >= RESPAWN_INTERVAL_TICKS then
            -- Como usamos revive_player que faz table.remove internamente,
            -- é seguro pois estamos indo de trás para frente.
            respawn_system.revive_player(p.id)
            revived_count = revived_count + 1
        end
    end

    if revived_count > 0 then
        Loci.Log.info("[Respawn] Revived " .. revived_count .. " players")
    end
end

-- Limpar estado quando jogador sai
function respawn_system.cleanup(entity_id)
    local idx = find_dead_player_index(entity_id)
    if idx then
        table.remove(dead_players, idx)
    end
end

return respawn_system
