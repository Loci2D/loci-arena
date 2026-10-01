# Loci2D - 3v3 Battle Arena: Documentação de Regras Base e Atributos

Este documento define as regras matemáticas e as lógicas de cálculo de atributos para o servidor da Loci2D, atuando como a única fonte de verdade (Single Source of Truth) para o desenvolvimento do sistema de combate. O objetivo é padronizar e corrigir inconsistências deixadas no rascunho anterior.

---

## 1. Sistema de Vida e Regeneração

*   **HP (Vida):** A base de HP dos personagens varia de **4.000 a 10.000**.
*   **Regeneração Base (Em Combate):** Todo personagem possui uma regeneração fixa em HP/segundo (ex: 10 HP/s).
*   **Regeneração (Fora de Combate):** Ativada após **7 segundos** sem receber nenhum tipo de dano.
    *   *Fórmula Sugerida:* Recupera uma porcentagem do HP Máximo por segundo (ex: `2% do HP Máximo / segundo`) em vez de multiplicar a vida atual (o que causaria escalonamento quebrado).

## 2. Sistema de Dano e Defesa (Físico vs Mágico)

Existem duas naturezas principais de dano: **Físico** e **Mágico**. Ambas são calculadas separadamente em relação às suas respectivas defesas (Defesa Física e Defesa Mágica).

### 2.1. Fórmula de Redução de Dano (Armadura/Resistência)
Para evitar que a defesa deixe o personagem invulnerável (dano = 0), utilizamos uma curva de rendimento decrescente (diminishing returns).

*   **Fórmula:** `Redução (%) = Defesa / (Defesa + K)`
    *   *K é a constante de escalonamento. No nosso caso, **K = 100***.
    *   *Exemplo:* Um personagem com 100 de Defesa. `Redução = 100 / (100 + 100) = 0.5 (50%)`. Metade do dano é mitigado.

### 2.2. Cálculo de Dano Final
Todo dano recebido (seja fixo de ataque básico ou de habilidade) passa pela mitigação da defesa correspondente (Física ou Mágica).

*   **Dano Final = Dano Base * (1 - Redução %)**

### 2.3. Tipos de Aplicação de Dano
*   **Dano Fixo (Flat):** Causará uma quantidade nominal (ex: 6000 de dano). É mitigado pela Defesa.
*   **Dano por Porcentagem de HP (DPS/Burst):**
    *   Dano atrelado à **Vida Máxima** ou **Vida Atual** do inimigo.
    *   *Regra de Limite (Cap):* É fundamental programar um limite máximo de dano contra "Chefes" ou personagens com HP absurdamente alto (ex: Habilidade tira 15% de HP, mas com dano máximo limitado a `X`).

## 3. Sistema de Ataque Crítico

O Crítico tem a chance de aumentar significativamente o dano de um ataque, sendo igual para habilidades Físicas e Mágicas.

*   **Chance de Crítico Base (RNG):** 10% (0.10) por ataque.
*   **Dano Crítico (Multiplicador):** **225%** (Dano Final * 2.25).
*   **Garantia de Crítico (Pseudo-RNG):** Foi sugerida uma regra onde a cada 5 ataques o crítico ocorre. Se formos usar isso, o sistema deve garantir que o **5º ataque no mesmo alvo é crítico garantido** caso não tenha "critado" nos 4 ataques anteriores. *(Isso reduz a frustração de RNG puro).*

## 4. Modificadores e Atributos Secundários

*   **Velocidade de Movimento (Movement Speed):** Velocidade em que a entidade se move no vetor da engine (Loci2D).
*   **Velocidade de Ataque (Attack Speed / Cooldown de Ataque):** Define o tempo de recarga (delay) entre um ataque básico e o próximo.
*   **Roubo de Vida (Lifesteal):**
    *   *Fórmula:* `Cura = Dano Final Causado * Porcentagem de Lifesteal`.
    *   Aplica-se apenas ao dano que *efetivamente* reduziu o HP do inimigo (após mitigação).
*   **Dano por Distância / Proximidade:**
    *   Projéteis que causam mais dano de longe: `Dano Final = Dano Base * (Distância Percorrida / Constante de Escala)`.
    *   Projéteis tipo Shotgun (perdem dano): Sofrem "Falloff" (redução de % do dano baseado na distância).

## 5. Efeitos de Status (Debuffs)

### 5.1. Fragilidade
*   Aplica um modificador global de dano sofrido.
*   *Efeito:* O alvo passa a receber **+30% de Dano** (Dano Recebido * 1.30) independente da fonte de dano.

### 5.2. Efeitos Atrelados a Natureza do Dano
*   **Sangramento (Dano Físico):**
    *   *Gatilho:* Ocorre após o personagem sofrer um acerto crítico (ou X críticos acumulados).
    *   *Efeitos:* Dano contínuo por segundo (DoT) + Aplicação de **Lentidão** (redução de Movement Speed).
*   **Queimadura (Dano Mágico):**
    *   *Efeitos:* Dano contínuo por segundo (DoT) + **Embaçamento** (Cegueira ou redução de visão de mapa/precisão para o jogador alvo).

---
**Nota para implementação na Loci2D:**
Para o servidor processar isso sem gargalo, recomendo que as entidades tenham um struct/classe de `CombatStats` que calcule dinamicamente a `Redução (%)` sempre que um status de armadura mudar, ao invés de calcular a divisão de defesa a cada hit recebido.
