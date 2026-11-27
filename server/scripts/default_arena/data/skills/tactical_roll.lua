-- Tactical Roll Skill Data
-- Rolamento de mobilidade/reposicionamento para kiting
local CombatSystem = require("core.combat_system")
local ArenaBounds = require("core.arena_bounds")

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
    id = "tactical_roll",
    name = "Tactical Roll",
    description = "Rolamento tático em direção da mira para reposicionamento",
    mana_cost = 15,
    cooldown = 60, -- 2.0s a 30Hz
    range = 20.0,     -- unidades do mundo (~2.5 alturas de personagem)
    roll_speed = 20.0 / 6, -- ~3.33 unidades/tick (desloca 20.0 unidades em 6 ticks)
    roll_duration_ticks = 6, -- 0.2s de rolamento
    iframe_duration_ticks = 3, -- 0.1s de invencibilidade durante o rolamento

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
        caster_x, caster_y = ArenaBounds.clamp_xy(caster_x, caster_y)

        local CharacterFactory = require("systems.character_factory")
        local current_tick = CharacterFactory.get_current_tick()

        -- Aplicar velocidade de rolamento com clamping da arena
        local proj_vx, proj_vy = ArenaBounds.project_velocity(caster_x, caster_y, aim_x * skill_data.roll_speed, aim_y * skill_data.roll_speed)
        Loci.Commands.set_velocity(entity_id, {
            x = proj_vx,
            y = proj_vy
        })

        -- Aplicar iframe (invencibilidade)
        local iframe_until = current_tick + skill_data.iframe_duration_ticks
        Loci.Commands.set_property(entity_id, "iframe_until", tostring(iframe_until))

        -- Aplicar dashing state para resetar velocidade após duração
        local roll_duration_ticks = skill_data.roll_duration_ticks or 6
        Loci.Commands.set_property(entity_id, "dashing_until", tostring(current_tick + roll_duration_ticks))

        Loci.Log.info(string.format("[Tactical Roll] Executado por %s", tostring(entity_id)))
        return true
    end
}
