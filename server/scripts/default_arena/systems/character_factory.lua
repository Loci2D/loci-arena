-- Character Factory
-- Responsável por carregar tabelas de dados e instanciar personagens
-- Integra com o motor GAS-lite para inicialização de atributos

local CharacterFactory = {}
local GasEngine = _G.GasEngine

-- Safe wrappers for Loci API (busca dinamicamente de _G.Loci)
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

local function Log_error(msg)
    local Loci = _G.Loci
    if Loci and Loci.Log and Loci.Log.error then
        Loci.Log.error(msg)
    end
end

local function Commands_set_property(id, key, val)
    local Loci = _G.Loci
    -- Tenta usar Commands primeiro
    if Loci and Loci.Commands and Loci.Commands.set_property then
        Loci.Commands.set_property(id, key, val)
    end
    -- Acessa o armazenamento local do GAS Engine
    local GasEngine = _G.GasEngine
    if GasEngine and GasEngine._set_attribute_local then
        GasEngine._set_attribute_local(id, key, val)
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

-- Cache de personagens carregados
local character_cache = {}

-- Diretório base para carregar arquivos de dados
-- O loci2d roda com --scripts-dir apontando para server/scripts, então precisamos do caminho completo
-- Para testes externos, pode ser sobrescrito via _G.DATA_DIR
local DATA_DIR = _G.DATA_DIR or "scripts/default_arena/data/"

-- Tabela de fallback para atributos base (previne erros de nil)
-- TODO: Atributo Placeholder - substituir pelo Sistema de Atributos definitivo
local BASE_ATTRIBUTE_FALLBACK = {
    max_hp = 100,
    hp = 100,
    mana = 100,
    max_mana = 100,
    move_speed = 120,
    attack_power = 10,
    defense = 0,
    cooldown_reduction = 0,
    hp_regen = 0.1,
    mana_regen = 0.2
}

-- Carregar arquivo de personagem
function CharacterFactory.load_character(character_name)
    -- Verificar cache primeiro
    if character_cache[character_name] then
        return character_cache[character_name]
    end

    local file_path = DATA_DIR .. "characters/" .. character_name .. ".lua"
    local success, character_data = pcall(dofile, file_path)

    if not success then
        if Loci.Log and Log_error then
            Log_error("[CharacterFactory] Failed to load character '" .. character_name .. "': " .. tostring(character_data))
        end
        return nil
    end

    -- Validar dados mínimos
    if not character_data or type(character_data) ~= "table" then
        if Loci.Log and Log_error then
            Log_error("[CharacterFactory] Invalid character data for '" .. character_name .. "'")
        end
        return nil
    end
    
    -- Aplicar fallbacks para atributos ausentes
    character_data.attributes = character_data.attributes or {}
    -- Fallback para max_hp
    if character_data.attributes.max_hp == nil then
        Log_warn("[CharacterFactory] Missing attribute 'max_hp' for '" .. character_name .. "', using fallback: 100")
        character_data.attributes.max_hp = 100
    end
    -- Fallback para hp
    if character_data.attributes.hp == nil then
        Log_warn("[CharacterFactory] Missing attribute 'hp' for '" .. character_name .. "', using fallback: 100")
        character_data.attributes.hp = 100
    end
    -- Fallback para mana
    if character_data.attributes.mana == nil then
        Log_warn("[CharacterFactory] Missing attribute 'mana' for '" .. character_name .. "', using fallback: 100")
        character_data.attributes.mana = 100
    end
    -- Fallback para max_mana
    if character_data.attributes.max_mana == nil then
        Log_warn("[CharacterFactory] Missing attribute 'max_mana' for '" .. character_name .. "', using fallback: 100")
        character_data.attributes.max_mana = 100
    end
    -- Fallback para move_speed
    if character_data.attributes.move_speed == nil then
        Log_warn("[CharacterFactory] Missing attribute 'move_speed' for '" .. character_name .. "', using fallback: 120")
        character_data.attributes.move_speed = 120
    end
    -- Fallback para attack_power
    if character_data.attributes.attack_power == nil then
        Log_warn("[CharacterFactory] Missing attribute 'attack_power' for '" .. character_name .. "', using fallback: 10")
        character_data.attributes.attack_power = 10
    end
    -- Fallback para defense
    if character_data.attributes.defense == nil then
        Log_warn("[CharacterFactory] Missing attribute 'defense' for '" .. character_name .. "', using fallback: 0")
        character_data.attributes.defense = 0
    end
    -- Fallback para cooldown_reduction
    if character_data.attributes.cooldown_reduction == nil then
        Log_warn("[CharacterFactory] Missing attribute 'cooldown_reduction' for '" .. character_name .. "', using fallback: 0")
        character_data.attributes.cooldown_reduction = 0
    end
    -- Fallback para hp_regen
    if character_data.attributes.hp_regen == nil then
        Log_warn("[CharacterFactory] Missing attribute 'hp_regen' for '" .. character_name .. "', using fallback: 0.1")
        character_data.attributes.hp_regen = 0.1
    end
    -- Fallback para mana_regen
    if character_data.attributes.mana_regen == nil then
        Log_warn("[CharacterFactory] Missing attribute 'mana_regen' for '" .. character_name .. "', using fallback: 0.2")
        character_data.attributes.mana_regen = 0.2
    end
    
    -- Garantir tags como tabela
    character_data.tags = character_data.tags or {}
    if type(character_data.tags) ~= "table" then
        character_data.tags = {character_data.tags}
    end

    -- Garantir skills como tabela
    character_data.skills = character_data.skills or {}
    if type(character_data.skills) ~= "table" then
        character_data.skills = {character_data.skills}
    end
    
    -- Cache e retornar
    character_cache[character_name] = character_data
    Log_info("[CharacterFactory] Character '" .. character_name .. "' loaded successfully")
    
    return character_data
