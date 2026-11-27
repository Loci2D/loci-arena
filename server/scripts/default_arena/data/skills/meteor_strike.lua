-- Meteor Strike Skill Data (Habilidade 4 / Slot 4 Ultimate do Mage - DPS Mágico)
-- Invoca um meteoro no ponto mirado: após 0.8s de aviso visual, o impacto
-- em área causa dano mágico massivo.
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
    id = "meteor_strike",
    name = "Meteoro Arcano",
    description = "Invoca um meteoro colossal no ponto mirado após 0.8s de aviso, causando dano mágico em área.",
    mana_cost = 65,
    cooldown = 480, -- 16.0s a 30Hz
    cast_lock_ticks = 24, -- 0.8s a 30Hz: conjuração durante a queda do meteoro
    range = 56.0,                   -- distância do ponto de impacto em unidades do mundo
    damage = 750,
    damage_type = CombatSystem.DamageType.MAGICAL,
    aoe_radius = 18.0,              -- raio da explosão do meteoro em unidades do mundo
    impact_delay_ticks = 24,        -- 0.8s de aviso visual antes do impacto (24 ticks a 30Hz)

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

        -- Ponto de impacto do meteoro (clampado aos limites seguros da arena)
        local target_x, target_y = ArenaBounds.clamp_xy(
            caster_x + aim_x * skill_data.range,
            caster_y + aim_y * skill_data.range
        )

        local current_tick = CharacterFactory.get_current_tick()
        local impact_tick = current_tick + (skill_data.impact_delay_ticks or 24)
        local caster_team = Loci.get_entity_property(entity_id, "team") or "1"

        -- O meteoro cai mesmo se o conjurador morrer ou se mover durante o aviso
        DelayedCasts.schedule(impact_tick, function()
            local nearby = Loci.get_entities_in_radius({ x = target_x, y = target_y }, skill_data.aoe_radius)
            local hit_count = 0
            if nearby then
                for _, target_id in ipairs(nearby) do
                    if target_id ~= entity_id then
                        local target_team = Loci.get_entity_property(target_id, "team") or "2"
                        if target_team ~= caster_team then
                            CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type)
                            hit_count = hit_count + 1
                        end
                    end
                end
            end
            Loci.Log.info(string.format(
                "[Meteor Strike] Impacto de %s em (%.1f, %.1f) (acertou %d alvos)",
                tostring(entity_id), target_x, target_y, hit_count
            ))
        end)

        return true
    end
}
