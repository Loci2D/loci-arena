# Loci Arena - Informações para Agentes

## Estrutura do Projeto

Este é um jogo multiplayer 2D usando:
- **Cliente**: Love2D (Lua)
- **Servidor**: loci2d (engine autoritativa de rede/física em Rust)
- **Scripts de jogo**: Lua no servidor (`server/scripts/default_arena/`)

## Execução

### Servidor
```bash
./scripts/run_server.sh
```

### Cliente
```bash
./scripts/run_client.sh
```

## Scripts de Servidor

- `server/scripts/default_arena/main.lua`: Script principal com callbacks autoritativos
  - `on_player_join`: Inicializa propriedades do jogador (hp, score, team)
  - `on_move_intent`: Processa movimento
  - `on_action`: Processa habilidades/ataques
  - `on_player_leave`: Limpeza ao desconectar

- Estrutura Modular (VFS nativo via `loci2d` v0.6.5-sdk.4):
  - Todos os submódulos do mapa residem dentro de `server/scripts/default_arena/`.
  - A engine empacota automaticamente todos os `.lua` do diretório do mapa no VFS durante o boot e nos replays (`.loci`).
  - O comando `require("core.combat_system")` carrega `server/scripts/default_arena/core/combat_system.lua`.
  - `core/combat_system.lua`: Fórmulas matemáticas de mitigação, crítico, debuffs e dano.
  - `systems/character_factory.lua`: Fábrica de carregamento de personagens e habilidades com controle de cooldown e mana.
  - `respawn_system.lua`: Rastreamento de morte e temporizador de reviver jogadores.
  - `data/characters/*.lua`: Tabelas de atributos dos heróis (ex: warrior, mage, arya, default).
  - `data/skills/*.lua`: Definições e lógica de execução das habilidades.

## API do Servidor (Loci.Commands)

- `Loci.Commands.set_property(entity_id, key, value)`: Define propriedade
- `Loci.Commands.get_property(entity_id, key)`: Obtém propriedade
- `Loci.Commands.set_velocity(entity_id, {x, y})`: Define velocidade
- `Loci.Commands.destroy_entity(entity_id)`: Destroi entidade
- `Loci.get_entity(entity_id)`: Obtém dados da entidade
- `Loci.get_tick()`: Obtém tick atual (se disponível)
- `Loci.Log.info(msg)`: Log no servidor

## Observações Importantes

- O servidor loci2d usa callbacks específicos que são chamados automaticamente (`on_player_join`, `on_move_intent`, `on_action`, `on_player_leave`)
- A função global `require` é fornecida nativamente pelo VFS seguro da engine (a partir da v0.6.5-sdk.4), sem necessidade de polyfill
- Todos os arquivos `.lua` necessários para um mapa devem ficar contidos no diretório desse mapa para serem incluídos no VFS e nos replays
- As propriedades (hp, score, team, etc.) são sincronizadas automaticamente para os clientes
