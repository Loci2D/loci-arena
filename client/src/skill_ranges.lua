-- Alcances das habilidades (em unidades do mundo) conhecidos pelo cliente.
--
-- O servidor é a fonte da verdade: ele publica a propriedade de entidade `skill_ranges`
-- (formato "slash=16:7,fireball=64:9", ou seja, "<skill>=<alcance>:<raio da AoE>") junto de
-- `skills_list`. Este módulo interpreta essa propriedade para o indicador de mira e o VFX
-- acompanharem exatamente o que o servidor calcula.
--
-- Enquanto a propriedade não chegou (ou se o servidor for mais antigo), valem os DEFAULTS
-- abaixo. Um teste (tests/test_skills_and_combat_flow.lua) garante que eles nunca divergem
-- de server/scripts/default_arena/data/skills/*.lua.
--
-- Todos os valores estão em unidades do mundo; multiplique por VISUAL_SCALE para obter pixels.

local SkillRanges = {}

SkillRanges.DEFAULTS = {
    slash          = { range = 16.0, aoe = 7.0 },
    fury_reward    = { range = 24.0, aoe = 9.0 },
    whirlwind_dash = { range = 40.0, aoe = 10.0 },
    blade_throw    = { range = 56.0, aoe = 8.0 },
    fireball       = { range = 64.0, aoe = 9.0 },
}

-- Metadados de habilidades (cooldown em segundos a 30 Hz e custo de mana, alinhados a data/skills/*.lua)
SkillRanges.SKILL_META = {
    slash          = { label = "Slash",    cooldown = 0.5,  mana_cost = 10 },
    fireball       = { label = "Fireball", cooldown = 1.5,  mana_cost = 35 },
    fury_reward    = { label = "Fúria",    cooldown = 5.0,  mana_cost = 0  },
    whirlwind_dash = { label = "Dash",     cooldown = 6.0,  mana_cost = 25 },
    blade_throw    = { label = "Lâmina",   cooldown = 14.0, mana_cost = 45 },
    shield         = { label = "Escudo",   cooldown = 10.0, mana_cost = 20 },
}

-- Fallback de skills por personagem apenas quando a propriedade `skills_list` ainda não chegou da rede
SkillRanges.CHARACTER_DEFAULT_SKILLS = {
    arya    = { "slash", "fury_reward", "whirlwind_dash", "blade_throw" },
    default = { "slash" },
    mage    = { "fireball" },
    warrior = { "slash" },
}

local function get_entity_str_prop(entity, key)
    if not entity then return "" end
    local val = (entity.get and entity:get(key))
        or entity[key]
        or (entity.properties and entity.properties[key])
    if val == nil then return "" end
    return tostring(val)
end

--- Resolve o nome da habilidade equipada no `slot_index` (1..4) para a entidade,
--- respeitando `skills_list` e `character_name` ativos (retorna `nil` se o slot não existir no herói).
function SkillRanges.resolve_entity_skill(entity, slot_index)
    if not entity or type(slot_index) ~= "number" or slot_index < 1 then
        return nil
    end

    local list_str = get_entity_str_prop(entity, "skills_list")
    if list_str ~= "" then
        local idx = 1
        for skill in string.gmatch(list_str, "[^,]+") do
            local trimmed = string.match(skill, "^%s*(.-)%s*$")
            if idx == slot_index then
                return (trimmed and trimmed ~= "") and string.lower(trimmed) or nil
            end
            idx = idx + 1
        end
        return nil
    end

    local char_name = string.lower(get_entity_str_prop(entity, "character_name"))
    if char_name == "" then
        char_name = "default"
    end
    local defaults = SkillRanges.CHARACTER_DEFAULT_SKILLS[char_name] or SkillRanges.CHARACTER_DEFAULT_SKILLS.default
    return defaults and defaults[slot_index] or nil
end

--- Retorna os metadados (`label`, `cooldown`, `mana_cost`) de uma habilidade.
function SkillRanges.meta(skill_name)
    if not skill_name then return nil end
    return SkillRanges.SKILL_META[string.lower(tostring(skill_name))]
end

local published = {}
local last_raw = nil

--- Interpreta "slash=16:7,fireball=64:9" em { slash = {range=16, aoe=7}, ... }.
--- Entradas malformadas (sem "=", sem ":", não numéricas ou negativas) são descartadas.
function SkillRanges.parse(raw)
    local result = {}
    if type(raw) ~= "string" or raw == "" then
        return result
    end
    for entry in string.gmatch(raw, "[^,]+") do
        local name, range_str, aoe_str = string.match(entry, "^%s*([%w_]+)%s*=%s*([%d%.]+)%s*:%s*([%d%.]+)%s*$")
        local range = tonumber(range_str)
        local aoe = tonumber(aoe_str)
        if name and range and aoe then
            result[name] = { range = range, aoe = aoe }
        end
    end
    return result
end

--- Atualiza os valores publicados pelo servidor. Chamar a cada frame é barato: só reinterpreta
--- quando a string muda. Uma string vazia/inválida não apaga o que já era válido.
function SkillRanges.update(raw)
    if type(raw) ~= "string" or raw == last_raw then
        return
    end
    last_raw = raw
    local parsed = SkillRanges.parse(raw)
    if next(parsed) ~= nil then
        published = parsed
    end
end

--- Volta para os padrões embutidos (descarta o que o servidor publicou).
function SkillRanges.reset()
    published = {}
    last_raw = nil
end

local function lookup(skill_name)
    return published[skill_name] or SkillRanges.DEFAULTS[skill_name]
end

--- Alcance da habilidade em unidades do mundo (ou `fallback` se desconhecida).
function SkillRanges.range(skill_name, fallback)
    local entry = lookup(skill_name)
    return entry and entry.range or fallback
end

--- Raio da AoE da habilidade em unidades do mundo (ou `fallback` se desconhecida).
function SkillRanges.aoe(skill_name, fallback)
    local entry = lookup(skill_name)
    return entry and entry.aoe or fallback
end

return SkillRanges
