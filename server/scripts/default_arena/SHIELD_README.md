# Sistema de Escudo - Guia de Configuração

## Visão Geral

O sistema de escudo foi implementado diretamente em `main.lua` (seção "SISTEMA DE ESCUDO") e permite que os jogadores ativem um escudo temporário que absorve uma porcentagem do HP base como dano.

**Nota**: O código está integrado no `main.lua` porque o ambiente Lua do loci2d não suporta a função `require()` para módulos separados.

**Importante**: O sistema foi simplificado para não depender de ticks do servidor (que não funcionam corretamente). Agora:
- O **servidor** gerencia a absorção de dano e calcula a capacidade do escudo (autoritativo)
- O **cliente** gerencia duração e cooldown (usando tempo real do Love2D)
- O cliente **não** aceita desativação do servidor para evitar conflitos de timer

## Como Usar

### No Jogo (Cliente)
- Pressione **E** para ativar o escudo
- O escudo dura 15 segundos por padrão
- Cooldown de 10 segundos por padrão
- Quando ativo, o escudo absorve 10% do HP base como dano
- Exemplo: Com 100 HP, o escudo absorve 10 de dano
- O escudo quebra se a capacidade chegar a 0 ou se o tempo expirar
- Jogadores com escudo ativo têm uma aura azul/laranja ao redor deles
- O HUD mostra:
  - Capacidade restante enquanto ativo
  - Tempo restante até expirar
  - Cooldown após o escudo acabar

## Configurações

### Servidor (`main.lua`)

As configurações do servidor estão na seção "SISTEMA DE ESCUDO" (linhas 13-15):

```lua
local SHIELD_CAPACITY_PERCENT = 0.1  -- Capacidade do escudo como % do HP (0.1 = 10%)
local SHIELD_ABILITY_ID = 2             -- ID da habilidade
```

### Cliente (`client/main.lua`)

As configurações do cliente estão no topo do arquivo (linhas 48-52):

```lua
local SHIELD_ABILITY_ID = 2         -- ID da habilidade de escudo
local SHIELD_CAPACITY = 100          -- Capacidade padrão (será sobrescrita pelo servidor)
local SHIELD_DURATION = 15.0         -- Duração do escudo em segundos
local SHIELD_COOLDOWN = 10.0         -- Cooldown do escudo em segundos
```

### Parâmetros Configuráveis

1. **SHIELD_CAPACITY_PERCENT** (Porcentagem do HP para capacidade do escudo)
   - Padrão: `0.1` (10% do HP)
   - Localização: `server/main.lua`
   - Affects: Capacidade do escudo calculada como porcentagem do HP base
   - Exemplos:
     - `0.1` = 10% do HP (100 HP → 10 de capacidade)
     - `0.2` = 20% do HP (100 HP → 20 de capacidade)
     - `0.5` = 50% do HP (100 HP → 50 de capacidade)
   - **Importante**: As mudanças neste valor são aplicadas imediatamente ao servidor (basta reiniciar o servidor)

2. **SHIELD_DURATION** (Duração do escudo em segundos)
   - Padrão: `15.0`
   - Localização: `client/main.lua`
   - Affects: Quanto tempo o escudo permanece ativo antes de expirar
   - **Importante**: É necessário reiniciar o cliente para aplicar mudanças

3. **SHIELD_COOLDOWN** (Cooldown do escudo em segundos)
   - Padrão: `10.0`
   - Localização: `client/main.lua`
   - Affects: Tempo de espera antes de poder ativar o escudo novamente
   - **Importante**: É necessário reiniciar o cliente para aplicar mudanças

4. **SHIELD_ABILITY_ID** (ID da habilidade)
   - Padrão: `2`
   - Localização: `server/main.lua` e `client/main.lua` (devem ser iguais)
   - Affects: ID usado para comunicação cliente-servidor

## Integração

### Servidor (main.lua)
- O sistema de escudo está integrado diretamente no `main.lua` (linhas 9-139)
- As configurações estão no topo desta seção (linhas 13-14)
- A função `damage_target()` foi modificada para aplicar absorção de dano
- A função `on_action()` processa o `ability_id = 2` para ativar o escudo
- A função `on_player_leave()` limpa o estado do escudo
- A capacidade do escudo é calculada dinamicamente baseada no HP do jogador

### Cliente (main.lua)
- Tecla **E** envia ação com `SHIELD_ABILITY_ID = 2`
- Visualização: aura azul ao redor do jogador quando escudo está ativo
- HUD mostra a capacidade restante recebida do servidor
- Jogadores inimigos com escudo ficam laranja

## Propriedades Sincronizadas

O servidor sincroniza as seguintes propriedades para o cliente:
- `is_shielded`: "true" ou "false"
- `shield_capacity`: capacidade restante do escudo (string)
- `shield_max_capacity`: capacidade máxima do escudo (string)

## Como Aplicar Mudanças

1. **Para mudar a porcentagem do escudo (servidor)**:
   - Edite `SHIELD_CAPACITY_PERCENT` em `server/scripts/default_arena/main.lua`
   - Reinicie o servidor: `./scripts/run_server.sh`
   - A mudança será aplicada imediatamente

2. **Para mudar duração ou cooldown (cliente)**:
   - Edite `SHIELD_DURATION` ou `SHIELD_COOLDOWN` em `client/main.lua`
   - Reinicie o cliente: `./scripts/run_client.sh`
   - A mudança será aplicada
