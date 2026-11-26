-- Blade Throw Skill Data (Habilidade 4 / Ultimate da Arya)
-- Arremessa a espada como uma entidade Projectile física (sensor CCD).
-- Causa dano físico e atordoamento (Stun) em área no impacto, mas deixa Arya desarmada por 2.0s.
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("systems.character_factory")
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
    id = "blade_throw",
    name = "Arremesso de Lâmina",
    description = "Arremessa a espada. Causa dano físico e Stun em área no impacto, mas aplica Desarme na Arya por 2.0s.",
    mana_cost = 45,
    cooldown = 420, -- 14 segundos a 30Hz
    cast_lock_ticks = 24, -- 0.8s a 30Hz: enraíza durante o arremesso (duração da animação Habilidade_4)
    range = 56.0,                   -- unidades do mundo (cabe na tela: +-45 na vertical, +-80 na horizontal)
    projectile_speed = 4.0,         -- unidades/tick (14 ticks para alcance máximo a 30Hz)
    projectile_radius = 1.5,        -- raio de colisão da lâmina (1.5 unidade / 12px)
    damage = 400,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 8.0,               -- unidades do mundo (Stun em área no impacto)
    stun_duration_ticks = 36,       -- 1.2 segundos de Stun a 30Hz
    disarm_duration_ticks = 60,     -- 2.0 segundos de Desarme a 30Hz

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

        -- Aplica penalidade temática de Desarme na própria Arya imediatamente no disparo
        local current_tick = CharacterFactory.get_current_tick()
        local disarm_until = current_tick + skill_data.disarm_duration_ticks
        Loci.Commands.set_property(entity_id, "disarmed_until", tostring(disarm_until))

        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"

        -- Dispara entidade Projectile real com sensor CCD
        local proj_id = ProjectileSystem.spawn({
            caster_id = entity_id,
            skill_id = skill_data.id,
            blueprint = "blade_throw",
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
            stun_duration_ticks = skill_data.stun_duration_ticks,
            team = caster_team,
            detonate_on_max_range = true,
        })

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Blade Throw] Projétil %s disparado por %s em (%.1f, %.1f) dir=(%.2f, %.2f) (Arya desarmada por %d ticks)",
                tostring(proj_id), tostring(entity_id), caster_x, caster_y, aim_x, aim_y, skill_data.disarm_duration_ticks
            ))
        end
        return true
    end
}
