-- Cleric Character Data
-- Suporte focado em cura, sustentação de vida e proteção de equipe

return {
    name = "Cleric",
    title = "Sacerdote da Luz",
    role = "healer",
    attributes = {
        max_hp = 4400,
        hp = 4400,
        phys_def = 55,    -- ~35.5% mitigação física
        mag_def = 65,     -- ~39.4% mitigação mágica
        mana = 200,
        max_mana = 200,
        move_speed = 2.0,
        hp_regen = 12,
        mana_regen = 15
    },
    tags = { "SUPPORT", "HEALER" },
    skills = {
        "smite"
    }
}
