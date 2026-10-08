-- Blade Throw Skill Data (Habilidade 4 / Ultimate da Arya)
-- Arremessa a espada na direção visada. Causa dano físico e atordoamento (Stun) em área no impacto,
-- mas deixa Arya desarmada (impedida de usar habilidades) por 2.0s.
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
    id = "blade_throw",
    name = "Arremesso de Lâmina",
    description = "Arremessa a espada. Causa dano físico e Stun em área no impacto, mas aplica Desarme na Arya por 2.0s.",
    mana_cost = 45,
    cooldown = 420, -- 14 segundos a 30Hz
    range = 260,
    damage = 400,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 55,
    stun_duration_ticks = 36,   -- 1.2 segundos de Stun a 30Hz
    disarm_duration_ticks = 60, -- 2.0 segundos de Desarme a 30Hz

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

        -- Ponto de impacto no alcance máximo
        local target_x = caster_x + aim_x * skill_data.range
        local target_y = caster_y + aim_y * skill_data.range

        -- Aplica penalidade temática de Desarme na própria Arya
        local CharacterFactory = require("default_arena.systems.character_factory")
        local current_tick = CharacterFactory.get_current_tick()
        local disarm_until = current_tick + skill_data.disarm_duration_ticks
        Loci.Commands.set_property(entity_id, "disarmed_until", tostring(disarm_until))

        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"
        local hit_ids = Loci.get_entities_in_radius({ x = target_x, y = target_y }, skill_data.aoe_radius)

        local hit_count = 0
        if hit_ids then
            for _, target_id in ipairs(hit_ids) do
                if target_id ~= entity_id then
                    local target_team = Loci.get_entity_property(target_id, "team") or "2"
                    if target_team ~= caster_team then
                        -- Aplica dano
                        CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type)
                        
                        -- Aplica Stun no alvo atingido
                        local stun_until = current_tick + skill_data.stun_duration_ticks
                        Loci.Commands.set_property(target_id, "stunned_until", tostring(stun_until))
                        Loci.Commands.set_velocity(target_id, { x = 0, y = 0 })

                        hit_count = hit_count + 1
                    end
                end
            end
        end

        Loci.Log.info(string.format("[Blade Throw] Executado por %s (acertou %d alvos, Arya desarmada por %d ticks)",
            tostring(entity_id), hit_count, skill_data.disarm_duration_ticks))
        return true
    end
}
