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
    -- Sequências compostas por múltiplos blocos de animação em ordem
    sequences = {
        aliado_morre = {
            "ela_caindo_no_chao_chorando",
            "apos_isso_ela_pega_sua_espada_devolta_e_acende_uma",
        },
    },
    -- Duração total fixa em segundos para estados específicos (ex: 3.0s de paralisia)
    state_durations = {
        aliado_morre = 3.0,
    },
    fps = 11,
}

