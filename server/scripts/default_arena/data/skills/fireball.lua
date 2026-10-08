-- Fireball Skill Data
-- Projétil explosivo de dano mágico em área
local CombatSystem = require("core.combat_system")
local ProjectileSystem = require("default_arena.projectile_system")

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
    id = "fireball",
    name = "Fireball",
    description = "Bola de fogo explosiva com dano mágico em área",
    mana_cost = 35,
    cooldown = 0, -- Sem cooldown para testes
    range = 300,
    damage = 500,
    damage_type = CombatSystem.DamageType.MAGICAL,
    aoe_radius = 60,

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local pos = Loci.get_entity_position(entity_id)
        local caster_x, caster_y = get_coords(pos)

        -- Spawna projétil que viaja no tempo
        -- Velocidade: 8 unidades por tick (240 unidades/s a 30Hz)
        -- Distância máxima: 300 unidades
        ProjectileSystem.spawn(
            entity_id,
            caster_x,
            caster_y,
            aim_x,
            aim_y,
            8.0,           -- speed
            skill_data.damage,
            skill_data.damage_type,
            skill_data.range,
            skill_data.aoe_radius
        )

        return true
    end
}
