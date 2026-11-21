-- AutoAim - Mira automática em touch/quick-cast.
--
-- Quando o jogador aciona uma habilidade sem direção manual explícita
-- (botões touch 1-2 e quick tap dos botões 3-4), este módulo procura o
-- inimigo vivo mais próximo (outro time, dentro do alcance de detecção)
-- e devolve o vetor de direção normalizado até ele. Sem inimigo próximo,
-- retorna nil para o chamador aplicar o fallback (direção de movimento /
-- última direção).
--
-- Módulo puro (sem dependência de love.*) para permitir testes unitários.

local AutoAim = {}

-- Alcance de detecção padrão (unidades do mundo) quando a habilidade do slot
-- não tem alcance conhecido via SkillRanges.
AutoAim.DEFAULT_MAX_RANGE = 64.0

local function read_prop(ent, key)
    if not ent then return nil end
    if type(ent.get) == "function" then
        local v = ent:get(key)
        if v ~= nil then return v end
    end
    if ent.properties then
        local v = ent.properties[key]
        if v ~= nil then return v end
    end
    return ent[key]
end

local function is_dead(ent)
    local d = read_prop(ent, "is_dead")
    if d == true or d == "true" or d == 1 or d == "1" then return true end
    local hp = tonumber(read_prop(ent, "hp"))
    if hp and hp <= 0 then return true end
    return false
end

local function is_player_entity(ent)
    local t = read_prop(ent, "entity_type")
    if t == nil then return true end
    local lt = string.lower(tostring(t))
    return lt == "player" or lt == "hero" or lt == "character"
end

--- Encontra o inimigo vivo mais próximo dentro de `max_range` (unidades do mundo).
--- Retorna a entidade alvo ou nil. Requer que ambos os times sejam conhecidos
--- e diferentes — entidades sem `team` sincronizado nunca são miradas.
function AutoAim.find_nearest_enemy(my_entity, entities, max_range)
    if not my_entity or type(entities) ~= "table" then return nil end
    local range = tonumber(max_range) or AutoAim.DEFAULT_MAX_RANGE
    if range <= 0 then return nil end

    local my_team = read_prop(my_entity, "team")
    if my_team == nil or my_team == "" then return nil end
    my_team = tostring(my_team)

    local mx = tonumber(my_entity.x) or 0
    local my = tonumber(my_entity.y) or 0
    local max_d2 = range * range

    local best, best_d2 = nil, nil
    for _, ent in pairs(entities) do
        if ent and ent.id ~= my_entity.id
            and is_player_entity(ent)
            and not is_dead(ent) then
            local team = read_prop(ent, "team")
            if team ~= nil and team ~= "" and tostring(team) ~= my_team then
                local dx = (tonumber(ent.x) or 0) - mx
                local dy = (tonumber(ent.y) or 0) - my
                local d2 = dx * dx + dy * dy
                if d2 <= max_d2 and (best_d2 == nil or d2 < best_d2) then
                    best, best_d2 = ent, d2
                end
            end
        end
    end
    return best
end

--- Retorna dx, dy normalizados apontando para o inimigo mais próximo,
--- ou nil quando não há alvo válido (inclui alvo na mesma posição do caster).
function AutoAim.aim_at_nearest_enemy(my_entity, entities, max_range)
    local target = AutoAim.find_nearest_enemy(my_entity, entities, max_range)
    if not target then return nil end

    local dx = (tonumber(target.x) or 0) - (tonumber(my_entity.x) or 0)
    local dy = (tonumber(target.y) or 0) - (tonumber(my_entity.y) or 0)
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 1e-6 then return nil end
    return dx / len, dy / len, target
end

return AutoAim
