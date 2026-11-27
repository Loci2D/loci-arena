-- Magic Missile Skill Data (Habilidade 1 / Slot 1 do Mage - DPS Mágico)
-- Disparo arcano contínuo de médio alcance: projétil direto de dano mágico
-- sem AoE (raio de impacto nulo, atinge apenas o primeiro inimigo).
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
    id = "magic_missile",
    name = "Míssil Arcano",
    description = "Disparo arcano veloz de médio alcance com dano mágico direto.",
    mana_cost = 10,
    cooldown = 18, -- 0.6s a 30Hz
    cast_lock_ticks = 6, -- 0.2s a 30Hz: cadência do disparo básico
    range = 46.0,                   -- unidades do mundo (médio alcance)
    projectile_speed = 4.5,         -- unidades/tick (~10 ticks para alcance máximo a 30Hz)
    projectile_radius = 1.4,        -- raio de colisão do projétil
    damage = 260,
    damage_type = CombatSystem.DamageType.MAGICAL,
    aoe_radius = 0,                 -- sem explosão em área: dano apenas no alvo direto

    on_execute = function(entity_id, aim_x, aim_y, skill_data, opts)
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
            blueprint = "magic_missile",
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
            detonate_on_max_range = false,
            target_id = opts and opts.target_id, -- target-lock: míssil teleguiado ao alvo travado
        })

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Magic Missile] Projetil %s disparado por %s em (%.1f, %.1f) dir=(%.2f, %.2f)",
                tostring(proj_id), tostring(entity_id), caster_x, caster_y, aim_x, aim_y
            ))
        end
        return true
    end
}
