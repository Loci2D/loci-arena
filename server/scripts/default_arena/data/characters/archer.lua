-- Archer Character Data
-- DPS Físico / Marksman - Atirador de longo alcance com kiting

return {
    name = "archer",
    title = "Marksman",
    role = "dps",
    attributes = {
        max_hp = 3500,
        hp = 3500,
        phys_def = 60,    -- Baixa defesa física (frágil)
        mag_def = 40,
        mana = 120,
        max_mana = 120,
        move_speed = 2.4, -- Alta mobilidade para kiting
        hp_regen = 15,
        mana_regen = 12
    },
    tags = { "RANGED", "DPS", "MARKSMAN" },
    skills = {
        "slash",           -- Habilidade 1 (Space) - Ataque Básico com espada curta
        "quick_shot",      -- Habilidade 2 (Q) - Disparo Rápido Básico
        "piercing_arrow",  -- Habilidade 3 (E) - Flecha Perfurante com Fragile
        "tactical_roll",   -- Habilidade 4 (R) - Rolamento Tático
        "arrow_rain"       -- Habilidade 5 (F) - Chuva de Flechas com Slow
    }
}
