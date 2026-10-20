-- Fury Reward Skill Data
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
    id = "fury_reward",
    name = "Recompensa da Fúria",
    description = "Golpe físico devastador de médio alcance, ativado após um aliado morrer.",
    mana_cost = 0,
    cooldown = 0, -- Ooldown é gerido pela passiva (requer aliado morrer)
    range = 120 / VISUAL_SCALE,     -- 15.0 unidades no mundo (120px na tela)
    damage = 500,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 50 / VISUAL_SCALE, -- 6.25 unidades no mundo (50px na tela)

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        -- Check if Fury is active
        local is_fury = Loci.get_entity_property(entity_id, "fury_active") == "true"
        if not is_fury then
            return false, "Habilidade bloqueada. Um aliado precisa morrer para ativar."
        end

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
        local hit_ids = {}
        local hit_set = {}

        -- Testar na área corpo-a-corpo e no ponto focal de impacto da onda de choque
        local test_points = {
            { x = caster_x + aim_x * (skill_data.range * 0.2), y = caster_y + aim_y * (skill_data.range * 0.2) },
            { x = caster_x + aim_x * (skill_data.range * 0.5), y = caster_y + aim_y * (skill_data.range * 0.5) }
        }

        for _, pt in ipairs(test_points) do
            local nearby = Loci.get_entities_in_radius(pt, skill_data.aoe_radius)
            if nearby then
                for _, target_id in ipairs(nearby) do
                    if target_id ~= entity_id and not hit_set[target_id] then
                        hit_set[target_id] = true
                        table.insert(hit_ids, target_id)
                    end
                end
            end
        end

        local hit_count = 0
        for _, target_id in ipairs(hit_ids) do
            local target_team = Loci.get_entity_property(target_id, "team") or "2"
            if target_team ~= caster_team then
                -- Força o critico pelo golpe devastador impulsionado por fúria
                CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type, true)
                hit_count = hit_count + 1
            end
        end

        -- Desativa a fúria após o uso
        Loci.Commands.set_property(entity_id, "fury_active", "false")

        Loci.Log.info(string.format("[Fury Reward] Executado por %s (acertou %d alvos)", tostring(entity_id), hit_count))
        return true
    end
}
