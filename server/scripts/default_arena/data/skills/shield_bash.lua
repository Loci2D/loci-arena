-- Shield Bash Skill Data (Habilidade 2 / Slot 2 do Warrior - Tank)
-- Avanço curto com o escudo na direção da mira, causando dano físico e
-- atordoando (Stun) alvos inimigos no percurso por 0.8s, cancelando conjurações ativas.
local CombatSystem = require("core.combat_system")
local ArenaBounds = require("core.arena_bounds")
local CharacterFactory = require("systems.character_factory")

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
    id = "shield_bash",
    name = "Golpe de Escudo",
    description = "Avança com o escudo, causando dano físico e Stun frontal de 0.8s que cancela conjurações.",
    mana_cost = 25,
    cooldown = 210, -- 7.0s a 30Hz
    range = 14.0,                   -- unidades do mundo (avanço curto corpo a corpo)
    dash_duration_ticks = 4,        -- 0.13s a 30Hz
    dash_speed = 14.0 / 4,          -- 3.5 unidades/tick (desloca 14.0 unidades em 4 ticks)
    damage = 280,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 6.0,               -- cone frontal ao longo do avanço
    stun_duration_ticks = 24,       -- 0.8 segundos de Stun a 30Hz

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

        -- Impulso de avanço (dash físico sincronizado com o alcance da habilidade)
        local current_tick = CharacterFactory.get_current_tick()
        local dash_duration_ticks = skill_data.dash_duration_ticks or 4
        Loci.Commands.set_property(entity_id, "dashing_until", tostring(current_tick + dash_duration_ticks))
        -- O avanço é mobilidade: cancela o cast lock de uma conjuração anterior.
        Loci.Commands.set_property(entity_id, "casting_until", "0")

        local dash_speed = skill_data.dash_speed or (skill_data.range / dash_duration_ticks)
        local proj_vx, proj_vy = ArenaBounds.project_velocity(caster_x, caster_y, aim_x * dash_speed, aim_y * dash_speed)
        Loci.Commands.set_velocity(entity_id, {
            x = proj_vx,
            y = proj_vy
        })

        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"
        local hit_ids = {}
        local hit_set = {}

        -- Amostra o cone frontal ao longo de todo o percurso do avanço
        local step = math.max(1.0, skill_data.aoe_radius * 0.6)
        local d = 0
        while d < skill_data.range do
            local sample_x, sample_y = ArenaBounds.clamp_xy(caster_x + aim_x * d, caster_y + aim_y * d)
            local nearby = Loci.get_entities_in_radius({ x = sample_x, y = sample_y }, skill_data.aoe_radius)
            if nearby then
                for _, target_id in ipairs(nearby) do
                    if target_id ~= entity_id and not hit_set[target_id] then
                        hit_set[target_id] = true
                        table.insert(hit_ids, target_id)
                    end
                end
            end
            d = d + step
        end

        -- Ponto final do avanço
        local final_x, final_y = ArenaBounds.clamp_xy(caster_x + aim_x * skill_data.range, caster_y + aim_y * skill_data.range)
        local final_nearby = Loci.get_entities_in_radius({ x = final_x, y = final_y }, skill_data.aoe_radius)
        if final_nearby then
            for _, target_id in ipairs(final_nearby) do
                if target_id ~= entity_id and not hit_set[target_id] then
                    hit_set[target_id] = true
                    table.insert(hit_ids, target_id)
                end
            end
        end

        local hit_count = 0
        local stun_until = current_tick + skill_data.stun_duration_ticks
        for _, target_id in ipairs(hit_ids) do
            local target_team = Loci.get_entity_property(target_id, "team") or "2"
            if target_team ~= caster_team then
                CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type)
                -- Stun frontal: imobiliza e cancela conjurações ativas do alvo
                Loci.Commands.set_property(target_id, "stunned_until", tostring(stun_until))
                Loci.Commands.set_property(target_id, "casting_until", "0")
                Loci.Commands.set_velocity(target_id, { x = 0, y = 0 })
                hit_count = hit_count + 1
            end
        end

        Loci.Log.info(string.format("[Shield Bash] Executado por %s (acertou %d alvos)", tostring(entity_id), hit_count))
        return true
    end
}
