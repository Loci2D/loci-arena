-- Archer Character Data
-- DPS Físico à distância, focado em alta cadência de tiro e mobilidade (kiting)

return {
    name = "Archer",
    title = "Caçador Veloz",
    role = "marksman",
    attributes = {
        max_hp = 3800,
        hp = 3800,
        phys_def = 40,    -- ~28.5% mitigação física
        mag_def = 40,     -- ~28.5% mitigação mágica
        mana = 120,
        max_mana = 120,
        move_speed = 2.1, -- Alta velocidade para kiting
        hp_regen = 10,
        mana_regen = 10
    },
    tags = { "RANGED", "DPS", "PHYSICAL" },
    skills = {
        "quick_shot"
    }
}
