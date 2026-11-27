-- Divine Resurgence Skill Data (Ultimate do Cleric)
-- Pulso sagrado em 360º ao redor do Cleric: cura todos os aliados no raio
-- e concede escudo de emergência.
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("systems.character_factory")
local TeamUtils = require("core.team_utils")

return {
    id = "divine_resurgence",
    name = "Ressurgência Divina",
    description = "Cura em área todos os aliados e concede escudo de emergência.",
    mana_cost = 65,
    cooldown = 480,        -- 16.0s a 30Hz
    cast_lock_ticks = 24,  -- 0.8s a 30Hz
    range = 0,             -- efeito centrado no próprio Cleric
    aoe_radius = 24.0,     -- raio do pulso sagrado
    heal_amount = 700,
    shield_amount = 400,
    shield_duration_ticks = 90, -- 3.0s a 30Hz

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local cx, cy = TeamUtils.get_entity_xy(entity_id)
        if not cx then return false, "Caster position unavailable" end

        local current_tick = CharacterFactory.get_current_tick()
        local allies = TeamUtils.get_allies(entity_id, cx, cy, skill_data.aoe_radius, true)

        local healed_count = 0
        for _, id in ipairs(allies) do
            local healed = TeamUtils.heal(id, skill_data.heal_amount)
            if healed > 0 then healed_count = healed_count + 1 end
            -- Não reduz um escudo existente maior: renova a duração com o valor atual
            local existing_shield = tonumber(Loci.get_entity_property(id, "shield")) or 0
            local shield_amount = math.max(existing_shield, skill_data.shield_amount)
            CombatSystem.apply_shield(id, shield_amount, skill_data.shield_duration_ticks, current_tick)
        end

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Divine Resurgence] %s curou %d aliados em (%.1f, %.1f) r=%.1f",
                tostring(entity_id), healed_count, cx, cy, skill_data.aoe_radius))
        end
        return true
    end
}
