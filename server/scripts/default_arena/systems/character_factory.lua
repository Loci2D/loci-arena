-- Character Factory
-- Responsável por carregar tabelas de dados e instanciar personagens e habilidades.
local CombatSystem = require("core.combat_system")

local CharacterFactory = {}

-- Caches em memória
local character_cache = {}
local skill_cache = {}

-- Rastreamento de cooldowns por entidade: { [entity_id] = { [skill_name] = tick_when_ready } }
local entity_cooldowns = {}
local current_tick = 0

-- Atualizado a cada tick do servidor
function CharacterFactory.update_tick(tick)
    current_tick = tick or (current_tick + 1)
end

function CharacterFactory.get_current_tick()
    return current_tick
end

-- Carregar arquivo de personagem via require
function CharacterFactory.load_character(character_name)
    if character_cache[character_name] then
        return character_cache[character_name]
    end

    local ok, data = pcall(require, "default_arena.data.characters." .. character_name)
    if not ok or not data then
        ok, data = pcall(require, "data.characters." .. character_name)
    end

    if not ok or type(data) ~= "table" then
        if Loci and Loci.Log then
            Loci.Log.error("[CharacterFactory] Falha ao carregar personagem '" .. tostring(character_name) .. "': " .. tostring(data))
        end
        return nil
    end

    character_cache[character_name] = data
    return data
end

-- Carregar arquivo de habilidade via require
function CharacterFactory.load_skill(skill_name)
    if skill_cache[skill_name] then
        return skill_cache[skill_name]
    end

    local ok, data = pcall(require, "default_arena.data.skills." .. skill_name)
    if not ok or not data then
        ok, data = pcall(require, "data.skills." .. skill_name)
    end

    if not ok or type(data) ~= "table" then
        if Loci and Loci.Log then
            Loci.Log.error("[CharacterFactory] Falha ao carregar habilidade '" .. tostring(skill_name) .. "': " .. tostring(data))
        end
        return nil
    end

    skill_cache[skill_name] = data
    return data
end

-- Instancia os atributos e habilidades do personagem em uma entidade
function CharacterFactory.create_character(entity_id, character_name)
    character_name = character_name or "default"
    local char_data = CharacterFactory.load_character(character_name)

    if not char_data then
        if Loci and Loci.Log then
            Loci.Log.warn("[CharacterFactory] Personagem '" .. character_name .. "' não encontrado, usando fallback 'default'")
        end
        char_data = CharacterFactory.load_character("default")
    end

    if not char_data then
        if Loci and Loci.Log then
            Loci.Log.error("[CharacterFactory] Não foi possível instanciar nenhum personagem para " .. tostring(entity_id))
        end
        return false
    end

    local attrs = char_data.attributes or {}
    local max_hp = attrs.max_hp or 5000
    local phys_def = attrs.phys_def or 100
    local mag_def = attrs.mag_def or 50
    local mana = attrs.mana or 100
    local max_mana = attrs.max_mana or mana
    local move_speed = attrs.move_speed or 3.0

    -- 1. Inicializa atributos base no CombatSystem
    CombatSystem.init_entity(entity_id, max_hp, phys_def, mag_def)

    -- 2. Define propriedades de controle e gameplay
    Loci.Commands.set_property(entity_id, "character_name", char_data.name or character_name)
    Loci.Commands.set_property(entity_id, "role", char_data.role or "fighter")
    Loci.Commands.set_property(entity_id, "mana", tostring(mana))
    Loci.Commands.set_property(entity_id, "max_mana", tostring(max_mana))
    Loci.Commands.set_property(entity_id, "move_speed", tostring(move_speed))
    Loci.Commands.set_property(entity_id, "hp_regen", tostring(attrs.hp_regen or 10))
    Loci.Commands.set_property(entity_id, "mana_regen", tostring(attrs.mana_regen or 5))

    -- 3. Lista de habilidades
    local skills_list = char_data.skills or {}
    Loci.Commands.set_property(entity_id, "skills_list", table.concat(skills_list, ","))

    -- 4. Inicializa tabela de cooldowns local
    entity_cooldowns[entity_id] = {}

    if Loci and Loci.Log then
        Loci.Log.info(string.format("[CharacterFactory] Entidade %s configurada como '%s' (HP: %d, Mana: %d)",
            tostring(entity_id), char_data.name or character_name, max_hp, mana))
    end

    return true
