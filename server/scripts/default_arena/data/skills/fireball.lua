-- Fireball Skill Data
-- Projétil explosivo de dano mágico em área (EntityType::Projectile com sensor CCD)
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
    id = "fireball",
    name = "Fireball",
    description = "Bola de fogo explosiva com dano mágico em área",
    mana_cost = 35,
    cooldown = 45, -- 1.5s a 30Hz
    cast_lock_ticks = 15, -- 0.5s a 30Hz: tempo de conjuração do projétil
    range = 64.0,                   -- unidades do mundo (cabe na tela: +-80 na horizontal)
    projectile_speed = 4.0,         -- unidades/tick (16 ticks para alcance máximo a 30Hz)
    projectile_radius = 1.5,        -- raio de colisão do projétil
    damage = 500,
    damage_type = CombatSystem.DamageType.MAGICAL,
    aoe_radius = 9.0,               -- unidades do mundo

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

        local proj_id = ProjectileSystem.spawn({
            caster_id = entity_id,
            skill_id = skill_data.id,
            blueprint = "fireball",
            x = caster_x,
            y = caster_y,
            dir_x = aim_x,
            dir_y = aim_y,
            speed = skill_data.projectile_speed or 4.0,
            range = skill_data.range,
            radius = skill_data.projectile_radius or 1.5,
            aoe_radius = skill_data.aoe_radius,
            damage = skill_data.damage,
            damage_type = skill_data.damage_type,
            team = caster_team,
            detonate_on_max_range = true,
        })

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Fireball] Projétil %s disparado por %s em (%.1f, %.1f) dir=(%.2f, %.2f)",
                tostring(proj_id), tostring(entity_id), caster_x, caster_y, aim_x, aim_y
            ))
        end
        return true
    end
}
