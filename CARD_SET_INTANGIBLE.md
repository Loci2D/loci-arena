## Solicitação: Implementar API set_intangible no binário oficial

### **PROBLEMA**

Projeto: **Loci Arena** (gameplay server-authoritative)
Binário atual: **v0.6.5-sdk.3**

Fireballs/projetiles colidem fisicamente com o próprio dono, causando:
- Jogador é empurrado pela própria fireball
- Jogador fica preso/bloqueado pela própria fireball
- Comportamento inconsistente com gameplay esperado

### **O QUE JÁ FOI TENTADO**

1. **Spawn offset**: Aumentado de 5.0 → 10.0 → 15.0 → 20.0 → 30.0
   - Reduziu colisão inicial, mas não elimina colisão física
   - Jogador ainda é empurrado quando reverte movimento

2. **Colisão via script Lua**:
   - `on_collision`: verificação de dono antes de destruir
   - `on_tick`: filtro de entidades ao aplicar dano
   - Problema: colisão física acontece NO NÍVEL DO MOTOR (core physics), não no script Lua
   - Script pode ignorar lógica, mas motor ainda empurra fisicamente

3. **Propriedade `collision_enabled=false`**:
   - Tentado como propriedade de entidade
   - Não há evidência que o motor honra essa propriedade
   - Comportamento não mudou

4. **Verificação de API disponível**:
   - Runtime test: `API set_intangible NÃO disponível`
   - Runtime test: `API Physics.raycast disponível!`
   - Binário v0.6.5-sdk.3 não expõe `set_intangible`

### **SOLUÇÃO ESPERADA**

Conforme card do professor (Trello), a API `set_intangible` deve permitir:

```lua
-- Exemplo de uso esperado:
Loci.set_intangible(entity_id, true)  -- Ativa pass-through
Loci.set_intangible(entity_id, false) -- Desativa pass-through
```

**Comportamento esperado:**
- Fireball/projectile com `set_intangible=true` não colide fisicamente com NADA
- Usar apenas com dono (spawn com intangible, desativar após X ticks ou distância)
- Ou implementar collision masks/masks de categoria no motor

### **IMPACTO**

- **Blocker**: Gameplay básico de multiplayer está comprometido
- UX ruim: Jogador é empurrado pela própria habilidade
- Inviável continuar implementação de habilidades (dash, slow, shield) sem resolver

### **REFERÊNCIAS**

- Repositório do motor: https://github.com/Loci2D/loci2d
- Binário configurado: v0.6.5-sdk.3
- Commit mencionado pelo professor: branch main
- Card Trello do professor: menciona `set_intangible` como solução

### **PERGUNTAS**

1. A API `set_intangible` existe no código fonte atual?
2. Se existe, qual release vai incluir essa API?
3. Existe timeline estimada para próximo release?
4. Se não existe, qual solução alternativa é viável (collision masks, etc)?

---

**Prioridade**: Alta (Blocker de gameplay)
**Assignee**: Core Team
**Label**: engine-api, physics, collision
