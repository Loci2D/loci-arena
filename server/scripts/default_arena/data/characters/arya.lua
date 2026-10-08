-- Arya Character Data
-- Guerreira gentil, focada em defesa e proteção

return {
    name = "Arya",
    title = "Guerreira Gentil",
    role = "tank",
    attributes = {
        max_hp = 5500,
        hp = 5500,
        phys_def = 130,   -- Alta defesa física
        mag_def = 50,
        mana = 100,
        max_mana = 100,
        move_speed = 3.2,
        hp_regen = 20,
        mana_regen = 10
    },
    tags = { "MELEE", "TANK", "PROTECTOR" },
    skills = {
        "slash",        -- Habilidade 1 (Ataque Básico)
        "fury_reward"   -- Habilidade 2 (Ataque Especial)
    }
}
