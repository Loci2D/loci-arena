-- Arrow Rain Skill Data
-- Chuva de flechas em área contínua com lentidão
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
    id = "arrow_rain",
    name = "Arrow Rain",
    description = "Chuva de flechas em área contínua com lentidão",
    mana_cost = 50,
    cooldown = 120, -- 4.0s a 30Hz
    range = 40.0,     -- unidades do mundo (~5 alturas de personagem)
    damage = 150,     -- dano por tick
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 15.0, -- unidades do mundo
    duration_ticks = 30, -- 1.0s de duração
    slow_duration_ticks = 60, -- 2.0s de lentidão
    slow_factor = 0.5,   -- 50% de redução de velocidade

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
        local CharacterFactory = require("systems.character_factory")
        local current_tick = CharacterFactory.get_current_tick()

        -- Ponto central da área de efeito
        local target_x = caster_x + aim_x * skill_data.range
        local target_y = caster_y + aim_y * skill_data.range

        -- Aplicar lentidão a todos os inimigos na área
        local nearby = Loci.get_entities_in_radius({ x = target_x, y = target_y }, skill_data.aoe_radius)
        local hit_count = 0
        if nearby then
            for _, target_id in ipairs(nearby) do
                if target_id ~= entity_id then
                    local target_team = Loci.get_entity_property(target_id, "team") or "2"
                    if target_team ~= caster_team then
                        -- Aplicar lentidão
                        local slow_until = current_tick + skill_data.slow_duration_ticks
                        Loci.Commands.set_property(target_id, "slowed_until", tostring(slow_until))
                        Loci.Commands.set_property(target_id, "slow_factor", tostring(skill_data.slow_factor))
                        hit_count = hit_count + 1
                    end
                end
            end
        end

        -- Marcar o jogador como canalizando (não pode se mover durante a chuva)
        local channeling_until = current_tick + skill_data.duration_ticks
        Loci.Commands.set_property(entity_id, "channeling_until", tostring(channeling_until))
        Loci.Commands.set_property(entity_id, "channeling_skill", "arrow_rain")

        Loci.Log.info(string.format("[Arrow Rain] Executado por %s (área em %.1f, %.1f, %d alvos lentos)",
            tostring(entity_id), target_x, target_y, hit_count))
        return true
    end
}
