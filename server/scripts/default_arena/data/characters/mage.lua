-- Mage Character Data
-- Foco em dano mágico à distância e controle de área (DPS Mágico do roster 3v3)

return {
    name = "Mage",
    role = "mage",
    attributes = {
        max_hp = 4000,
        hp = 4000,
        phys_def = 40,    -- ~28.5% mitigação física
        mag_def = 90,     -- ~47.4% mitigação mágica
        mana = 250,
        max_mana = 250,
        move_speed = 2.0,
        hp_regen = 10,
        mana_regen = 15
    },
    tags = { "RANGED", "DPS", "MAGICAL" },
    skills = {
        "magic_missile",   -- Habilidade 1: Ataque Básico (disparo arcano)
        "fireball",        -- Habilidade 2: Habilidade Tática (projétil explosivo)
        "frost_nova",      -- Habilidade 3: Onda congelante 360º de autodefesa
        "meteor_strike"    -- Habilidade 4: Ultimate (meteoro com aviso visual)
    }
}
