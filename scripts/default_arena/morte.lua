-- ============================================================================
-- MORTE.LUA - Funcionalidades de Combate e Morte (para incluir no main.lua)
-- ============================================================================
-- Este arquivo contém as funções relacionadas a dano, HP e morte
-- Use: dofile("scripts/default_arena/morte.lua")
-- ============================================================================

local MAX_HP = 100
local DAMAGE_AMOUNT = 25
local DAMAGE_RADIUS = 5.0

-- Função para inicializar HP de um jogador
function init_hp_stats(entity_id)
    Loci.Commands.set_property(entity_id, "hp", tostring(MAX_HP))
    Loci.Commands.set_property(entity_id, "max_hp", tostring(MAX_HP))
    Loci.Commands.set_property(entity_id, "dead", "false")
end

-- Função para verificar se está morto
function is_entity_dead(entity_id)
    return Loci.get_entity_property(entity_id, "dead") == "true"
end

-- Função para aplicar dano
function apply_damage_to_entity(attacker_id, target_id)
    if is_entity_dead(target_id) then
        return false
    end
    
    local current_hp = tonumber(Loci.get_entity_property(target_id, "hp") or MAX_HP)
    local new_hp = math.max(0, current_hp - DAMAGE_AMOUNT)
    
    Loci.Commands.set_property(target_id, "hp", tostring(new_hp))
    Loci.Log.info(string.format("DAMAGE: %d -> %d : %d/%d", 
                    attacker_id, target_id, new_hp, MAX_HP))
    
    return true, new_hp
end

-- Função para marcar como morto
function mark_as_dead(victim_id, killer_id)
    Loci.Commands.set_property(victim_id, "dead", "true")
    Loci.Log.info(string.format("ENTITY %d DIED (killed by %d)", victim_id, killer_id))
end