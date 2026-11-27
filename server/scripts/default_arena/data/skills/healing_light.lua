-- Healing Light Skill Data (Habilidade 2 do Cleric)
-- Cura o aliado mais ferido dentro do cone de mira; se nenhum aliado estiver
-- no alcance/ângulo, cura o próprio Cleric.
local TeamUtils = require("core.team_utils")

return {
    id = "healing_light",
    name = "Luz Curativa",
    description = "Cura o aliado mais ferido na direção da mira (ou a si mesmo).",
    mana_cost = 35,
    cooldown = 180,        -- 6.0s a 30Hz
    cast_lock_ticks = 12,  -- 0.4s a 30Hz
    range = 36.0,          -- unidades do mundo
    heal_amount = 500,
    cone_dot = 0.2,        -- ~78° de semi-ângulo de mira
    aoe_radius = 1.5,      -- raio do indicador de mira (alvo único)

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        aim_x, aim_y = TeamUtils.normalize_aim(aim_x, aim_y)

        local candidates = TeamUtils.get_allies_in_cone(
            entity_id, aim_x, aim_y, skill_data.range, skill_data.cone_dot, false)

        -- Seleciona o aliado mais ferido (menor fração de HP restante)
        local best = nil
        local best_ratio = math.huge
        for _, cand in ipairs(candidates) do
            local ratio = cand.max_hp > 0 and (cand.hp / cand.max_hp) or 1
            if ratio < best_ratio then
                best_ratio = ratio
                best = cand
            end
        end

        local target_id = (best and best.id) or entity_id
        local healed = TeamUtils.heal(target_id, skill_data.heal_amount)

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Healing Light] %s curou %s em %d HP (alvo: %s)",
                tostring(entity_id), tostring(target_id), math.floor(healed),
                best and "aliado" or "self"))
        end
        return true
    end
}