end

-- Limpa estado da entidade ao sair
function CharacterFactory.on_entity_remove(entity_id)
    entity_cooldowns[entity_id] = nil
end

-- Valida se a entidade possui a habilidade
function CharacterFactory.has_skill(entity_id, skill_name)
    local list_str = Loci.get_entity_property(entity_id, "skills_list")
    if not list_str or list_str == "" then return false end
    for skill in string.gmatch(list_str, "[^,]+") do
        if skill == skill_name then
            return true
        end
    end
    return false
end

-- Retorna a habilidade equipada pelo slot/índice (1-based)
function CharacterFactory.get_skill_by_slot(entity_id, slot_index)
    local list_str = Loci.get_entity_property(entity_id, "skills_list")
    if not list_str or list_str == "" then return nil end
    local idx = 1
    for skill in string.gmatch(list_str, "[^,]+") do
        if idx == slot_index then
            return skill
        end
        idx = idx + 1
    end
    return nil
end

-- Verifica se pode executar a habilidade (vida, mana, cooldown)
function CharacterFactory.can_cast(entity_id, skill_data)
    local hp = tonumber(Loci.get_entity_property(entity_id, "hp") or "0") or 0
    if hp <= 0 then
        return false, "Entity is dead"
    end

    local mana = tonumber(Loci.get_entity_property(entity_id, "mana") or "0") or 0
    if skill_data.mana_cost and mana < skill_data.mana_cost then
        return false, "Insufficient mana"
    end

    local cooldowns = entity_cooldowns[entity_id]
    if cooldowns and cooldowns[skill_data.id] then
        if current_tick < cooldowns[skill_data.id] then
            return false, "Skill is on cooldown"
        end
    end

    return true
end

-- Consome mana da entidade
function CharacterFactory.consume_mana(entity_id, amount)
    local mana = tonumber(Loci.get_entity_property(entity_id, "mana") or "0") or 0
    mana = math.max(0, mana - amount)
    Loci.Commands.set_property(entity_id, "mana", tostring(mana))
end

-- Registra cooldown
function CharacterFactory.trigger_cooldown(entity_id, skill_id, cooldown_ticks)
    if not entity_cooldowns[entity_id] then
        entity_cooldowns[entity_id] = {}
    end
    entity_cooldowns[entity_id][skill_id] = current_tick + (cooldown_ticks or 0)
end

-- Executa a habilidade
function CharacterFactory.execute_skill(entity_id, skill_name, aim_x, aim_y)
    local skill_data = CharacterFactory.load_skill(skill_name)
    if not skill_data then
        return false, "Skill '" .. tostring(skill_name) .. "' not found"
    end

    if not CharacterFactory.has_skill(entity_id, skill_name) then
        return false, "Entity does not possess skill '" .. tostring(skill_name) .. "'"
    end

    local can_cast, reason = CharacterFactory.can_cast(entity_id, skill_data)
    if not can_cast then
        return false, reason
    end

    if skill_data.on_execute then
        local ok, err = skill_data.on_execute(entity_id, aim_x, aim_y, skill_data)
        if not ok then
            return false, err or "Failed to execute skill"
        end
    end

    if skill_data.mana_cost and skill_data.mana_cost > 0 then
        CharacterFactory.consume_mana(entity_id, skill_data.mana_cost)
    end

    if skill_data.cooldown and skill_data.cooldown > 0 then
        CharacterFactory.trigger_cooldown(entity_id, skill_data.id, skill_data.cooldown)
    end

    return true
end

-- Limpar cache
function CharacterFactory.clear_cache()
    character_cache = {}
    skill_cache = {}
end

return CharacterFactory
