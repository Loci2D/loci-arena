-- Bastion Overload Skill Data (Ultimate do Enchanter)
-- Cúpula protetora em 360º: concede escudo de grupo e +25% de velocidade de
-- movimento para todos os aliados na área por 5 segundos.
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("systems.character_factory")
local TeamUtils = require("core.team_utils")

return {
    id = "bastion_overload",
    name = "Sobrecarga do Bastião",
    description = "Escudo de grupo e aceleração de movimento para todos os aliados na área.",
    mana_cost = 55,
    cooldown = 450,        -- 15.0s a 30Hz
    cast_lock_ticks = 24,  -- 0.8s a 30Hz
    range = 0,             -- efeito centrado no próprio Enchanter
    aoe_radius = 22.0,     -- raio da cúpula do bastião
    duration_ticks = 150,  -- 5.0s a 30Hz
    shield_amount = 1000,
    speed_boost_mult = 1.25, -- +25% de velocidade de movimento

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local cx, cy = TeamUtils.get_entity_xy(entity_id)
        if not cx then return false, "Caster position unavailable" end

        local current_tick = CharacterFactory.get_current_tick()
        local buff_until = current_tick + skill_data.duration_ticks
        local allies = TeamUtils.get_allies(entity_id, cx, cy, skill_data.aoe_radius, true)

        for _, id in ipairs(allies) do
            -- Não reduz um escudo existente maior: renova a duração com o valor atual
            local existing_shield = tonumber(Loci.get_entity_property(id, "shield")) or 0
            local shield_amount = math.max(existing_shield, skill_data.shield_amount)
            CombatSystem.apply_shield(id, shield_amount, skill_data.duration_ticks, current_tick)

            Loci.Commands.set_property(id, "speed_boost_until", tostring(buff_until))
            Loci.Commands.set_property(id, "speed_boost_mult", tostring(skill_data.speed_boost_mult))
        end

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Bastion Overload] %s potencializou %d aliados em (%.1f, %.1f) r=%.1f",
                tostring(entity_id), #allies, cx, cy, skill_data.aoe_radius))
        end
        return true
    end
}
