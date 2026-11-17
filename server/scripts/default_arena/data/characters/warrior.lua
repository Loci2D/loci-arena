-- Warrior Character Data
-- Foco em alta resistência física e combate corpo-a-corpo

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
        move_speed = 2.4,  -- Reduzido de 3.0 para melhor precisão em combate
        hp_regen = 15,
        mana_regen = 5
    },
    tags = { "MELEE", "TANK" },
    skills = {
        "slash"
    }
}
