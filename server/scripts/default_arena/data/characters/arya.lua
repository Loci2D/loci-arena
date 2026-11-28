-- Arya Character Data
-- Lutadora ágil e agressiva, focada em combate corpo-a-corpo e mobilidade

return {
    name = "Arya",
    title = "Lutadora Ágil",
    role = "fighter",
    attributes = {
        max_hp = 5000,
        hp = 5000,
        phys_def = 85,    -- Defesa física moderada de lutadora (~45.9% mitigação)
        mag_def = 55,     -- Defesa mágica balanceada (~35.5% mitigação)
        mana = 100,
        max_mana = 100,
        move_speed = 2.2, -- Alta mobilidade e velocidade ágil
        hp_regen = 12,    -- Regeneração moderada
        mana_regen = 10
    },
    tags = { "MELEE", "FIGHTER" },
    skills = {
        "slash",          -- Habilidade 1 (Ataque Básico)
        "fury_reward",    -- Habilidade 2 (Ataque Especial / Fúria)
        "whirlwind_dash", -- Habilidade 3 (Investida Giratória 360º)
        "blade_throw"     -- Habilidade 4 (Arremesso com Stun e Desarme)
    }
}
