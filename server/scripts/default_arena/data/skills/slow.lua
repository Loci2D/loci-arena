-- Slow Skill Data
-- Habilidade que aplica desaceleração em alvos em área
local CharacterFactory = require("default_arena.systems.character_factory")

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
    id = "slow",
    name = "Slow",
    description = "Aplica desaceleração em alvos em área (50% velocidade por 3 segundos)",
    mana_cost = 15,
    cooldown = 180, -- 6 segundos a 30Hz
    range = 100,
    aoe_radius = 60,

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local pos = Loci.get_entity_position(entity_id)
        local caster_x, caster_y = get_coords(pos)

        -- Ponto de impacto na direção da mira
        local target_x = caster_x + aim_x * (skill_data.range * 0.5)
        local target_y = caster_y + aim_y * (skill_data.range * 0.5)

        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"
        local hit_ids = Loci.get_entities_in_radius({ x = target_x, y = target_y }, skill_data.aoe_radius)

        local hit_count = 0
        local current_tick = CharacterFactory.get_current_tick() or 0
        local slow_duration = 3 -- 3 segundos
        local slow_end_tick = current_tick + (slow_duration * 30) -- 30 ticks por segundo
        local slow_multiplier = 0.5 -- 50% da velocidade

        if hit_ids then
            for _, target_id in ipairs(hit_ids) do
                if target_id ~= entity_id then
                    local target_team = Loci.get_entity_property(target_id, "team") or "2"
                    if target_team ~= caster_team then
                        Loci.Commands.set_property(target_id, "slowed_until", tostring(slow_end_tick))
                        Loci.Commands.set_property(target_id, "slow_multiplier", tostring(slow_multiplier))
                        hit_count = hit_count + 1
                    end
                end
            end
        end

        Loci.Log.info(string.format("[Slow] Executado por %s (acertou %d alvos)", tostring(entity_id), hit_count))
        return true
    end
}
