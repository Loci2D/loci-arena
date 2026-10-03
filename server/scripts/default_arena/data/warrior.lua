-- Warrior Character Data
-- Personagem de exemplo com foco em combate corpo-a-corpo
-- Crie novos personagens alterando apenas os valores nesta tabela

return {
    -- Atributos base do personagem
    -- TODO: Atributo Placeholder - substituir pelo Sistema de Atributos definitivo
    attributes = {
        max_hp = 150,
        hp = 150,
        mana = 50,
        max_mana = 50,
        move_speed = 110,
        attack_power = 20,
        defense = 8,
        cooldown_reduction = 0,
        hp_regen = 0.15,
        mana_regen = 0.1
    },
    
    -- Tags que definem comportamentos especiais
    tags = {
        "MELEE",       -- Combatente corpo-a-corpo
        "TANK"         -- Alta resistência
    },
    
    -- Lista de habilidades disponíveis (nomes dos arquivos em data/skills/)
    skills = {
        "slash",
        -- "shield_bash",
        -- "charge"
    }
}
