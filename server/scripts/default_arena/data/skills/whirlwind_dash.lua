-- Whirlwind Dash Skill Data (Habilidade 3 da Arya)
-- Investida rápida na direção da mira, girando a espada em 360º e causando dano físico em área.
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
    id = "whirlwind_dash",
    name = "Investida Giratória",
    description = "Avança na direção da mira, desferindo um giro de 360º com dano físico em área.",
    mana_cost = 25,
    cooldown = 180, -- 6 segundos a 30Hz
    range = 160,    -- Distância do avanço
    damage = 450,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 65, -- Raio da área de corte em 360º

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        -- Normaliza direção da mira
        local len = math.sqrt(aim_x * aim_x + aim_y * aim_y)
        if len > 0 then
            aim_x = aim_x / len
            aim_y = aim_y / len
        else
            aim_x, aim_y = 1, 0
        end

        local pos = Loci.get_entity_position(entity_id)
        local caster_x, caster_y = get_coords(pos)

        -- Impulso de deslocamento (Dash físico)
        local dash_speed = 22.0
        Loci.Commands.set_velocity(entity_id, {
            x = aim_x * dash_speed,
            y = aim_y * dash_speed
        })

        -- Ponto de impacto centrado na trajetória intermediária/final
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

        Loci.Log.info(string.format("[Whirlwind Dash] Executado por %s (acertou %d alvos)", tostring(entity_id), hit_count))
        return true
    end
}
