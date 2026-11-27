-- Aegis Barrier Skill Data (Habilidade 2 do Enchanter)
-- Projeta uma barreira protetora sobre o aliado mais próximo dentro do cone
-- de mira; se nenhum aliado estiver no alcance/ângulo, protege a si mesmo.
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("systems.character_factory")
local TeamUtils = require("core.team_utils")

return {
    id = "aegis_barrier",
    name = "Barreira de Égide",
    description = "Concede escudo de absorção ao aliado na mira (ou a si mesmo).",
    mana_cost = 35,
    cooldown = 210,        -- 7.0s a 30Hz
    cast_lock_ticks = 12,  -- 0.4s a 30Hz
    range = 36.0,          -- unidades do mundo
    shield_amount = 850,
    shield_duration_ticks = 120, -- 4.0s a 30Hz
    cone_dot = 0.2,
    aoe_radius = 1.5,      -- raio do indicador de mira (alvo único)

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        aim_x, aim_y = TeamUtils.normalize_aim(aim_x, aim_y)

        local candidates = TeamUtils.get_allies_in_cone(
            entity_id, aim_x, aim_y, skill_data.range, skill_data.cone_dot, false)

        -- Seleciona o aliado mais próximo da linha de mira
        local best = nil
        for _, cand in ipairs(candidates) do
            if not best or cand.dist < best.dist then
                best = cand
            end
        end

        local target_id = (best and best.id) or entity_id

        -- Não reduz um escudo existente maior: renova a duração com o valor atual
        local current_tick = CharacterFactory.get_current_tick()
        local existing_shield = tonumber(Loci.get_entity_property(target_id, "shield")) or 0
        local shield_amount = math.max(existing_shield, skill_data.shield_amount)
        CombatSystem.apply_shield(target_id, shield_amount, skill_data.shield_duration_ticks, current_tick)

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Aegis Barrier] Escudo de %d aplicado a %s por %s (alvo: %s)",
                math.floor(shield_amount), tostring(target_id), tostring(entity_id),
                best and "aliado" or "self"))
        end
        return true
    end
}
