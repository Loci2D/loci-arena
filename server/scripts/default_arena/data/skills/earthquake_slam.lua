-- Earthquake Slam Skill Data (Habilidade 4 / Slot 4 Ultimate do Warrior - Tank)
-- Salto na direção da mira seguido de impacto no chão em área: dano físico
-- e Stun em área por 1.2s no ponto de aterrissagem.
local CombatSystem = require("core.combat_system")
local ArenaBounds = require("core.arena_bounds")
local CharacterFactory = require("systems.character_factory")
local DelayedCasts = require("systems.delayed_casts")

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
    id = "earthquake_slam",
    name = "Slam Sísmico",
    description = "Salta até o ponto mirado e esmaga o chão: dano físico e Stun em área por 1.2s.",
    mana_cost = 50,
    cooldown = 450, -- 15.0s a 30Hz
    range = 28.0,                   -- distância do salto em unidades do mundo
    dash_duration_ticks = 8,        -- 0.27s de ar até a aterrissagem
    damage = 550,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 14.0,              -- raio do impacto no ponto de aterrissagem
    stun_duration_ticks = 36,       -- 1.2 segundos de Stun a 30Hz

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
        caster_x, caster_y = ArenaBounds.clamp_xy(caster_x, caster_y)

        local current_tick = CharacterFactory.get_current_tick()
        local dash_duration_ticks = skill_data.dash_duration_ticks or 8

        -- Ponto de aterrissagem (clampado aos limites seguros da arena)
        local land_x, land_y = ArenaBounds.clamp_xy(
            caster_x + aim_x * skill_data.range,
            caster_y + aim_y * skill_data.range
        )

        -- Impulso do salto: mobilidade via dashing_until, sem cast lock
        Loci.Commands.set_property(entity_id, "dashing_until", tostring(current_tick + dash_duration_ticks))
        Loci.Commands.set_property(entity_id, "casting_until", "0")

        local dash_speed = skill_data.range / dash_duration_ticks
        local proj_vx, proj_vy = ArenaBounds.project_velocity(caster_x, caster_y, aim_x * dash_speed, aim_y * dash_speed)
        Loci.Commands.set_velocity(entity_id, {
            x = proj_vx,
            y = proj_vy
        })

        -- Impacto do slam no tick de aterrissagem, resolvido de forma autoritativa
        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"
        DelayedCasts.schedule(current_tick + dash_duration_ticks, function()
            local nearby = Loci.get_entities_in_radius({ x = land_x, y = land_y }, skill_data.aoe_radius)
            local hit_count = 0
            if nearby then
                local stun_until = current_tick + dash_duration_ticks + skill_data.stun_duration_ticks
                for _, target_id in ipairs(nearby) do
                    if target_id ~= entity_id then
                        local target_team = Loci.get_entity_property(target_id, "team") or "2"
                        if target_team ~= caster_team then
                            CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type)
                            Loci.Commands.set_property(target_id, "stunned_until", tostring(stun_until))
                            Loci.Commands.set_property(target_id, "casting_until", "0")
                            Loci.Commands.set_velocity(target_id, { x = 0, y = 0 })
                            hit_count = hit_count + 1
                        end
                    end
                end
            end
            Loci.Log.info(string.format(
                "[Earthquake Slam] Impacto de %s em (%.1f, %.1f) (acertou %d alvos)",
                tostring(entity_id), land_x, land_y, hit_count
            ))
        end)

        return true
    end
}
