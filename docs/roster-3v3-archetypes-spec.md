# Especificação Técnica de Personagens e Habilidades — Roster 3v3

> **Referência do Projeto:** Loci Arena (Engine `loci2d` Rust + Cliente Love2D)  
> **Tickrate do Servidor:** `30 Hz` (`1 segundo = 30 ticks`)  
> **Escala Canônica:** `VISUAL_SCALE = 8` (`1.0u = 8 px`), colisor circular de raio `2.0u` (`16 px`), altura visual padrão `8.0u` (`64 px`).  
> **Fórmula de Mitigação (`CombatSystem`):** $\text{Mitigação} = \frac{\text{Defesa}}{\text{Defesa} + 100}$

---

## 1. Visão Geral da Arquitetura 3v3

Para suportar partidas competitivas balanceadas no formato **3v3** (6 jogadores na arena, 3 por time), o elenco é estruturado em **3 grandes classes**, cada uma subdividida em **2 arquétipos especializados**, totalizando **6 personagens**:

```
                       ┌───────────────────────┐
                       │     Loci Arena 3v3    │
                       └───────────┬───────────┘
          ┌────────────────────────┼────────────────────────┐
          ▼                        ▼                        ▼
     [ MELEE ]                  [ DPS ]                [ SUPORTE ]
  ┌───────┴───────┐        ┌───────┴───────┐        ┌───────┴───────┐
  ▼               ▼        ▼               ▼        ▼               ▼
Tank          Fighter   Físico          Mágico    Cura          Utilidade
(Warrior)     (Arya)    (Archer)        (Mage)    (Cleric)      (Enchanter)
```

### Filosofia de Balanceamento
1. **Papéis Definidos**: Cada composição 3v3 viável combina absorção de dano / disrupção (Tank/Fighter), dano contínuo ou explosivo (DPS) e sustentação/buffs (Suporte).
2. **Controles Padronizados em 4 Slots**:
   - **Slot 1 (Ataque Básico)**: Cooldown curto (`15–20` ticks / `0.5–0.66s`), sem ou com baixíssimo custo de mana (`0–10`).
   - **Slot 2 (Habilidade Tática 1)**: Dano principal, debuff ou cura direcionada. Cooldown médio (`150–210` ticks / `5.0–7.0s`).
   - **Slot 3 (Mobilidade / Defensivo)**: Dash, rolamento, buff de escudo ou controle de aproximação (`180–300` ticks / `6.0–10.0s`).
   - **Slot 4 (Ultimate)**: Habilidade definidora de confronto, alto impacto (`420–480` ticks / `14.0–16.0s`), alto consumo de mana.
3. **Sem Carga Manual de Clique**: Todas as habilidades são disparadas como intents discretas autoritativas (`send_action`), garantindo perfeita integridade no netcode UDP e predição do cliente sem risco de dessincronização.

---

## 2. Tabela Comparativa de Atributos Base

| Arquétipo | Personagem | `role` | HP | Def. Fís. (Mitig.) | Def. Mág. (Mitig.) | Vel. (`u/tick`) | Vel. (`px/s`) | Mana / Regen | HP Regen |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Melee: Tank** | **Warrior** | `tank` | `6000` | `120` (54.5%) | `40` (28.5%) | `1.9` | `456` | `100` / `5` | `15` |
| **Melee: Fighter** | **Arya** | `fighter` | `5000` | `85` (45.9%) | `55` (35.5%) | `2.2` | `528` | `100` / `10` | `12` |
| **DPS: Físico** | **Archer** | `marksman` | `3800` | `40` (28.5%) | `40` (28.5%) | `2.1` | `504` | `120` / `10` | `10` |
| **DPS: Mágico** | **Mage** | `mage` | `4000` | `40` (28.5%) | `90` (47.4%) | `2.0` | `480` | `250` / `15` | `10` |
| **Suporte: Cura** | **Cleric** | `healer` | `4400` | `55` (35.5%) | `65` (39.4%) | `2.0` | `480` | `200` / `15` | `12` |
| **Suporte: Utilidade** | **Enchanter** | `support` | `4600` | `60` (37.5%) | `60` (37.5%) | `2.05` | `492` | `180` / `12` | `10` |

---

## 3. Especificação Completa dos 6 Personagens

---

### 3.1. Warrior (Melee: Tank)
- **Identidade**: Colosso de armadura pesada. Bloqueia avanço de inimigos e protege seus causadores de dano.
- **Tags**: `{"MELEE", "TANK"}`
- **Velocidade**: `1.9 u/tick` (o mais lento da arena, mas o mais resistente)

