-- Mage Character Data
-- Personagem de exemplo com foco em magia
-- Crie novos personagens alterando apenas os valores nesta tabela

return {
    -- Atributos base do personagem
    -- TODO: Atributo Placeholder - substituir pelo Sistema de Atributos definitivo
    attributes = {
        max_hp = 80,
        hp = 80,
        mana = 150,
        max_mana = 150,
        move_speed = 100,
        attack_power = 5,
        defense = 2,
        cooldown_reduction = 0,
        hp_regen = 0.05,
        mana_regen = 0.5
    },
    
    -- Tags que definem comportamentos especiais
    tags = {
        -- "RANGED",      -- Atacante à distância
        -- "SQUISHY",     -- Alta vulnerabilidade
        -- "MAGIC_USER"   -- Usa magia
    },
    
    -- Lista de habilidades disponíveis (nomes dos arquivos em data/skills/)
    skills = {
        "fireball",
        -- "ice_spike",
        -- "teleport"
    }
}
