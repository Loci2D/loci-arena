# Áudio do Loci Arena

Este diretório contém todos os arquivos de áudio do jogo.

## Estrutura

```
client/assets/audio/
├── SFX (Efeitos Sonoros Curtos)
│   ├── slash.wav              - Som de espada (Arya - Slash)
│   ├── fury_reward.wav        - Som de fúria (Arya - Fury Reward)
│   ├── whirlwind_dash.wav     - Som de dash (Arya - Whirlwind Dash)
│   ├── blade_throw.wav        - Som de arremesso (Arya - Blade Throw)
│   ├── fireball.wav          - Som de bola de fogo (Mage - Fireball)
│   ├── hit.wav               - Som de acerto normal
│   ├── critical.wav          - Som de acerto crítico (dano >= 350)
│   ├── shield_hit.wav        - Som de escudo absorvendo dano
│   └── death.wav             - Som de morte
│
└── BGM (Música de Fundo)
    └── bgm_arena.mp3         - Trilha sonora da arena (loop contínuo)
```

## Formatos Suportados

### SFX (Efeitos Sonoros)
- **Formato:** WAV (`.wav`)
- **Carregamento:** `"static"` (carregado inteiro na RAM)
- **Uso:** Sons curtos (< 1 segundo) com sobreposição simultânea
- **Volume:** Configurado em `client/src/audio_system.lua` (SOUND_CATALOG)

### BGM (Música de Fundo)
- **Formatos:** MP3 (`.mp3`), OGG (`.ogg`), ou WAV (`.wav`)
- **Carregamento:** `"stream"` (streaming, não carrega tudo na RAM)
- **Uso:** Trilhas longas em loop contínuo
- **Volume:** Configurado em `client/src/audio_system.lua` (BGM_CATALOG)
- **Loop:** Automático (`source:setLooping(true)`)

## Substituição de Arquivos

Para substituir os arquivos de áudio por versões finais:

1. **SFX:** Substitua os arquivos `.wav` mantendo os mesmos nomes
2. **BGM:** Substitua `bgm_arena.mp3` (ou converta para `.ogg` para tamanho menor)
3. **Atualize catálogos:** Se necessário, ajuste volumes em `client/src/audio_system.lua`

## Licença

- SFX atuais: CC0 1.0 Universal (público domínio)
- BGM atual: Placeholder (não é versão final)

## Sistema de Áudio

O sistema de áudio é implementado em `client/src/audio_system.lua`:

- **SFX:** Usa `clone()` para permitir sobreposição simultânea
- **BGM:** Usa streaming para arquivos longos, loop automático
- **Mute:** Tecla `M` silencia SFX e BGM, retoma BGM ao desmutar
- **Volume:** Controle independente de SFX e BGM via API

## Comandos

- `M` - Toggle mute/unmute (silencia SFX e BGM, retoma BGM ao desmutar)
- API Lua: `AudioSystem.play_bgm("arena")`, `AudioSystem.stop_bgm()`, etc.
