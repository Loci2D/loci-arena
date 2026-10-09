-- Default Arena Character Data
-- Atributos padrão equilibrados para arena 3v3

return {
    name = "Default",
    role = "fighter",
    attributes = {
        max_hp = 5000,
        hp = 5000,
        phys_def = 80,    -- ~44.4% mitigação física
        mag_def = 60,     -- ~37.5% mitigação mágica
        mana = 150,
        max_mana = 150,
        move_speed = 3.0,
        hp_regen = 10,
        mana_regen = 10
    },
    tags = { "BALANCED" },
    skills = {
        "slash",  -- Slot 1: Space
        "dash"    -- Slot 2: Double-tap
    }
}
