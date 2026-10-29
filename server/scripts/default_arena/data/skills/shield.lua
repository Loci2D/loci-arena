-- Shield Skill Data (Placeholder)
-- Habilidade defensiva genérica que cria um escudo temporário absorvendo dano
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("default_arena.systems.character_factory")

return {
    id = "shield",
    name = "Shield",
    description = "Cria um escudo temporário que absorve até 1000 de dano por 5 segundos",
    mana_cost = 20,
    cooldown = 300, -- 10 segundos a 30Hz

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local shield_amount = 1000 -- Absorve até 1000 de dano
        local duration_ticks = 150 -- 5 segundos a 30Hz (5 * 30)
        local current_tick = CharacterFactory.get_current_tick() or 0

        CombatSystem.apply_shield(entity_id, shield_amount, duration_ticks, current_tick)
        return true
    end
}
