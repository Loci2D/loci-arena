# Loci Arena

> **Jogo 2D Multiplayer de Arena desenvolvido com Love2D e loci2d server.**

Este repositório contém o código do **jogo** (cliente e regras de gameplay do servidor). A engine de rede e física autoritativa ([loci2d](https://github.com/Loci2D/loci2d)) roda como um processo separado através de um binário pré-compilado, garantindo determinismo, sincronização e desacoplamento do código de rede.

---

## Estrutura de Pastas

```text
loci-arena/
├── client/                     # Jogo no Love2D (Visual, som, UI, input)
│   ├── assets/                 # Sprites, efeitos sonoros, músicas e fontes
│   │   ├── sprites/
│   │   └── audio/
│   ├── src/                    # Módulos do cliente (cenas, entidades, HUD)
│   ├── loci2d/                 # SDK Love2D do loci2d (gerenciado via setup_sdk.sh)
│   ├── conf.lua                # Configuração da janela do Love2D
│   └── main.lua                # Ponto de entrada do cliente
│
├── server/                     # Lógica autoritativa do servidor
│   ├── scripts/
│   │   └── default_arena/      # Regras do jogo em Lua (empacotadas no VFS nativo)
│   │       ├── core/           # Sistema de combate (mitigação, crítico, escudos)
│   │       ├── systems/        # Fábrica de personagens e habilidades
│   │       ├── data/           # Atributos de heróis (characters/) e skills (skills/)
│   │       ├── respawn_system.lua
│   │       └── main.lua        # Callbacks autoritativos (join, move, action, tick)
│   └── .env.example            # Configurações de porta e tick-rate
│
├── bin/                        # Binário executável do loci2d (.gitignore)
├── scripts/                    # Scripts utilitários de execução
│   ├── setup_engine.sh         # Obtém o binário correto da engine loci2d
│   ├── setup_sdk.sh            # Configura o SDK Love2D (symlink local ou GitHub release)
│   ├── setup_client.sh         # Instala e verifica dependências do cliente (Love2D, Lua e SDK)
│   ├── run_server.sh           # Inicia o servidor com os scripts locais
│   └── run_client.sh           # Inicia o cliente Love2D (com verificação automática)
│
├── .loci2d-version             # Versão travada da engine loci2d
├── .loci2d-sdk-version         # Versão travada do SDK Love2D (sdk-love2d)
└── README.md
```

---

## Como Executar

### 1. Pré-requisitos
- Bash/Terminal (Linux, macOS ou WSL/Git Bash no Windows).
- [Love2D](https://love2d.org) (v11.x+) e [Lua](https://www.lua.org) (instalados automaticamente pelo script ou manualmente).

### 2. Configurar a Engine
Para obter o binário do servidor compatível com esta versão do jogo:
```bash
./scripts/setup_engine.sh
```
*(Se você tem o repositório `loci2d` clonado na mesma pasta pai, o script copiará o binário automaticamente).*

### 3. Rodar o Servidor
Abra um terminal e execute:
```bash
./scripts/run_server.sh
```

### 4. Rodar o Cliente
Em outro terminal (ou múltiplos para testar mais de um jogador):
```bash
./scripts/run_client.sh
```
*(Se o Love2D ou o Lua não estiverem instalados, o script executará `./scripts/setup_client.sh` para instalar automaticamente as dependências).*

---

## Controles Padrão
- **WASD / Setas**: Movimentação
- **Espaço / Clique**: Ação / Habilidade primária
- **F3**: Alternar painel de depuração (Ping, FPS, Ticks, Entidades)

---

## Fluxo de Git e Branches (Guia para a Turma)

Para evitar conflitos de código e manter o projeto sempre jogável:

1. **`main`**: Versão estável. Somente código testado e funcionando vai para a `main`.
2. **`develop`**: Branch de integração onde novas funcionalidades são combinadas e testadas.
3. **Branches de Feature**: Crie uma branch a partir de `develop` para cada tarefa:
   - `git checkout develop`
   - `git checkout -b feat/nome-da-feature`
4. **Padrão de Nomenclatura**:
   - `feat/client-particle-effects` (efeitos visuais no cliente)
   - `feat/server-fireball-spell` (nova magia no servidor)
   - `feat/ui-scoreboard` (placar de pontuação)
   - `fix/hitbox-offset` (correção de bug)

### Onde devo mexer?
- **Gráficos, Sons, HUD e Efeitos Visuais**: mexa em `client/` (Love2D).
- **Dano, Vida, Pontos, Regras de Vitória e Magias**: mexa em `server/scripts/default_arena/main.lua` (Lua autoritativo).
