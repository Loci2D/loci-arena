local CombatSystem = {}

-- Constantes baseadas na documentação (Single Source of Truth)
CombatSystem.CONST = {
    DEFENSE_K = 100,               -- Constante para calcular redução de dano (K)
    CRIT_CHANCE_BASE = 0.10,       -- 10% de chance base de crítico
    CRIT_MULTIPLIER = 2.25,        -- Dano x 2.25 quando crita
    FRAGILITY_MULT = 1.30          -- 30% a mais de dano se o alvo for "Frágil"
}

-- Tipos de Dano Suportados
CombatSystem.DamageType = {
    PHYSICAL = 1,
    MAGICAL = 2,
    TRUE = 3 -- Ignora defesas
}

-- Helper para inicializar os atributos num player
function CombatSystem.init_entity(entity_id, max_hp, phys_def, mag_def)
    Loci.Commands.set_property(entity_id, "max_hp", tostring(max_hp))
    Loci.Commands.set_property(entity_id, "hp", tostring(max_hp))
    Loci.Commands.set_property(entity_id, "phys_def", tostring(phys_def))
    Loci.Commands.set_property(entity_id, "mag_def", tostring(mag_def))
    
    -- Status effects (0 = off, 1 = on)
    Loci.Commands.set_property(entity_id, "fragile", "0")
    
    Loci.Log.info("[Combat] Atributos base definidos para " .. tostring(entity_id))
end

-- Calcula a Redução de Dano (%) usando a fórmula Diminishing Returns
function CombatSystem.calculate_mitigation(defense)
    if defense < 0 then defense = 0 end
    return defense / (defense + CombatSystem.CONST.DEFENSE_K)
end

-- Processa um ataque passando pelas regras do jogo
-- Retorna uma tabela com o resultado do ataque
function CombatSystem.process_hit(attacker_id, target_id, base_damage, dmg_type, force_crit)
    
    -- 1. Obter HP atual
    local target_hp = tonumber(Loci.Commands.get_property(target_id, "hp"))
    if not target_hp or target_hp <= 0 then 
        return { success = false, reason = "target_dead" } 
    end

    -- 2. Identificar qual Defesa usar
    local def = 0
    if dmg_type == CombatSystem.DamageType.PHYSICAL then
        def = tonumber(Loci.Commands.get_property(target_id, "phys_def")) or 0
    elseif dmg_type == CombatSystem.DamageType.MAGICAL then
        def = tonumber(Loci.Commands.get_property(target_id, "mag_def")) or 0
    end
    -- Dano Verdadeiro (TRUE) fica com def = 0

    -- 3. Calcular Dano Mitigado
    local mitigation = CombatSystem.calculate_mitigation(def)
    local final_damage = base_damage * (1 - mitigation)

    -- 4. Processar Crítico (RNG)
    local is_crit = force_crit or (math.random() <= CombatSystem.CONST.CRIT_CHANCE_BASE)
    if is_crit then
        final_damage = final_damage * CombatSystem.CONST.CRIT_MULTIPLIER
        
        -- TODO: Implementar lógica de Sangramento se for Físico ou Queimadura se for Mágico
    end

    -- 5. Processar Modificadores e Debuffs (ex: Fragilidade)
    local is_fragile = Loci.Commands.get_property(target_id, "fragile") == "1"
    if is_fragile then
        final_damage = final_damage * CombatSystem.CONST.FRAGILITY_MULT
    end

    -- 6. Aplicar Dano no HP (mantendo no mínimo 0)
    target_hp = math.max(0, target_hp - final_damage)
    Loci.Commands.set_property(target_id, "hp", tostring(target_hp))

    Loci.Log.info(string.format("[Combat] Dano %d (Mitig: %.1f%%) causado em %s", 
        math.floor(final_damage), mitigation * 100, tostring(target_id)))

    -- 7. Checar Morte
    if target_hp == 0 then
        -- Loci.Commands.trigger_event("entity_death", target_id)
        Loci.Log.info("[Combat] " .. tostring(target_id) .. " foi eliminado!")
    end

    return {
        success = true,
        damage_dealt = final_damage,
        was_critical = is_crit,
        lethal = (target_hp == 0)
    }
end

return CombatSystem
