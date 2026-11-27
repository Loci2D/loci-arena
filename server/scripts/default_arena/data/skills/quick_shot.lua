-- Quick Shot Skill Data
-- Disparo rápido básico de flecha com projétil físico
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
    id = "quick_shot",
    name = "Quick Shot",
    description = "Disparo rápido de flecha com dano físico",
    mana_cost = 8,
    cooldown = 12, -- 0.4s a 30Hz
    range = 48.0,     -- unidades do mundo (~6 alturas de personagem)
    damage = 280,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    projectile_speed = 18.0, -- velocidade do projétil em unidades/tick
    projectile_radius = 0.5,

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        -- Normaliza vetor de mira
        local len = math.sqrt(aim_x * aim_x + aim_y * aim_y)
        if len > 0 then
            aim_x = aim_x / len
            aim_y = aim_y / len
        else
            aim_x, aim_y = 1, 0
        end

        local pos = Loci.get_entity_position(entity_id)
        local caster_x, caster_y = get_coords(pos)
        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"

        -- Amostragem linear (raycast simulado) para detecção de alvos
        local hit_ids = {}
        local step = 2.0
        local d = 2.0
        while d < skill_data.range do
            local sample_x = caster_x + aim_x * d
            local sample_y = caster_y + aim_y * d
            local nearby = Loci.get_entities_in_radius({ x = sample_x, y = sample_y }, skill_data.projectile_radius)
            if nearby then
                for _, target_id in ipairs(nearby) do
                    if target_id ~= entity_id then
                        local target_team = Loci.get_entity_property(target_id, "team") or "2"
                        if target_team ~= caster_team then
                            CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type)
                            table.insert(hit_ids, target_id)
                            break
                        end
                    end
                end
            end
            if #hit_ids > 0 then break end
            d = d + step
        end

        Loci.Log.info(string.format("[Quick Shot] Executado por %s", tostring(entity_id)))
        return true
    end
}
