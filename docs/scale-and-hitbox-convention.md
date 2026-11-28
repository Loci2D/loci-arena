# Convenção Única de Escala, Pivô e Hitboxes — Loci Arena

> **Referência técnica:** Card [#96](https://trello.com/c/SHn4oQ8e) e Card [#93](https://trello.com/c/NbgRmWUF) · Documenta a convenção consolidada a partir dos PRs #67 (`feat/skill-range-calibration`) e #69 (`feat/movement-speed-2.0`).

---

## 1. Contexto Investigado

Para alinhar o alcance percebido das habilidades ao tamanho visual dos personagens, foram comparadas as constantes físicas do servidor (`PLAYER_COLLIDER_RADIUS = 2.0`), a escala visual do cliente (`VISUAL_SCALE = 8`, `SPRITE_BASE_SIZE = 32`, `SPRITE_SCALE = 2`) e a geometria de detecção das skills:

1. **Proporção física vs. visual**: `2.0u` de raio no servidor equivalem a `16px` de raio (`32px` de diâmetro), enquanto o sprite renderizado com `SPRITE_SCALE = 2` tem `64px` de altura base (`8.0u`) — ou seja, altura visual 2× maior que o diâmetro do colisor circular.
2. **Relação entre pivôs**: no servidor, `(ent.x, ent.y)` representa o centro do colisor circular no plano do chão (onde o cliente ancora a sombra de time e os pés do sprite), enquanto elementos aéreos (VFX procedurais, indicador de mira e HUD acima da cabeça) usam deslocamento vertical relativo à altura do sprite.

---

## 2. Decisão Técnica: Convenção de Escala (Perspectiva 2.5D)

Mantemos o colisor físico travado à engine `loci2d` (`MapBounds::default_arena()`) e formalizamos a separação entre **plano do chão (física/hitboxes)** e **altura visual em perspectiva 2.5D**:

| Constante | Valor Canônico | Equivalente em Pixels / Mundo | Fonte no Código |
| :--- | :---: | :--- | :--- |
| `VISUAL_SCALE` | `8` | `1.0u = 8 px` (`1280×720` = `160×90u`) | `client/main.lua`, `server/scripts/default_arena/core/combat_system.lua` (`CombatSystem.CONST.VISUAL_SCALE`) |
| `PLAYER_COLLIDER_RADIUS` | `2.0u` | `16 px` de raio (`32 px` de diâmetro); `SAFE_MIN/MAX = ±498` (paredes/engine Rust) | `server/scripts/default_arena/core/arena_bounds.lua`, `client/main.lua` |
| `BODYBLOCK_DIST` (`MIN_COLLISION_DIST`) | `6.5u` | `52 px` entre centros (contato externo da sombra de `52 px`, com *sliding* tangencial) | `server/scripts/default_arena/main.lua`, `client/main.lua` |
| `SPRITE_BASE_SIZE` | `32 px` | Base lógica do modelo/placeholder | `client/main.lua` |
| `SPRITE_SCALE` | `2` | `64 px` (`8.0u`) de altura visual de referência | `client/main.lua` |
| Velocidade base (`SPEED`) | `2.0 u/tick` | `60 u/s` a `30 Hz` (`480 px/s` = `7.5` alturas/s); arquétipos podem variar (ex.: Arya `2.2 u/tick`) | `server/scripts/default_arena/main.lua`, `server/scripts/default_arena/data/characters/*.lua`, `loci.netcode.default_move_speed` |

### Por que manter `PLAYER_COLLIDER_RADIUS = 2.0` e `SPRITE_SCALE = 2`?

- **Compatibilidade com a engine `loci2d`**: o binário autoritativo em Rust define `MapBounds::default_arena()` em `[-500, +500]` com colisor circular de raio `2.0` (`[-498, +498]`). Alterar o raio apenas em Lua quebraria a paridade com a física nativa e os testes de colisão de parede.
- **Legibilidade em perspectiva 2.5D**: em jogos top-down/isométricos 2.5D, o colisor físico representa a **pegada no chão** (sombra/pés, `32px` de diâmetro), enquanto os `64px` (`8.0u`) de altura do sprite se projetam para cima fora do plano de colisão.

### Regra de Pivôs

1. **Pivô do Chão / Colisor `(x, y)`**:
   - Origem e destino de todas as skills e colisões no servidor (`Loci.get_entity_position`).
   - Âncora da sombra de time (`draw_team_shadow`) e dos pés do sprite (`oy = foot_y`).
2. **Pivô Visual do Tronco `(x, y - 32px)` (`-4.0u`)**:
   - Usado como referência vertical para VFX procedurais no ar (`draw_procedural_skill_fx`), indicador de mira em `client/main.lua` e cálculo de offset da HUD acima da cabeça.
   - *Observação:* caso no futuro se deseje projetar o indicador de mira diretamente no plano do chão `(x, y)`, o ajuste deve ser feito em uma demanda dedicada mantendo alinhamento com `SkillRanges`.

---

## 3. Tabela de Calibração das Skills (vs. Altura Visual `8.0u`)

Todas as skills são definidas diretamente em unidades do mundo nos arquivos `server/scripts/default_arena/data/skills/*.lua` e publicadas para o cliente via propriedade `skill_ranges` (`CharacterFactory.build_skill_ranges`), consumida por `client/src/skill_ranges.lua` com teste anti-deriva em `tests/test_skills_and_combat_flow.lua`:

| Skill | `range` | `aoe_radius` | Amostragem / Impacto no Servidor | Alcance Efetivo Frontal | Proporção (vs. `8.0u`) |
| :--- | :---: | :---: | :--- | :---: | :---: |
| `slash` | `16.0u` (`128px`) | `7.0u` (`56px`) | `0.25*r` (`4.0u`) e `0.5*r` (`8.0u`) | `15.0u` (`120px`) | `1.88×` |
| `fury_reward` | `24.0u` (`192px`) | `9.0u` (`72px`) | `0.2*r` (`4.8u`) e `0.5*r` (`12.0u`) | `21.0u` (`168px`) | `2.63×` |
| `whirlwind_dash` | `40.0u` (`320px`) | `10.0u` (`80px`) | Varredura `d = 0..40.0u` (`6` ticks) | `50.0u` (`400px`) | `5.00×` (dash) |
| `blade_throw` | `56.0u` (`448px`) | `8.0u` (`64px`) | Projétil raio `1.5u` de `d = 2.0..56.0u` | `64.0u` (`512px`) | `7.00×` (projétil) |
| `fireball` | `64.0u` (`512px`) | `9.0u` (`72px`) | Explosão centrada em `0.7*r` (`44.8u`) | `53.8u` (`430.4px`) | `5.60×` (centro) |
| `shield` | — | — | Auto-buff (`1000` escudo, `150` ticks) | — | — |
