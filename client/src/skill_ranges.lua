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

-- Convenção única de escala do projeto (espelha ArenaBounds e CombatSystem.CONST no servidor)
SkillRanges.SCALE = {
    VISUAL_SCALE = 8,             -- 1 unidade do mundo = 8 px (viewport 1280x720 = 160x90 u)
    PLAYER_COLLIDER_RADIUS = 2.0, -- Raio físico autoritativo no servidor (32 px de diâmetro)
    SPRITE_BASE_SIZE = 32,        -- Tamanho base de referência do sprite em px
    SPRITE_SCALE = 2,             -- Escala visual 2x (64 px = 8.0 u de altura em perspectiva 2.5D)
    BODY_CENTER_OFFSET_U = 4.0,   -- ((32 * 2) / 2) / 8 = 4.0 u (32 px) acima do pivô dos pés
}

SkillRanges.DEFAULTS = {
    slash          = { range = 16.0, aoe = 7.0 },
    fury_reward    = { range = 24.0, aoe = 9.0 },
    whirlwind_dash = { range = 40.0, aoe = 10.0 },
    blade_throw    = { range = 56.0, aoe = 8.0 },
    fireball       = { range = 64.0, aoe = 9.0 },
}

-- Multiplicadores de amostragem e ponto focal alinhados a server/scripts/default_arena/data/skills/*.lua
SkillRanges.DETECTION_PROFILES = {
    slash          = { kind = "samples",    sample_factors = { 0.25, 0.5 }, aim_factor = 0.5 },
    fury_reward    = { kind = "samples",    sample_factors = { 0.2, 0.5 },  aim_factor = 0.5 },
    fireball       = { kind = "impact_aoe", impact_factor = 0.7,            aim_factor = 0.7 },
    whirlwind_dash = { kind = "sweep",      impact_factor = 1.0,            aim_factor = 1.0 },
    blade_throw    = { kind = "projectile", impact_factor = 1.0,            aim_factor = 1.0, proj_radius = 1.5 },
}

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

--- Distância focal usada pelo indicador de mira no chão (alinha o círculo de AoE ao centro real de impacto/amostragem no servidor).
function SkillRanges.aim_distance(skill_name, fallback)
    local r = SkillRanges.range(skill_name)
    if not r then
        return fallback
    end
    local profile = SkillRanges.DETECTION_PROFILES[skill_name]
    local factor = (profile and profile.aim_factor) or 1.0
    return r * factor
end

--- Retorna a geometria de detecção da skill (distâncias dos círculos de acerto e raio de AoE em unidades do mundo)
--- para visualização no overlay de debug e validação contra o servidor.
function SkillRanges.get_detection_geometry(skill_name)
    local entry = lookup(skill_name)
    if not entry then
        return nil
    end
    local profile = SkillRanges.DETECTION_PROFILES[skill_name]
    local distances = {}
    if profile and profile.sample_factors then
        for _, f in ipairs(profile.sample_factors) do
            table.insert(distances, entry.range * f)
        end
    else
        local factor = (profile and profile.impact_factor) or 1.0
        table.insert(distances, entry.range * factor)
    end
    return {
        kind = (profile and profile.kind) or "impact_aoe",
        range = entry.range,
        aoe = entry.aoe,
        aim_distance = SkillRanges.aim_distance(skill_name, entry.range),
        distances = distances,
        proj_radius = profile and profile.proj_radius or nil,
    }
end

return SkillRanges
