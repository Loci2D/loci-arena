-- Mapeamento de animações e skills para Arya
-- Usado pelo motor genérico sprite_anim.lua

return {
    character = "arya",
    states = {
        idle = "Rotacao",
        walk = "andando",
        run = "correndo",
        death = "morte",
        ally_death = "aliado_morre",
    },
    skills = {
        slash = "Habilidade_1",
        fury_reward = "Habilidade_2",
        whirlwind_dash = "Habilidade_3",
        blade_throw = "Habilidade_4",
        -- Fallback por slot numérico (1 a 4)
        [1] = "Habilidade_1",
        [2] = "Habilidade_2",
        [3] = "Habilidade_3",
        [4] = "Habilidade_4",
    },
    -- Nomes de animações preferidas caso o estado contenha múltiplos blocos de animação
    preferred_anims = {
        aliado_morre = "ela_caindo_no_chao_chorando",
        morte = "ela_caindo_no_chao_morta_apos_levar_um_golpe_fatal",
    },
    fps = 11,
}

