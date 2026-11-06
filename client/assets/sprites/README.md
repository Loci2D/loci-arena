# Sprites dos Personagens (Loci Arena)

Esta pasta contém as texturas de pixel art dos personagens para o cliente Love2D.

## Padrão Técnico dos Sprites (Pixelab)
- **Resolução nativa**: 32x32 pixels (PNG com canal alfa RGBA).
- **Filtragem**: `nearest`, `nearest` (mantém nitidez pura do pixel art sem blur bilinear).
- **Pivô (Origem)**: Pés do personagem, base central inferior (`ox = 16`, `oy = 32`).
- **Perspectiva**: Low top-down.

## Estrutura Suportada

### 1. Conjunto Multi-direcional Completo (Padrão Oficial Pixelab - 8 Direções)
O cliente detecta automaticamente pastas com o nome do personagem contendo os 8 ângulos de rotação:
```text
client/assets/sprites/<nome_personagem>/
├── south.png         # Frente (olhando para a câmera / +Y)
├── south-east.png    # Diagonal inferior direita
├── east.png          # Direita (+X)
├── north-east.png    # Diagonal superior direita
├── north.png         # Costas (-Y)
├── north-west.png    # Diagonal superior esquerda
├── west.png          # Esquerda (-X)
└── south-west.png    # Diagonal inferior esquerda
```
O cliente seleciona dinamicamente a rotação com base no vetor de movimento do personagem, preservando a anatomia real (ex: lado correto de cicatrizes, olhos vendados e armas).

### 2. Imagem Única com Espelhamento (Fallback Simples)
Caso o personagem possua apenas um PNG simples:
- Arquivo: `assets/sprites/<nome_personagem>.png`
- Direção padrão: Olhando para a direita (+X). O cliente espelha automaticamente no eixo X quando o personagem se move para a esquerda.

### 3. Placeholder Procedural
Caso o personagem não possua sprite nem pasta de rotações, um placeholder padronizado de 32x32px com visor direcional é renderizado automaticamente nas cores da equipe (`me`, `enemy`, `dead`).
