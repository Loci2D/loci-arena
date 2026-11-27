-- Kinetic Pulse Skill Data (Habilidade Básica do Enchanter)
-- Disparo de energia cinética de impacto rápido
local CombatSystem = require("core.combat_system")
local ProjectileSystem = require("systems.projectile_system")

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
    id = "kinetic_pulse",
    name = "Pulso Cinético",
    description = "Disparo de impacto cinético",
    mana_cost = 8,
    cooldown = 18,        -- 0.6s a 30Hz
    cast_lock_ticks = 6,  -- 0.2s a 30Hz
    range = 30.0,         -- unidades do mundo
    projectile_speed = 4.5,
    projectile_radius = 1.4,
    damage = 200,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 5.0,

    on_execute = function(entity_id, aim_x, aim_y, skill_data, opts)
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

        ProjectileSystem.spawn({
            caster_id = entity_id,
            skill_id = skill_data.id,
            blueprint = "kinetic_pulse",
            x = caster_x,
            y = caster_y,
            dir_x = aim_x,
            dir_y = aim_y,
            speed = skill_data.projectile_speed or 4.5,
            range = skill_data.range,
            radius = skill_data.projectile_radius or 1.4,
            aoe_radius = skill_data.aoe_radius,
            damage = skill_data.damage,
            damage_type = skill_data.damage_type,
            team = caster_team,
            detonate_on_max_range = true,
            target_id = opts and opts.target_id, -- target-lock: projétil teleguiado ao alvo travado
        })
        return true
    end
}
