# Convenção Única de Escala, Pivô e Hitboxes — Loci Arena

> **Referência técnica:** Card [#93](https://trello.com/c/NbgRmWUF) · Complementa o PR #67 (`feat/skill-range-calibration`) e o PR #76 (`fix/virtual-controls-cooldown-aim-facing`).

---

## 1. Problema Investigado

Em investigações iniciais sobre o alcance percebido das habilidades, compararam-se as constantes físicas do servidor (`PLAYER_COLLIDER_RADIUS = 2.0`), a escala visual do cliente (`VISUAL_SCALE = 8`, `SPRITE_BASE_SIZE = 32`, `SPRITE_SCALE = 2`) e a geometria de detecção das skills:

1. **Proporção física vs. visual**: `2.0u` de raio no servidor equivalem a `16px` de raio (`32px` de diâmetro), enquanto o sprite renderizado com `SPRITE_SCALE = 2` tem `64px` de altura base (`8.0u`) — ou seja, altura visual 2× maior que o diâmetro do colisor circular.
2. **Desalinhamento de pivô**: no servidor, `(ent.x, ent.y)` é o centro do colisor circular no chão (ancorado nos **pés** pelo cliente). Entretanto, o indicador de mira no chão em `client/main.lua` iniciava em `y - 32px` (centro visual do corpo) e usava `1.0 * range` mesmo para skills com impacto em fração do alcance (ex.: `fireball` em `0.7 * range`).
3. **Ausência de inspeção visual**: o modo debug (`F3`) exibia apenas telemetria textual, dificultando a comparação visual entre colisor físico, caixa do sprite, pivô e círculos de detecção das skills.

---

## 2. Decisão Técnica: Convenção Única de Escala (Perspectiva 2.5D)

Mantemos o colisor físico travado à engine `loci2d` (`MapBounds::default_arena()`) e formalizamos a separação entre **plano do chão (física/hitboxes)** e **altura visual em perspectiva 2.5D**:

| Constante | Valor Canônico | Equivalente em Pixels / Mundo | Fonte da Verdade |
| :--- | :---: | :--- | :--- |
| `VISUAL_SCALE` | `8` | `1.0u = 8 px` (`1280×720` = `160×90u`) | `SkillRanges.SCALE.VISUAL_SCALE`, `CombatSystem.CONST.VISUAL_SCALE` |
| `PLAYER_COLLIDER_RADIUS` | `2.0u` | `16 px` de raio (`32 px` de diâmetro); `SAFE_MIN/MAX = ±498` | `ArenaBounds.PLAYER_COLLIDER_RADIUS`, `SkillRanges.SCALE.PLAYER_COLLIDER_RADIUS` |
| `MIN_COLLISION_DIST` | `4.05u` | `32.4 px` entre centros (`PLAYER_DIAMETER + 0.05`) | `server/scripts/default_arena/main.lua` |
| `SPRITE_BASE_SIZE` | `32 px` | Base lógica do modelo/placeholder | `SkillRanges.SCALE.SPRITE_BASE_SIZE` |
| `SPRITE_SCALE` | `2` | `64 px` (`8.0u`) de altura visual de referência | `SkillRanges.SCALE.SPRITE_SCALE` |
| `BODY_CENTER_OFFSET_U` | `4.0u` | `32 px` acima do pivô dos pés (`(32 * 2) / 2`) | `SkillRanges.SCALE.BODY_CENTER_OFFSET_U` |
| Velocidade base (`SPEED`) | `2.0 u/tick` | `60 u/s` a `30 Hz` (`480 px/s` = `7.5` alturas/s) | `server/scripts/default_arena/main.lua`, `loci.netcode.default_move_speed` |

### Por que manter `PLAYER_COLLIDER_RADIUS = 2.0` e `SPRITE_SCALE = 2`?

- **Compatibilidade com a engine `loci2d`**: o binário autoritativo em Rust define `MapBounds::default_arena()` em `[-500, +500]` com colisor circular de raio `2.0` (`[-498, +498]`). Alterar o raio apenas em Lua quebraria a paridade com a física nativa e todos os testes de parede/túnel.
- **Legibilidade em perspectiva 2.5D**: em jogos top-down/isométricos 2.5D, o colisor físico representa a **pegada no chão** (sombra/pés, `32px` de diâmetro), enquanto os `64px` (`8.0u`) de altura do sprite se projetam para cima fora do plano de colisão.

### Regra de Pivôs

1. **Pivô do Chão / Colisor `(x, y)`**:
   - Origem e destino de todas as skills no servidor (`Loci.get_entity_position`).
   - Âncora da sombra de time (`draw_team_shadow`) e dos pés do sprite (`oy = foot_y`).
   - **Origem do indicador de mira no chão** (`love.draw` em `client/main.lua`) e dos círculos de detecção no overlay de debug (`F3`).
2. **Pivô Visual do Tronco `(x, y - 4.0u)` (`-32px`)**:
   - Usado apenas para origem visual de projéteis/arcos no ar (`draw_procedural_skill_fx`) e cálculo de offset da HUD acima da cabeça.

---

## 3. Tabela de Calibração das Skills (vs. Altura Visual `8.0u`)

Todas as skills são definidas diretamente em unidades do mundo nos arquivos `server/scripts/default_arena/data/skills/*.lua` e publicadas para o cliente via `skill_ranges` (`CharacterFactory.build_skill_ranges`):

| Skill | `range` | `aoe_radius` | Amostragem / Impacto no Servidor | Alcance Efetivo Frontal | Fator Focal da Mira (`SkillRanges.aim_distance`) | Proporção (vs. `8.0u`) |
| :--- | :---: | :---: | :--- | :---: | :---: | :---: |
| `slash` | `16.0u` (`128px`) | `7.0u` (`56px`) | `0.25*r` (`4.0u`) e `0.5*r` (`8.0u`) | `15.0u` (`120px`) | `0.5 * range` (`8.0u`) | `1.88×` |
| `fury_reward` | `24.0u` (`192px`) | `9.0u` (`72px`) | `0.2*r` (`4.8u`) e `0.5*r` (`12.0u`) | `21.0u` (`168px`) | `0.5 * range` (`12.0u`) | `2.63×` |
| `whirlwind_dash` | `40.0u` (`320px`) | `10.0u` (`80px`) | Varredura `d = 0..40.0u` (`6` ticks) | `50.0u` (`400px`) | `1.0 * range` (`40.0u`) | `5.00×` (dash) |
| `blade_throw` | `56.0u` (`448px`) | `8.0u` (`64px`) | Raio `1.5u` de `d = 2.0..56.0u` | `64.0u` (`512px`) | `1.0 * range` (`56.0u`) | `7.00×` (projétil) |
| `fireball` | `64.0u` (`512px`) | `9.0u` (`72px`) | Explosão centrada em `0.7*r` (`44.8u`) | `53.8u` (`430.4px`) | `0.7 * range` (`44.8u`) | `5.60×` (centro) |
| `shield` | — | — | Auto-buff (`1000` escudo, `150` ticks) | — | — | — |

---

## 4. Overlay Espacial de Debug (`F3`)

Ao ativar o debug (`F3`), `draw_spatial_debug_overlay` em `client/main.lua` renderiza diretamente na arena:

- **Círculo verde**: colisor físico real no chão (`PLAYER_COLLIDER_RADIUS = 2.0u` = `16px` de raio).
- **Retângulo amarelo**: bounding box visual de referência do sprite (`64×64px` ancorado nos pés).
- **Cruzes de pivô**: verde nos **pés/colisor** `(px, py)` e magenta no **centro visual do corpo** `(px, py - 32px)`.
- **Círculos e arcos das skills equipadas**: geometria exata de `SkillRanges.get_detection_geometry(skill)` projetada na direção do vetor de facing atual do jogador local.
