# Sprites dos Personagens (Loci Arena)

Esta pasta contém as texturas e animações de pixel art dos personagens para o cliente Love2D.

---

## Padrão Técnico dos Sprites (Pixelab)
- **Filtragem**: `nearest`, `nearest` (mantém nitidez pura do pixel art sem blur bilinear).
- **Pivô (Origem)**: Pés do personagem, base central inferior (`ox = w / 2`, `oy = h`).
- **Dimensões**: Variam por asset (ex: 44x40 em rotações estáticas, 48x48 / 52x52 em frames de animação). O motor recalcula dinamicamente `ox` e `oy` por frame.
- **Perspectiva**: Low top-down.
- **Taxa de Animação**: ~10–12 FPS (9 frames ≈ 0.8s).

---

## Estrutura Suportada

### 1. Conjunto Animado 8-Direções Completo (Pixelab com `metadata.json` + `anim_map.lua`)
Estrutura padrão recomendada para heróis animados:

```text
client/assets/sprites/<personagem>/   # Sempre em lowercase (ex: arya/)
├── metadata.json                     # Metadados exportados diretamente pelo Pixelab
├── anim_map.lua                      # Mapeamento de skills e estados do jogo para as pastas
├── Rotacao/                          # Rotações estáticas nas 8 direções (idle)
│   └── rotations/
│       ├── south.png
│       ├── east.png
│       └── ...
├── andando/                          # Caminhada nas 8 direções × 9 frames
│   ├── rotations/
│   └── animations/
│       ├── south/frame_000.png ... frame_008.png
│       └── ...
├── correndo/                         # Corrida nas 8 direções × 9 frames
│   ├── rotations/
│   └── animations/...
├── Habilidade_1/                     # Habilidade 1 (ex: slash)
├── Habilidade_2/                     # Habilidade 2 (ex: fury_reward)
├── Habilidade_3/                     # Habilidade 3 (ex: whirlwind_dash)
├── Habilidade_4/                     # Habilidade 4 (ex: blade_throw)
├── aliado_morre/                     # Reação da passiva (choque térmico/emocional)
└── morte/                            # Morte / pose final (one-shot segurando último frame)
    ├── south/frame_000.png ... frame_008.png
    └── ...
```

> **Atenção sobre a estrutura de `morte/`**: Algumas exportações colocam frames diretamente em `<char>/morte/<dir>/frame_XXX.png` (sem subpasta `animations/`). O scanner suporta transparentemente ambas as estruturas.

---

## Formato do `anim_map.lua`

Como os exportadores geram nomes genéricos (ex: `Habilidade_1`, `Habilidade_2`), cada personagem possui seu arquivo `anim_map.lua` mapeando os identificadores lógicos do jogo para as pastas físicas de animação:

```lua
-- client/assets/sprites/<personagem>/anim_map.lua
return {
    character = "arya",
    states = {
        idle = "Rotacao",         -- Estado de repouso
        walk = "andando",         -- Caminhada (< 2.5 unidades de velocidade)
        run = "correndo",         -- Corrida (>= 2.5 unidades de velocidade)
        death = "morte",          -- One-shot ao morrer; segura último frame
        ally_death = "aliado_morre", -- Reação especial (ex: passiva fury_active)
    },
    skills = {
        slash          = "Habilidade_1", -- Ataque básico
        fury_reward    = "Habilidade_2", -- Ataque de fúria
        whirlwind_dash = "Habilidade_3", -- Dash / investida
        blade_throw    = "Habilidade_4", -- Arremesso de arma
        -- Fallbacks numéricos por slot caso skills_list esteja pendente
        [1] = "Habilidade_1",
        [2] = "Habilidade_2",
        [3] = "Habilidade_3",
        [4] = "Habilidade_4",
    },
    -- Seleciona animação específica quando uma pasta contém múltiplos blocos
    preferred_anims = {
        aliado_morre = "ela_caindo_no_chao_chorando",
        morte = "ela_caindo_no_chao_morta_apos_levar_um_golpe_fatal",
    },
    fps = 11,
}
```

---

## Pipeline: Como Adicionar um Novo Personagem

1. **Exportar do Pixelab**:
   - Exporte o pacote do personagem com os estados desejados (idle, walking, running, skills, death).
   - Extraia a pasta em `client/assets/sprites/<nome_personagem>/` (use **letras minúsculas** para a pasta, ex: `warrior`, `mage`).
   - Mantenha o arquivo `metadata.json` na raiz da pasta do personagem.

2. **Criar o `anim_map.lua`**:
   - Crie `client/assets/sprites/<nome_personagem>/anim_map.lua`.
   - Mapeie os nomes de skills definidos no servidor (`server/scripts/default_arena/data/characters/<nome>.lua`) para as pastas correspondentes (`Habilidade_1`, etc.).

3. **Pronto!**:
   - O motor `sprite_anim.lua` detecta e carrega o personagem automaticamente sob demanda (lazy loading).

---

## Resolução de Caminhos e Tolerância a Falhas

1. **Convenção de Nomes e Case**:
   - O servidor envia nomes em lowercase (ex: `"arya"`).
   - O carregador tenta resolver automaticamente variações de case: `lowercase`, `Capitalized` e original, suportando caminhos relativos tanto a partir de `client/` quanto da raiz do repositório.
2. **Lazy Loading e Limite de Cache (LRU)**:
   - Apenas os frames necessários para a animação ativa são carregados na VRAM.
   - O cache de imagens possui limite máximo configurado (512 imagens) com política de descarte LRU (Least Recently Used), prevenindo vazamento de memória.
3. **Cadeia de Fallbacks Estrita**:
   - Frame exato da animação e direção solicitada
   - Direção mais próxima angularmente (tabela de proximidade 8-way)
   - Primeiro frame da direção
   - Rotação estática do estado atual (`rotations/<dir>.png`)
   - Rotação estática de repouso (`Rotacao/rotations/<dir>.png`)
   - Imagem única estática (`assets/sprites/<nome>.png`)
   - Placeholder procedural de 32x32px com visor direcional nas cores da equipe (`me`, `enemy`, `dead`)
