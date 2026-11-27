-- Gravity Surge Skill Data (Habilidade 3 do Enchanter)
-- Cria um vórtice gravitacional no ponto mirado: puxa inimigos para o centro,
-- causa dano mágico e atordoa brevemente, agrupando-os para os DPSs.
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("systems.character_factory")
local ArenaBounds = require("core.arena_bounds")
local TeamUtils = require("core.team_utils")

return {
    id = "gravity_surge",
    name = "Surto Gravitacional",
    description = "Vórtice que puxa inimigos para o centro, causando dano mágico e Stun.",
    mana_cost = 35,
    cooldown = 240,        -- 8.0s a 30Hz
    cast_lock_ticks = 18,  -- 0.6s a 30Hz
    range = 32.0,          -- distância do enchanter até o centro do vórtice
    aoe_radius = 10.0,     -- raio de efeito do vórtice
    damage = 150,
    damage_type = CombatSystem.DamageType.MAGICAL,
    stun_duration_ticks = 18, -- 0.6s a 30Hz
    pull_speed = 4.0,      -- velocidade máxima de puxão (unidades/tick)
    max_pull_ticks = 18,   -- o puxão nunca excede a duração do stun

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        aim_x, aim_y = TeamUtils.normalize_aim(aim_x, aim_y)

        local cx, cy = TeamUtils.get_entity_xy(entity_id)
        if not cx then return false, "Caster position unavailable" end

        local zx, zy = ArenaBounds.clamp_xy(
            cx + aim_x * skill_data.range,
            cy + aim_y * skill_data.range)

        local current_tick = CharacterFactory.get_current_tick()
        local enemies = TeamUtils.get_enemies(entity_id, zx, zy, skill_data.aoe_radius)

        local hit_count = 0
        for _, target_id in ipairs(enemies) do
            CombatSystem.process_hit(entity_id, target_id, skill_data.damage, skill_data.damage_type)

            local stun_until = current_tick + skill_data.stun_duration_ticks
            Loci.Commands.set_property(target_id, "stunned_until", tostring(stun_until))

            -- Puxão em direção ao centro do vórtice: dash físico de curta duração
            -- garante que a velocidade de puxão não seja sobrescrita pelas intents.
            local tx, ty = TeamUtils.get_entity_xy(target_id)
            if tx then
                local dx, dy = zx - tx, zy - ty
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 0.5 then
                    local pull_ticks = math.min(
                        skill_data.max_pull_ticks,
                        math.max(1, math.ceil(dist / skill_data.pull_speed)))
                    local step = dist / pull_ticks
                    local pvx, pvy = ArenaBounds.project_velocity(
                        tx, ty, (dx / dist) * step, (dy / dist) * step)
                    Loci.Commands.set_property(target_id, "dashing_until", tostring(current_tick + pull_ticks))
                    Loci.Commands.set_velocity(target_id, { x = pvx, y = pvy })
                else
                    Loci.Commands.set_velocity(target_id, { x = 0, y = 0 })
                end
            end

            hit_count = hit_count + 1
        end

        if Loci and Loci.Log then
            Loci.Log.info(string.format(
                "[Gravity Surge] Vórtice de %s em (%.1f, %.1f) r=%.1f (pegou %d inimigos)",
                tostring(entity_id), zx, zy, skill_data.aoe_radius, hit_count))
        end
        return true
    end
}