#### Kit de Habilidades:
1. **Slot 1: `slash` (Ataque Básico)**
   - **Tipo**: Físico | **Dano**: `350`
   - **Alcance / AoE**: `16.0u` / `7.0u` | **Cooldown**: `15 ticks` (0.5s) | **Mana**: `10`
   - **Mecânica**: Golpe de espada frontal corpo-a-corpo.
2. **Slot 2: `shield_bash` (Habilidade Tática)**
   - **Tipo**: Físico | **Dano**: `280`
   - **Alcance / AoE**: `14.0u` / `6.0u` | **Cooldown**: `210 ticks` (7.0s) | **Mana**: `25`
   - **Mecânica**: Avanço curto com o escudo, atordoando o alvo por `24 ticks` (0.8s) e cancelando conjurações ativas.
3. **Slot 3: `shield` (Defensivo / Auto-Buff)**
   - **Tipo**: Escudo de Absorção
   - **Absorção**: `1000 HP` por `150 ticks` (5.0s) | **Cooldown**: `300 ticks` (10.0s) | **Mana**: `30`
   - **Mecânica**: Aplica `apply_shield` no próprio guerreiro, absorvendo dano antes da barra de vida.
4. **Slot 4: `earthquake_slam` (Ultimate)**
   - **Tipo**: Físico | **Dano**: `550`
   - **Alcance / AoE**: `28.0u` / `14.0u` | **Cooldown**: `450 ticks` (15.0s) | **Mana**: `50`
   - **Mecânica**: Salto e impacto no chão em área. Causa dano físico e Stun em área por `36 ticks` (1.2s).

---

### 3.2. Arya (Melee: Fighter / Lutadora)
- **Identidade**: Lutadora ágil com mobilidade explosiva, mecânica de desarme de alto risco e fúria após baixas.
- **Tags**: `{"MELEE", "FIGHTER"}`
- **Velocidade**: `2.2 u/tick` (a mais rápida da arena)

#### Kit de Habilidades *(Consolidado e Calibrado)*:
1. **Slot 1: `slash` (Ataque Básico)**
   - **Tipo**: Físico | **Dano**: `350`
   - **Alcance / AoE**: `16.0u` / `7.0u` | **Cooldown**: `15 ticks` (0.5s) | **Mana**: `10`
2. **Slot 2: `fury_reward` (Ataque Especial / Fúria)**
   - **Tipo**: Físico | **Dano**: `500` (Crítico Forçado $2.25\times = 1125$)
   - **Alcance / AoE**: `24.0u` / `9.0u` | **Cooldown**: `150 ticks` (5.0s) | **Mana**: `0`
   - **Mecânica**: Bloqueado em times até a morte de um aliado (ativado via passiva) ou liberado em duelos 1v1.
3. **Slot 3: `whirlwind_dash` (Investida Giratória)**
   - **Tipo**: Físico | **Dano**: `450`
   - **Alcance / AoE**: `40.0u` / `10.0u` | **Duração do Dash**: `6 ticks` (0.2s) | **Cooldown**: `180 ticks` (6.0s) | **Mana**: `25`
   - **Mecânica**: Desloca a personagem em alta velocidade girando a espada em 360º ao longo de todo o percurso.
4. **Slot 4: `blade_throw` (Ultimate)**
   - **Tipo**: Físico | **Dano**: `400` + Stun `36 ticks` (1.2s)
   - **Alcance / Raio**: `56.0u` / `8.0u` AoE | **Cooldown**: `420 ticks` (14.0s) | **Mana**: `45`
   - **Mecânica**: Arremessa a lâmina física (sensor CCD). No impacto, causa Stun em área, mas aplica **Desarme** de `60 ticks` (2.0s) na própria Arya.

---

### 3.3. Archer (DPS: Físico / Atirador)
- **Identidade**: Atirador de longo alcance. Mantém distância com rolamento tático e causa dano físico contínuo com projéteis.
- **Tags**: `{"RANGED", "DPS", "PHYSICAL"}`
- **Velocidade**: `2.1 u/tick` (alta mobilidade para kiting)

#### Kit de Habilidades:
1. **Slot 1: `quick_shot` (Ataque Básico)**
   - **Tipo**: Físico | **Dano**: `280`
   - **Alcance / Raio do Projétil**: `52.0u` / `1.2u` | **Velocidade**: `5.0 u/tick`
   - **Cooldown**: `18 ticks` (0.6s) | **Cast Lock**: `6 ticks` (0.2s) | **Mana**: `5`
   - **Mecânica**: Disparo direto e veloz de flecha.
