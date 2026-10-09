-- Mage Character Data
-- Foco em dano mágico à distância e controle de área

return {
    name = "Mage",
    role = "mage",
    attributes = {
        max_hp = 4000,
        hp = 4000,
        phys_def = 40,    -- ~28.5% mitigação física
        mag_def = 100,    -- 50.0% mitigação mágica
        mana = 250,
        max_mana = 250,
        move_speed = 3.0,
        hp_regen = 10,
        mana_regen = 15
    },
    tags = { "RANGED", "CASTER" },
    skills = {
        "fireball",  -- Slot 1: Space
        "dash"       -- Slot 2: Double-tap
    }
}
