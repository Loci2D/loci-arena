-- Sacred Ground Skill Data (Habilidade 3 do Cleric)
-- Cria uma zona sagrada no ponto mirado: aliados dentro do círculo regeneram
-- 80 HP/s e ganham +20 de Defesa Mágica temporária enquanto permanecerem na área.
local TeamUtils = require("core.team_utils")
local ArenaBounds = require("core.arena_bounds")
local ZoneSystem = require("systems.zone_system")

return {
    id = "sacred_ground",
    name = "Solo Sagrado",
    description = "Zona de regeneração: aliados no círculo recuperam 80 HP/s e ganham +20 de Defesa Mágica.",
    mana_cost = 40,
    cooldown = 270,        -- 9.0s a 30Hz
    cast_lock_ticks = 18,  -- 0.6s a 30Hz
    range = 24.0,          -- distância do cleric até o centro da zona
    aoe_radius = 12.0,     -- raio da zona sagrada
    duration_ticks = 120,  -- 4.0s a 30Hz
    tick_interval = 30,    -- pulsos a cada 1s (80 HP por pulso = 80 HP/s)
    heal_per_tick = 80,
    mag_def_bonus = 20,
    buff_refresh_ticks = 30,

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        aim_x, aim_y = TeamUtils.normalize_aim(aim_x, aim_y)

        local cx, cy = TeamUtils.get_entity_xy(entity_id)
        if not cx then return false, "Caster position unavailable" end

        local zx, zy = ArenaBounds.clamp_xy(
            cx + aim_x * skill_data.range,
            cy + aim_y * skill_data.range)

        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"

        ZoneSystem.spawn_zone({
            x = zx,
            y = zy,
            radius = skill_data.aoe_radius,
            team = caster_team,
            affects = "allies",
            duration_ticks = skill_data.duration_ticks,
            tick_interval = skill_data.tick_interval,
            on_tick = function(zone, ids, tick)
                for _, id in ipairs(ids) do
                    TeamUtils.heal(id, skill_data.heal_per_tick)
                    -- +20 Def. Mágica renovada a cada pulso enquanto o aliado
                    -- permanecer na zona (CombatSystem aplica o bônus se ativo).
                    Loci.Commands.set_property(id, "mag_def_bonus", tostring(skill_data.mag_def_bonus))
                    Loci.Commands.set_property(id, "mag_def_bonus_until", tostring(tick + skill_data.buff_refresh_ticks))
                end
            end,
        })

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Sacred Ground] Zona criada por %s em (%.1f, %.1f) r=%.1f",
                tostring(entity_id), zx, zy, skill_data.aoe_radius))
        end
        return true
    end
}
