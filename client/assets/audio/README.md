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
    └── bgm_arena.ogg         - Trilha sonora da arena (loop contínuo)
```

## Formatos Suportados

### SFX (Efeitos Sonoros)
- **Formato:** WAV (`.wav`)
- **Carregamento:** `"static"` (carregado inteiro na RAM)
- **Uso:** Sons curtos (< 1 segundo) com sobreposição simultânea
- **Volume:** Configurado em `client/src/audio_system.lua` (SOUND_CATALOG)

### BGM (Música de Fundo)
- **Formato recomendado:** OGG Vorbis (`.ogg`). Também aceitos: MP3 (`.mp3`) e WAV (`.wav`)
- **Por que OGG:** o MP3 inclui *padding* do encoder, que pode causar um pequeno corte audível quando o loop recomeça; o OGG repete sem emenda e fica menor
- **Carregamento:** `"stream"` (streaming, não carrega tudo na RAM)
- **Uso:** Trilhas longas em loop contínuo
- **Volume:** Configurado em `client/src/audio_system.lua` (BGM_CATALOG)
- **Loop:** Automático (`source:setLooping(true)`)

## Substituição de Arquivos

Para substituir os arquivos de áudio por versões finais:

1. **SFX:** Substitua os arquivos `.wav` mantendo os mesmos nomes
2. **BGM:** Substitua `bgm_arena.ogg` mantendo o nome, ou ajuste o `file` em `BGM_CATALOG`. Para converter: `ffmpeg -i entrada.mp3 -map_metadata -1 -c:a libvorbis -q:a 4 bgm_arena.ogg`
3. **Atualize catálogos:** Se necessário, ajuste volumes em `client/src/audio_system.lua`

## Licença

- SFX atuais: CC0 1.0 Universal (público domínio)

## Sistema de Áudio

O sistema de áudio é implementado em `client/src/audio_system.lua`:

- **SFX:** Usa `clone()` para permitir sobreposição simultânea
- **BGM:** Usa streaming para arquivos longos, loop automático
- **Mute:** Tecla `M` corta todo o áudio (SFX em andamento e BGM). A BGM guarda a posição e volta do mesmo ponto ao desmutar
- **Pausa:** `pause_bgm()` é explícita e sobrevive a mute/unmute; só `resume_bgm()` (ou `play_bgm()`) a retoma
- **Mutado:** `play_bgm()` com o áudio mutado apenas registra a faixa; ela começa a tocar ao desmutar
- **Troca de faixa:** `play_bgm(outra)` para a anterior; nunca há duas faixas tocando. Chamar a faixa que já está tocando não a reinicia
- **Arquivo ausente / headless:** a faixa é desabilitada com um log informativo, sem *beep* de fallback e sem erro
- **Volume:** Controle independente de SFX (`set_sfx_volume`) e BGM (`set_bgm_volume`), de 0.0 a 1.0. O de BGM vale na hora; o de SFX vale para os próximos efeitos
- **Ciclo de vida:** a BGM inicia quando o jogador local spawna e é parada em `love.quit()`

## Comandos

- `M` - Toggle mute/unmute (silencia SFX e BGM, retoma BGM ao desmutar)
- API Lua: `AudioSystem.play_bgm("arena")`, `AudioSystem.stop_bgm()`, etc.
