-- Slash Skill Data
-- Habilidade de exemplo: ataque corpo-a-corpo em área frontal
-- Crie novas habilidades alterando apenas os valores nesta tabela

-- Safe wrapper for Loci API
local function Log_info(msg)
    local Loci = _G.Loci
    if Loci and Loci.Log and Loci.Log.info then
        Loci.Log.info(msg)
    end
end

local function Log_warn(msg)
    local Loci = _G.Loci
    if Loci and Loci.Log and Loci.Log.warn then
        Loci.Log.warn(msg)
    end
end

local function Commands_get_property(id, key)
    local Loci = _G.Loci
    -- Tenta obter via Commands primeiro
    if Loci and Loci.Commands and Loci.Commands.get_property then
        local value = Loci.Commands.get_property(id, key)
        if value ~= nil then
            return value
        end
    end
    -- Fallback para armazenamento local do GAS Engine
    local GasEngine = _G.GasEngine
    if GasEngine and GasEngine._get_attribute_local then
        return GasEngine._get_attribute_local(id, key)
    end
    return nil
end

return {
    -- Identificador único da skill
    id = "slash",

    -- Nome para exibição
    name = "Slash",

    -- Descrição
    description = "Ataque corporal em área frontal",

    -- Custo de mana
    mana_cost = 10,

    -- Cooldown em ticks (30 ticks = 1 segundo a 30Hz)
    cooldown = 30,

    -- Alcance em unidades
    range = 60,

    -- Dano base
    damage = 25,

    -- Tipo de dano
    damage_type = "physical",

    -- Raio de área de efeito frontal
    aoe_radius = 40,

    -- Ângulo do cone frontal (em graus)
    cone_angle = 90,

    -- Função de execução da skill
    -- Parâmetros: entity_id, target_x, target_y, skill_data, gas_engine
    on_execute = function(entity_id, target_x, target_y, skill_data, gas)
        Log_info("[Slash] Entity " .. tostring(entity_id) .. " performing slash at (" .. target_x .. ", " .. target_y .. ")")

        -- Obter posição da entidade
        local pos_x = Commands_get_property(entity_id, "x") or 0
        local pos_y = Commands_get_property(entity_id, "y") or 0
        
        -- Calcular distância até o alvo
        local dx = target_x - pos_x
        local dy = target_y - pos_y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        -- Verificar alcance
        if distance > skill_data.range then
            Log_warn("[Slash] Target out of range: " .. distance .. " > " .. skill_data.range)
            return false, "Target out of range"
        end

        -- TODO: Implementar detecção de entidades no cone frontal
        -- Em produção, usaríamos Loci.Commands.get_entities_in_cone(pos_x, pos_y, aim_angle, skill_data.cone_angle, skill_data.range)

        Log_info("[Slash] Skill executed successfully (damage: " .. skill_data.damage .. ", range: " .. skill_data.range .. ")")

        return true
    end
}
