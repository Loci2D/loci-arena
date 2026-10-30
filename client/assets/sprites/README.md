# Sprites dos Personagens (Loci Arena)

Esta pasta contém as texturas de pixel art dos personagens para o cliente Love2D.

## Padrão Técnico dos Sprites (Pixelab)
- **Resolução nativa**: 32x32 pixels (PNG com canal alfa RGBA).
- **Filtragem**: `nearest`, `nearest` (mantém nitidez pura do pixel art sem blur bilinear).
- **Pivô (Origem)**: Pés do personagem, base central inferior (`ox = 16`, `oy = 32`).
- **Nomenclatura**: `<nome_personagem>.png` em minúsculas (ex: `arya.png`).
- **Direção padrão do sprite (Facing)**: Olhando para a direita (+X). O cliente espelha automaticamente no eixo X quando o personagem se move para a esquerda.

Quando um arquivo de sprite for adicionado nesta pasta, o cliente irá carregá-lo e vinculá-lo dinamicamente à entidade correspondente. Caso o sprite ainda não exista, um placeholder padronizado de 32x32px com indicador de facing é renderizado automaticamente.