2. **Slot 2: `piercing_arrow` (Habilidade Tática)**
   - **Tipo**: Físico | **Dano**: `420`
   - **Alcance / Raio do Projétil**: `64.0u` / `1.6u` | **Velocidade**: `6.5 u/tick`
   - **Cooldown**: `180 ticks` (6.0s) | **Mana**: `25`
   - **Mecânica**: Flecha de alta perfuração que atravessa múltiplos inimigos em linha e aplica `fragile = 1` (+30% de dano sofrido) por `60 ticks` (2.0s).
3. **Slot 3: `tactical_roll` (Mobilidade / Evasão)**
   - **Tipo**: Deslocamento Físico
   - **Alcance**: `26.0u` em `4 ticks` | **Cooldown**: `180 ticks` (6.0s) | **Mana**: `20`
   - **Mecânica**: Rolamento ágil na direção do comando de movimento ou mira, permitindo reposicionamento instantâneo.
4. **Slot 4: `arrow_rain` (Ultimate)**
   - **Tipo**: Físico em Área | **Dano Total**: `650` (5 pulsos de `130`)
   - **Alcance / AoE**: `48.0u` / `16.0u` | **Duração da Área**: `60 ticks` (2.0s)
   - **Cooldown**: `420 ticks` (14.0s) | **Mana**: `45`
   - **Mecânica**: Marca um círculo à distância; após 10 ticks, uma saraivada contínua atinge a área, causando dano e lentidão.

---

### 3.4. Mage (DPS: Mágico / Conjurador)
- **Identidade**: Especialista em dano massivo em área de impacto e controle de espaço, vulnerável a investidas diretas.
- **Tags**: `{"RANGED", "DPS", "MAGICAL"}`
- **Velocidade**: `2.0 u/tick`

#### Kit de Habilidades:
1. **Slot 1: `magic_missile` (Ataque Básico)**
   - **Tipo**: Mágico | **Dano**: `260`
   - **Alcance / Raio do Projétil**: `46.0u` / `1.4u` | **Velocidade**: `4.5 u/tick`
   - **Cooldown**: `18 ticks` (0.6s) | **Mana**: `10`
2. **Slot 2: `fireball` (Habilidade Tática)** *(Já existente)*
   - **Tipo**: Mágico | **Dano**: `480`
   - **Alcance / AoE**: `64.0u` / `9.0u` | **Velocidade**: `3.5 u/tick`
   - **Cooldown**: `150 ticks` (5.0s) | **Mana**: `35`
   - **Mecânica**: Projétil explosivo de longo alcance com detonação em área no primeiro contato ou no limite do alcance.
3. **Slot 3: `frost_nova` (Defensivo / Disrupção)**
   - **Tipo**: Mágico em 360º | **Dano**: `220` + Stun `18 ticks` (0.6s)
   - **AoE**: `14.0u` centrado no conjurador | **Cooldown**: `240 ticks` (8.0s) | **Mana**: `30`
   - **Mecânica**: Onda congelante imediata ao redor do mago que repele assassinos e lutadores que tentam encurtar a distância.
4. **Slot 4: `meteor_strike` (Ultimate)**
   - **Tipo**: Mágico | **Dano**: `750`
   - **Alcance / AoE**: `56.0u` / `18.0u` | **Atraso de Queda**: `24 ticks` (0.8s de aviso visual)
   - **Cooldown**: `480 ticks` (16.0s) | **Mana**: `65`
   - **Mecânica**: Invoca um meteoro colossal que aniquila grupos concentrados no ponto marcado.

---

### 3.5. Cleric (Suporte: Cura / Sacerdote)
- **Identidade**: O sustentáculo da equipe. Restaura pontos de vida, cria zonas seguras de regeneração e reverte lutas quase perdidas.
- **Tags**: `{"SUPPORT", "HEALER"}`
- **Velocidade**: `2.0 u/tick`

#### Kit de Habilidades:
1. **Slot 1: `smite` (Ataque Básico)**
   - **Tipo**: Mágico | **Dano**: `220`
   - **Alcance / Raio**: `38.0u` / `1.2u` | **Cooldown**: `20 ticks` (0.66s) | **Mana**: `10`
   - **Mecânica**: Raio luminoso em linha reta com dano moderado para auxílio a abates.
2. **Slot 2: `healing_light` (Cura Direcionada)**
   - **Tipo**: Restauração de HP | **Cura**: `500 HP`
   - **Alcance**: `36.0u` | **Cooldown**: `180 ticks` (6.0s) | **Mana**: `35`
   - **Mecânica**: Cura o aliado mais ferido na direção da mira (ou a si mesmo se nenhum aliado estiver dentro do cone de alcance).
3. **Slot 3: `sacred_ground` (Zona Sagrada)**
   - **Tipo**: Área de Regeneração
   - **Alcance / AoE**: `24.0u` / `12.0u` | **Duração**: `120 ticks` (4.0s)
   - **Cooldown**: `270 ticks` (9.0s) | **Mana**: `40`
   - **Mecânica**: Cria um santuário no chão. Aliados no círculo regeneram `80 HP/s` e ganham +20 de Defesa Mágica temporária.
