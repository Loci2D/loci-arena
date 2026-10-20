-- Whirlwind Dash Skill Data (Habilidade 3 da Arya)
-- Investida rápida na direção da mira, girando a espada em 360º e causando dano físico em área.
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

local VISUAL_SCALE = (CombatSystem.CONST and CombatSystem.CONST.VISUAL_SCALE) or 8 -- Escala do cliente (8 pixels = 1 unidade/metro no mundo)

return {
    id = "whirlwind_dash",
    name = "Investida Giratória",
    description = "Avança na direção da mira, desferindo um giro de 360º com dano físico em área.",
    mana_cost = 25,
    cooldown = 180, -- 6 segundos a 30Hz
    range = 160 / VISUAL_SCALE,     -- 20.0 unidades no mundo (160px na tela)
    damage = 450,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 65 / VISUAL_SCALE, -- 8.125 unidades no mundo (65px na tela)

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

        -- Impulso de deslocamento (Dash físico com duração controlada de ~0.30s / 9 ticks a 30Hz)
        local CharacterFactory = require("default_arena.systems.character_factory")
        local current_tick = CharacterFactory.get_current_tick()
        Loci.Commands.set_property(entity_id, "dashing_until", tostring(current_tick + 9))

        local dash_speed = 22.0
        Loci.Commands.set_velocity(entity_id, {
            x = aim_x * dash_speed,
            y = aim_y * dash_speed
        })

        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"
        local hit_ids = {}
        local hit_set = {}

        -- Amostra ao longo de todo o percurso da investida, iniciando em d = 0 (corpo a corpo em 360º)
        -- até o alcance final da investida, garantindo que inimigos colados no jogador não sejam errados.
        local step = math.max(1.0, skill_data.aoe_radius * 0.6)
        local d = 0
        while d < skill_data.range do
            local sample_x = caster_x + aim_x * d
            local sample_y = caster_y + aim_y * d
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

        -- Ponto final do percurso da investida
        local final_x = caster_x + aim_x * skill_data.range
        local final_y = caster_y + aim_y * skill_data.range
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
        for _, target_id in ipairs(hit_ids) do
            local target_team = Loci.get_entity_property(target_id, "team") or "2"
            if target_team ~= caster_team then
                CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type)
                hit_count = hit_count + 1
            end
        end

        Loci.Log.info(string.format("[Whirlwind Dash] Executado por %s (acertou %d alvos)", tostring(entity_id), hit_count))
        return true
    end
}
