-- Fireball Skill Data
-- Projétil explosivo de dano mágico em área
local CombatSystem = require("core.combat_system")

local function get_coords(pos)
    if not pos then return 0, 0 end
    if type(pos.x_float) == "function" then
        return pos:x_float(), pos:y_float()
    elseif pos.x and pos.y then
        return pos.x, pos.y
    end
    return 0, 0
end

return {
    id = "fireball",
    name = "Fireball",
    description = "Bola de fogo explosiva com dano mágico em área",
    mana_cost = 35,
    cooldown = 45, -- 1.5s a 30Hz
    range = 300,
    damage = 500,
    damage_type = CombatSystem.DamageType.MAGICAL,
    aoe_radius = 60,

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local pos = Loci.get_entity_position(entity_id)
        local caster_x, caster_y = get_coords(pos)

        -- Ponto de impacto na direção da mira
        local target_x = caster_x + aim_x * (skill_data.range * 0.7)
        local target_y = caster_y + aim_y * (skill_data.range * 0.7)

        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"
        local hit_ids = Loci.get_entities_in_radius({ x = target_x, y = target_y }, skill_data.aoe_radius)

        local hit_count = 0
        if hit_ids then
            for _, target_id in ipairs(hit_ids) do
                if target_id ~= entity_id then
                    local target_team = Loci.get_entity_property(target_id, "team") or "2"
                    if target_team ~= caster_team then
                        CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type)
                        hit_count = hit_count + 1
                    end
                end
            end
        end

        Loci.Log.info(string.format("[Fireball] Executado por %s (acertou %d alvos na explosão)", tostring(entity_id), hit_count))
        return true
    end
}