end

-- Carregar arquivo de habilidade
function CharacterFactory.load_skill(skill_name)
    local file_path = DATA_DIR .. "skills/" .. skill_name .. ".lua"
    local success, skill_data = pcall(dofile, file_path)
    
    if not success then
        Log_error("[CharacterFactory] Failed to load skill '" .. skill_name .. "': " .. tostring(skill_data))
        return nil
    end
    
    -- Validar dados mínimos
    if not skill_data or type(skill_data) ~= "table" then
        Log_error("[CharacterFactory] Invalid skill data for '" .. skill_name .. "'")
        return nil
    end
    
    -- Aplicar fallbacks para propriedades ausentes
    skill_data.mana_cost = skill_data.mana_cost or 0
    skill_data.cooldown = skill_data.cooldown or 0
    skill_data.range = skill_data.range or 0
    skill_data.damage = skill_data.damage or 0
    
    Log_info("[CharacterFactory] Skill '" .. skill_name .. "' loaded successfully")
    
    return skill_data
end

-- Instanciar personagem em uma entidade
function CharacterFactory.create_character(entity_id, character_name)
    local character_data = CharacterFactory.load_character(character_name)
    
    if not character_data then
        Log_error("[CharacterFactory] Cannot create character '" .. character_name .. "': data not found")
        return false
    end
    
    -- Aplicar atributos base
    if character_data.attributes then
        local attrs = character_data.attributes
        if attrs.max_hp ~= nil then
            Commands_set_property(entity_id, "max_hp", attrs.max_hp)
        end
        if attrs.hp ~= nil then
            Commands_set_property(entity_id, "hp", attrs.hp)
        end
        if attrs.mana ~= nil then
            Commands_set_property(entity_id, "mana", attrs.mana)
        end
        if attrs.max_mana ~= nil then
            Commands_set_property(entity_id, "max_mana", attrs.max_mana)
        end
        if attrs.move_speed ~= nil then
            Commands_set_property(entity_id, "move_speed", attrs.move_speed)
        end
        if attrs.attack_power ~= nil then
            Commands_set_property(entity_id, "attack_power", attrs.attack_power)
        end
        if attrs.defense ~= nil then
            Commands_set_property(entity_id, "defense", attrs.defense)
        end
        if attrs.cooldown_reduction ~= nil then
            Commands_set_property(entity_id, "cooldown_reduction", attrs.cooldown_reduction)
        end
        if attrs.hp_regen ~= nil then
            Commands_set_property(entity_id, "hp_regen", attrs.hp_regen)
        end
        if attrs.mana_regen ~= nil then
            Commands_set_property(entity_id, "mana_regen", attrs.mana_regen)
        end
    end
    
    -- Aplicar tags iniciais
    -- NOTA: set_property não aceita tabelas no loci2d atual
    -- TODO: Implementar quando suporte a tabelas estiver disponível
    if character_data.tags and #character_data.tags > 0 then
        Log_info("[CharacterFactory] Character has " .. #character_data.tags .. " tags (not stored due to API limitation)")
    end
    
    -- Armazenar nome do personagem para referência
    Commands_set_property(entity_id, "character_name", character_name)
    
    -- Armazenar skills disponíveis como string concatenada (workaround para limitação de tabelas)
    -- Formato: "skill1,skill2,skill3"
    if character_data.skills and #character_data.skills > 0 then
        local skills_string = table.concat(character_data.skills, ",")
        GasEngine._set_attribute_local(entity_id, "skills_list", skills_string)
        Log_info("[CharacterFactory] Character has " .. #character_data.skills .. " skills: " .. skills_string)
    else
        GasEngine._set_attribute_local(entity_id, "skills_list", "")
        Log_info("[CharacterFactory] Character has no skills")
    end
    
    Log_info("[CharacterFactory] Character '" .. character_name .. "' instantiated on entity " .. tostring(entity_id))
    
    return true
end

-- Obter skill data de uma entidade
-- Verifica se a skill está na lista de skills do personagem
function CharacterFactory.get_entity_skill(entity_id, skill_name)
    -- Obter lista de skills do personagem
    local skills_string = GasEngine._get_attribute_local(entity_id, "skills_list") or ""
    
    -- Verificar se a skill está na lista
    if skills_string ~= "" then
        local skills_list = {}
        for skill in string.gmatch(skills_string, "[^,]+") do
            table.insert(skills_list, skill)
        end
        
        -- Verificar se skill_name está na lista
        local has_skill = false
        for _, skill in ipairs(skills_list) do
            if skill == skill_name then
                has_skill = true
                break
            end
        end
        
        if not has_skill then
            Log_warn("[CharacterFactory] Entity " .. tostring(entity_id) .. " does not have skill '" .. skill_name .. "'")
            return nil
        end
    else
        Log_warn("[CharacterFactory] Entity " .. tostring(entity_id) .. " has no skills")
        return nil
    end
    
    -- Carregar dados da skill
    return CharacterFactory.load_skill(skill_name)
end

-- Executar skill de uma entidade
function CharacterFactory.execute_skill(entity_id, skill_name, target_x, target_y)
    -- Verificar se entidade pode agir
    local can_act, act_error = GasEngine.can_cast(entity_id, skill_name)
    if not can_act then
        return false, act_error
    end
    
    -- Carregar dados da skill
    local skill_data = CharacterFactory.get_entity_skill(entity_id, skill_name)
    if not skill_data then
        return false, "Skill not found or not equipped"
    end
    
    -- Verificar e consumir mana
    if skill_data.mana_cost > 0 then
        local mana_success, mana_error = GasEngine.consume_mana(entity_id, skill_data.mana_cost)
        if not mana_success then
            return false, mana_error
        end
    end
    
    -- Verificar cooldown
    if skill_data.cooldown and skill_data.cooldown > 0 then
        local cooldown_success, cooldown_error = GasEngine.process_cooldown(entity_id, skill_name, skill_data.cooldown)
        if not cooldown_success then
            return false, cooldown_error
        end
    end
    
    -- Executar lógica da skill
    if skill_data.on_execute then
        local success, error_msg = skill_data.on_execute(entity_id, target_x, target_y, skill_data, GasEngine)
        if not success then
            return false, error_msg
        end
    end
    
    Log_info("[CharacterFactory] Entity " .. tostring(entity_id) .. " executed skill '" .. skill_name .. "'")
    
    return true
end

-- Limpar cache (útil para hot-reload em desenvolvimento)
function CharacterFactory.clear_cache()
    character_cache = {}
    Log_info("[CharacterFactory] Cache cleared")
end

return CharacterFactory
