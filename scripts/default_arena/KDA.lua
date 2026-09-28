-- ============================================================================
-- KDA.LUA - Funcionalidades de Estatísticas (para incluir no main.lua)
-- ============================================================================
-- Este arquivo contém as funções relacionadas a K/D/A
-- Use: dofile("scripts/default_arena/KDA.lua")
-- ============================================================================

-- Função para inicializar estatísticas de um jogador
function init_kda_stats(entity_id)
    Loci.Commands.set_property(entity_id, "kills", "0")
    Loci.Commands.set_property(entity_id, "deaths", "0")
    Loci.Commands.set_property(entity_id, "assists", "0")
    Loci.Commands.set_property(entity_id, "team", "1")
end

-- Função para registrar um kill
function register_kill(killer_id, victim_id)
    local kills = tonumber(Loci.get_entity_property(killer_id, "kills") or "0") + 1
    Loci.Commands.set_property(killer_id, "kills", tostring(kills))
    
    local deaths = tonumber(Loci.get_entity_property(victim_id, "deaths") or "0") + 1
    Loci.Commands.set_property(victim_id, "deaths", tostring(deaths))
    
    Loci.Log.info(string.format("KILL: %d killed %d", killer_id, victim_id))
end