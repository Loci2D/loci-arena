-- Frost Nova Skill Data (Habilidade 3 / Slot 3 do Mage - DPS Mágico)
-- Onda congelante de autodefesa em 360º centrada no conjurador: dano mágico
-- e Stun curto em todos os inimigos próximos, repelindo quem tenta encurtar distância.
local CombatSystem = require("core.combat_system")
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
    id = "frost_nova",
    name = "Nova de Gelo",
    description = "Onda congelante em 360º ao redor do mago: dano mágico e Stun de 0.6s.",
    mana_cost = 30,
    cooldown = 240, -- 8.0s a 30Hz
    cast_lock_ticks = 9, -- 0.3s a 30Hz: janela da onda expansiva
    range = 0,      -- centrada no conjurador (sem componente de mira)
    damage = 220,
    damage_type = CombatSystem.DamageType.MAGICAL,
    aoe_radius = 14.0,              -- raio da onda congelante em unidades do mundo
    stun_duration_ticks = 18,       -- 0.6 segundos de Stun a 30Hz

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local pos = Loci.get_entity_position(entity_id)
        local caster_x, caster_y = get_coords(pos)

        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"
        local current_tick = CharacterFactory.get_current_tick()
        local stun_until = current_tick + skill_data.stun_duration_ticks

        local nearby = Loci.get_entities_in_radius({ x = caster_x, y = caster_y }, skill_data.aoe_radius)
        local hit_count = 0
        if nearby then
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

        Loci.Log.info(string.format("[Frost Nova] Executada por %s (acertou %d alvos)", tostring(entity_id), hit_count))
        return true
    end
}
