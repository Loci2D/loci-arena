# Áudio / SFX — Loci Arena

Pasta dedicada aos efeitos sonoros do cliente (`client/assets/audio/`), pré-carregados por [`client/src/audio_system.lua`](../../src/audio_system.lua).

## Como substituir um efeito sonoro no futuro

Basta substituir o arquivo `.wav` mantendo **exatamente o mesmo nome**. Caso algum arquivo seja removido, o cliente gera automaticamente um tom procedural placeholder para evitar falhas.

| Arquivo | Quando toca | Observação |
| :--- | :--- | :--- |
| `slash.wav` | Conjuração da skill `slash` | Placeholder .wav pronto para troca |
| `fireball.wav` | Conjuração da skill `fireball` | Placeholder .wav pronto para troca |
| `fury_reward.wav` | Conjuração da skill `fury_reward` | Placeholder .wav pronto para troca |
| `whirlwind_dash.wav` | Conjuração da skill `whirlwind_dash` | Placeholder .wav pronto para troca |
| `blade_throw.wav` | Conjuração da skill `blade_throw` | Placeholder .wav pronto para troca |
| `hit.wav` | Dano normal aplicado no `hp` (`< 350`) | Placeholder .wav pronto para troca |
| `critical.wav` | Dano crítico aplicado no `hp` (`>= 350`) | Placeholder .wav pronto para troca |
| `shield_hit.wav` | Absorção de dano no `shield` ou skill `shield` | Placeholder .wav pronto para troca |
| `death.wav` | Morte do jogador local (`is_dead`) | Placeholder .wav pronto para troca |
