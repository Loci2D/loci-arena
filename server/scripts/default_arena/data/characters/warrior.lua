-- Warrior Character Data
-- Foco em alta resistência física e combate corpo-a-corpo (Tank do roster 3v3)

return {
    name = "Warrior",
    role = "tank",
    attributes = {
        max_hp = 6000,
        hp = 6000,
        phys_def = 120,   -- ~54.5% mitigação física
        mag_def = 40,     -- ~28.5% mitigação mágica
        mana = 100,
        max_mana = 100,
        move_speed = 1.9,
        hp_regen = 15,
        mana_regen = 5
    },
    tags = { "MELEE", "TANK" },
    skills = {
        "slash",            -- Habilidade 1: Ataque Básico
        "shield_bash",      -- Habilidade 2: Avanço com Stun frontal
        "shield",           -- Habilidade 3: Escudo de absorção (auto-buff)
        "earthquake_slam"   -- Habilidade 4: Ultimate de impacto em área
    }
}
