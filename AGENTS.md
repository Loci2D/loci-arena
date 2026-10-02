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

- `server/scripts/default_arena/projectile_system.lua`: Sistema de tiro (adicionado)
  - Usa raycast instantâneo para detecção de colisão
  - Aplica dano via `Loci.Commands.set_property(entity_id, "hp", new_hp)`
  - Cooldown de 15 ticks (0.5s a 30Hz)
  - Alcance de 200 unidades
  - Dano de 10 por acerto

## API do Servidor (Loci.Commands)

- `Loci.Commands.set_property(entity_id, key, value)`: Define propriedade
- `Loci.Commands.get_property(entity_id, key)`: Obtém propriedade
- `Loci.Commands.set_velocity(entity_id, {x, y})`: Define velocidade
- `Loci.Commands.destroy_entity(entity_id)`: Destroi entidade
- `Loci.get_entity(entity_id)`: Obtém dados da entidade
- `Loci.get_tick()`: Obtém tick atual (se disponível)
- `Loci.Log.info(msg)`: Log no servidor

## Observações Importantes

- O servidor loci2d usa callbacks específicos que são chamados automaticamente
- Não há função `on_tick` padrão documentada no código existente
- O sistema de projéteis usa raycast instantâneo em vez de projéteis físicos porque a API para spawn de entidades dinâmicas não está clara
- As propriedades (hp, score, team) são sincronizadas automaticamente para os clientes
