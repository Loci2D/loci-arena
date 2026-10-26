-- Shield Skill Data
-- Habilidade defensiva que cria um escudo temporário absorvendo dano
local CharacterFactory = require("default_arena.systems.character_factory")

return {
    id = "shield",
    name = "Shield",
    description = "Cria um escudo que absorve 500 de dano por 5 segundos",
    mana_cost = 20,
    cooldown = 300, -- 10 segundos a 30Hz

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local shield_amount = 1000 -- Absorve 1000 de dano (2 hits de 350)
        local shield_duration = 5 -- 5 segundos
        local current_tick = CharacterFactory.get_current_tick() or 0
        local shield_end_tick = current_tick + (shield_duration * 30) -- 30 ticks por segundo

        Loci.Commands.set_property(entity_id, "shield", tostring(shield_amount))
        Loci.Commands.set_property(entity_id, "shield_active", "1")
        Loci.Commands.set_property(entity_id, "shield_end_tick", tostring(shield_end_tick))

        Loci.Log.info(string.format("[Shield] Escudo ativado para %s (absorção: %d, até tick: %d)", 
            tostring(entity_id), shield_amount, shield_end_tick))
        
        return true
    end
}
