-- Enchanter Character Data
-- Suporte de utilidade focado em escudos de absorção e controle de grupo

return {
    name = "Enchanter",
    title = "Guardião Tático",
    role = "support",
    attributes = {
        max_hp = 4600,
        hp = 4600,
        phys_def = 60,    -- ~37.5% mitigação física
        mag_def = 60,     -- ~37.5% mitigação mágica
        mana = 180,
        max_mana = 180,
        move_speed = 2.05,
        hp_regen = 10,
        mana_regen = 12
    },
    tags = { "SUPPORT", "UTILITY" },
    skills = {
        "kinetic_pulse",   -- Habilidade 1: kinetic_pulse (pulso cinético básico)
        "aegis_barrier",   -- Habilidade 2: aegis_barrier (escudo protetor em aliado)
        "gravity_surge",   -- Habilidade 3: gravity_surge (vórtice gravitacional de puxão e stun)
        "bastion_overload" -- Habilidade 4: bastion_overload (ultimate de cúpula com escudo de grupo e aceleração)
    }
}
