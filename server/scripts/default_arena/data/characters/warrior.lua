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
        mana = 9999,      -- Praticamente infinito para testes
        max_mana = 9999,
        move_speed = 3.0,
        hp_regen = 15,
        mana_regen = 5
    },
    tags = { "MELEE", "TANK" },
    skills = {
        "slash",     -- Slot 1: Space
        "dash",      -- Slot 2: Double-tap
        "fireball"   -- Slot 3: Q (para teste)
    }
}