4. **Slot 4: `divine_resurgence` (Ultimate)**
   - **Tipo**: Cura em Área + Escudo de Emergência
   - **AoE**: `24.0u` (360º ao redor do Cleric)
   - **Cura**: `700 HP` + Escudo de `400 HP` por `90 ticks` (3.0s)
   - **Cooldown**: `480 ticks` (16.0s) | **Mana**: `65`
   - **Mecânica**: Pulso sagrado massivo que salva o time inteiro em teamfights críticas.

---

### 3.6. Enchanter (Suporte: Utilidade / Guardião Tático)
- **Identidade**: Especialista em escudos reativos, atordoamento e aceleração de equipe. Muda o ritmo da arena sem depender de curas diretas.
- **Tags**: `{"SUPPORT", "UTILITY"}`
- **Velocidade**: `2.05 u/tick`

#### Kit de Habilidades:
1. **Slot 1: `kinetic_pulse` (Ataque Básico)**
   - **Tipo**: Físico | **Dano**: `200`
   - **Alcance / AoE**: `28.0u` / `6.0u` | **Cooldown**: `18 ticks` (0.6s) | **Mana**: `8`
   - **Mecânica**: Disparo de energia cinética de impacto rápido.
2. **Slot 2: `aegis_barrier` (Escudo em Aliado)**
   - **Tipo**: Escudo de Absorção | **Absorção**: `850 HP` por `120 ticks` (4.0s)
   - **Alcance**: `36.0u` | **Cooldown**: `210 ticks` (7.0s) | **Mana**: `35`
   - **Mecânica**: Projeta uma barreira protetora sobre o aliado na mira (ou em si mesmo), prevenindo dano antes que ele ocorra.
3. **Slot 3: `gravity_surge` (Vórtice Gravitacional / CC)**
   - **Tipo**: Mágico / Controle de Grupo | **Dano**: `150` + Stun `18 ticks` (0.6s)
   - **Alcance / AoE**: `32.0u` / `10.0u` | **Cooldown**: `240 ticks` (8.0s) | **Mana**: `35`
   - **Mecânica**: Cria um vórtice no ponto mirado que puxa inimigos para o centro e os atordoa brevemente, agrupando-os para os DPSs.
4. **Slot 4: `bastion_overload` (Ultimate)**
   - **Tipo**: Escudo de Grupo + Aceleração
   - **AoE**: `22.0u` | **Duração**: `150 ticks` (5.0s)
   - **Efeito**: Concede `1000 HP` de escudo e `+25%` de velocidade de movimento para todos os aliados na área.
   - **Cooldown**: `450 ticks` (15.0s) | **Mana**: `55`

---

## 4. Sistema Visual de Placeholders por Arquétipo

Enquanto os pacotes de spritesheets dedicados de cada personagem estão em produção, o cliente renderiza o robô procedural padronizado de `32×32 px` com **paletas de cores exclusivas por arquétipo**, permitindo reconhecimento imediato na tela:

### Paleta dos Robôs:
| Arquétipo | Personagem | Cor Primária do Corpo (RGB) | Amostra Visual |
| :--- | :--- | :---: | :---: |
| **Tank** | Warrior | `(0.35, 0.45, 0.58)` | **Aço Ardósia / Azul Blindado** |
| **Fighter** | Arya | `(0.85, 0.30, 0.22)` | **Carmesim de Combate** |
| **Marksman** | Archer | `(0.18, 0.68, 0.32)` | **Verde Esmeralda / Caçador** |
| **Mage** | Mage | `(0.58, 0.22, 0.88)` | **Violeta Arcano** |
| **Healer** | Cleric | `(0.94, 0.76, 0.18)` | **Dourado Solar / Sagrado** |
| **Support** | Enchanter | `(0.10, 0.72, 0.75)` | **Turquesa Tático / Ciano** |

### Diferenciação de Time e Estado:
- **Visor / Olho do Robô**:
  - `Jogador Local (Me)`: Ciano Elétrico `(0.20, 0.95, 1.00)`
  - `Aliado (Time 1)`: Azul Celeste `(0.30, 0.80, 1.00)`
  - `Inimigo (Time 2)`: Vermelho Vibrante `(1.00, 0.30, 0.25)`
- **Sombra no Chão (`draw_team_shadow`)**:
  - Azul para Time 1 / Verde para local / Vermelho para Time 2.
- **Robô Morto**:
  - Corpo em cinza desaturado `(0.35, 0.35, 0.38)` + visor desativado + cruz vermelha centralizada no peito.
