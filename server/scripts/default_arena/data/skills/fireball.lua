-- Fireball Skill Data
-- Habilidade de exemplo: bola de fogo que causa dano em área
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
    id = "fireball",

    -- Nome para exibição
    name = "Fireball",

    -- Descrição
    description = "Lança uma bola de fogo que causa dano em área",

    -- Custo de mana
    mana_cost = 30,

    -- Cooldown em ticks (30 ticks = 1 segundo a 30Hz)
    cooldown = 60,

    -- Alcance em unidades
    range = 300,

    -- Dano base
    damage = 40,

    -- Tipo de dano
    damage_type = "fire",

    -- Raio de área de efeito
    aoe_radius = 50,

    -- Função de execução da skill
    -- Parâmetros: entity_id, target_x, target_y, skill_data, gas_engine
    on_execute = function(entity_id, target_x, target_y, skill_data, gas)
        Log_info("[Fireball] Entity " .. tostring(entity_id) .. " casting fireball at (" .. target_x .. ", " .. target_y .. ")")

        -- Obter posição da entidade
        local pos_x = Commands_get_property(entity_id, "x") or 0
        local pos_y = Commands_get_property(entity_id, "y") or 0
        -- Calcular distância até o alvo
        local dx = target_x - pos_x
        local dy = target_y - pos_y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        -- Verificar alcance
        if distance > skill_data.range then
            Log_warn("[Fireball] Target out of range: " .. distance .. " > " .. skill_data.range)
            return false, "Target out of range"
        end

        -- TODO: Implementar spawn de projétil ou dano instantâneo em área
        -- Por enquanto, vamos simular dano instantâneo no alvo
        -- Em produção, isso deveria criar um projétil via Loci.Commands.spawn_projectile()

        -- Simulação: aplicar dano a entidades na área (exemplo simplificado)
        -- Em produção, usaríamos Loci.Commands.get_entities_in_radius(target_x, target_y, skill_data.aoe_radius)

        Log_info("[Fireball] Skill executed successfully (damage: " .. skill_data.damage .. ", aoe_radius: " .. skill_data.aoe_radius .. ")")

        return true
    end
}
