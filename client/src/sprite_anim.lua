--
-- sprite_anim.lua
-- Sistema de sprites animados 8-direções genérico para Loci Arena
-- Suporta parsing de metadata.json do Pixelab, convenções de diretório,
-- fallback em camadas (direção mais próxima -> frame 1 -> rotação estática -> imagem única -> placeholder),
-- lazy loading com descarte LRU e máquina de estados de animação por entidade.
--

local json = require("src.json")

local SpriteAnim = {}

local DIRECTIONS_8 = {
    "east", "south-east", "south", "south-west",
    "west", "north-west", "north", "north-east"
}

-- Mapeamento de direção para índice 1..8
local DIR_TO_INDEX = {}
for i, d in ipairs(DIRECTIONS_8) do
    DIR_TO_INDEX[d] = i
end

-- Tabela de proximidade angular para direção mais próxima
local DIRECTION_FALLBACKS = {}
for i, dir in ipairs(DIRECTIONS_8) do
    local list = {}
    -- Proximidade 1 (45 graus de cada lado)
    local left1 = ((i - 2) % 8) + 1
    local right1 = (i % 8) + 1
    table.insert(list, DIRECTIONS_8[left1])
    table.insert(list, DIRECTIONS_8[right1])

    -- Proximidade 2 (90 graus)
    local left2 = ((i - 3) % 8) + 1
    local right2 = ((i + 1) % 8) + 1
    table.insert(list, DIRECTIONS_8[left2])
    table.insert(list, DIRECTIONS_8[right2])

    -- Proximidade 3 (135 graus)
    local left3 = ((i - 4) % 8) + 1
    local right3 = ((i + 2) % 8) + 1
    table.insert(list, DIRECTIONS_8[left3])
    table.insert(list, DIRECTIONS_8[right3])

    -- Proximidade 4 (180 graus / oposto)
    local opp = ((i + 3) % 8) + 1
    table.insert(list, DIRECTIONS_8[opp])

    DIRECTION_FALLBACKS[dir] = list
end

local DEFAULT_FPS = 11
local MAX_IMAGE_CACHE = 512
local SPRITE_BASE_SIZE = 32

-- Cache de sprite_set por char_name em lowercase
local loaded_characters = {}

-- Cache de imagens carregadas sob demanda com LRU
local image_cache = {}
local cache_count = 0
local cache_lru_counter = 0

-- Estados visuais/animação por entidade (máquina de estados)
local entity_states = {}

-- Helpers de I/O protegidos
local function file_exists(path)
    if not path or path == "" then return false end
    if love and love.filesystem and love.filesystem.getInfo then
        local info = love.filesystem.getInfo(path)
        if type(info) == "table" then
            return info.type ~= "directory"
        elseif type(info) == "boolean" then
            if not info then return false end
            local f = io.open(path, "r")
            if f then f:close(); return true end
            return false
        end
        return false
    end
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function dir_exists(path)
    if not path or path == "" then return false end
    if love and love.filesystem and love.filesystem.getInfo then
        local info = love.filesystem.getInfo(path)
        if type(info) == "table" then
            return info.type == "directory" or info.type == "symlink"
        elseif type(info) == "boolean" then
            if not info then return false end
            local ok, _, code = os.execute("test -d \"" .. path .. "\" 2>/dev/null")
            return (ok == true or code == 0 or ok == 0)
        end
        return false
    end
    local ok, _, code = os.execute("test -d \"" .. path .. "\" 2>/dev/null")
    return (ok == true or code == 0 or ok == 0)
end

local function read_text_file(path)
    if love and love.filesystem and love.filesystem.read then
        local content, size = love.filesystem.read(path)
        if content then return content end
    end
    local f = io.open(path, "r")
    if f then
        local c = f:read("*a")
        f:close()
        return c
    end
    return nil
end

local function load_lua_table(path)
    if love and love.filesystem and love.filesystem.load then
        local chunk, err = love.filesystem.load(path)
        if chunk then
            local ok, res = pcall(chunk)
            if ok and type(res) == "table" then
                return res
            end
        end
    end
    local chunk, err = loadfile(path)
    if chunk then
        local ok, res = pcall(chunk)
        if ok and type(res) == "table" then
            return res
        end
    end
    return nil
end

local function get_directory_items(path)
    if love and love.filesystem and love.filesystem.getDirectoryItems then
        return love.filesystem.getDirectoryItems(path) or {}
    end
    return {}
end

-- Cálculo de direção 8-way a partir de vetor
local function calc_direction_8way(dx, dy, fallback_dir)
    if not dx or not dy or (dx == 0 and dy == 0) then
        return fallback_dir or "south"
    end
    local angle = math.atan2(dy, dx)
    if angle < 0 then
        angle = angle + 2 * math.pi
    end
    local index = math.floor(((angle + math.pi / 8) % (2 * math.pi)) / (math.pi / 4))
    return DIRECTIONS_8[index + 1] or fallback_dir or "south"
end

-- Carregamento sob demanda com descarte LRU
local function load_image(path)
    if not path or path == "" then return nil, 0, 0 end

    local cached = image_cache[path]
    if cached then
        cache_lru_counter = cache_lru_counter + 1
        cached.lru = cache_lru_counter
        return cached.img, cached.w, cached.h
    end

    if not file_exists(path) then
        return nil, 0, 0
    end

    if not (love and love.graphics and love.graphics.newImage) then
        return nil, 0, 0
    end

    local ok, img = pcall(love.graphics.newImage, path)
    if not (ok and img) then
        return nil, 0, 0
    end

    img:setFilter("nearest", "nearest")
    local w = img:getWidth()
    local h = img:getHeight()

    -- Despejo LRU se limite excedido
    if cache_count >= MAX_IMAGE_CACHE then
        local oldest_k, oldest_lru = nil, math.huge
        for k, v in pairs(image_cache) do
            if v.lru < oldest_lru then
                oldest_lru = v.lru
                oldest_k = k
            end
        end
        if oldest_k then
            image_cache[oldest_k] = nil
            cache_count = cache_count - 1
        end
    end

    cache_lru_counter = cache_lru_counter + 1
    image_cache[path] = {
        img = img,
        w = w,
        h = h,
        lru = cache_lru_counter
    }
    cache_count = cache_count + 1

    return img, w, h
end

-- Resolução de pasta do personagem com variações de case e paths relativos
local function resolve_character_dir(char_name)
    if not char_name or char_name == "" then return nil, nil end

    local lower = string.lower(char_name)
    local cap = char_name:sub(1, 1):upper() .. char_name:sub(2):lower()
    local orig = char_name

    local variants = { lower, cap, orig }
    local base_prefixes = { "assets/sprites/", "client/assets/sprites/" }

    -- 1. Tentar pasta
    for _, prefix in ipairs(base_prefixes) do
        for _, v in ipairs(variants) do
            local dir = prefix .. v
            if dir_exists(dir) then
                return dir, "folder"
            end
        end
    end

    -- 2. Tentar arquivo único .png
    for _, prefix in ipairs(base_prefixes) do
        for _, v in ipairs(variants) do
            local p = prefix .. v .. ".png"
            if file_exists(p) then
                return p, "single"
            end
        end
    end

    return nil, nil
end

-- Parser de convenção de diretórios quando não há metadata.json
local function scan_directory_convention(char_dir)
    local states = {}
    local items = get_directory_items(char_dir)

    for _, item in ipairs(items) do
        local state_path = char_dir .. "/" .. item
        if dir_exists(state_path) and item ~= "rotations" and item ~= "animations" then
            local state_name = item
            local state_data = {
                name = state_name,
                rotations = {},
                animations = {},
                default_anim = nil,
                has_frames = false
            }

            -- 1. rotations/<dir>.png
            local rot_dir = state_path .. "/rotations"
            if dir_exists(rot_dir) then
                for _, dir in ipairs(DIRECTIONS_8) do
                    local rp = rot_dir .. "/" .. dir .. ".png"
                    if file_exists(rp) then
                        state_data.rotations[dir] = rp
                    end
                end
            end

            -- 2. animations/
            local anim_dir = state_path .. "/animations"
            if dir_exists(anim_dir) then
                local anim_items = get_directory_items(anim_dir)
                local is_direct_dirs = false
                for _, ai in ipairs(anim_items) do
                    if DIR_TO_INDEX[ai] then
                        is_direct_dirs = true
                        break
                    end
                end

                if is_direct_dirs then
                    -- animations/<dir>/frame_XXX.png
                    local anim_name = "default"
                    state_data.animations[anim_name] = {}
                    for _, dir in ipairs(DIRECTIONS_8) do
                        local dir_path = anim_dir .. "/" .. dir
                        if dir_exists(dir_path) then
                            local frames = {}
                            local f_items = get_directory_items(dir_path)
                            table.sort(f_items)
                            for _, f in ipairs(f_items) do
                                if f:match("%.png$") then
                                    table.insert(frames, dir_path .. "/" .. f)
                                end
                            end
                            if #frames > 0 then
                                state_data.animations[anim_name][dir] = frames
                                state_data.has_frames = true
                            end
                        end
                    end
                    state_data.default_anim = anim_name
                else
                    -- animations/<sub_anim>/<dir>/frame_XXX.png
                    for _, sub in ipairs(anim_items) do
                        local sub_path = anim_dir .. "/" .. sub
                        if dir_exists(sub_path) then
                            state_data.animations[sub] = {}
                            for _, dir in ipairs(DIRECTIONS_8) do
                                local dir_path = sub_path .. "/" .. dir
                                if dir_exists(dir_path) then
                                    local frames = {}
                                    local f_items = get_directory_items(dir_path)
                                    table.sort(f_items)
                                    for _, f in ipairs(f_items) do
                                        if f:match("%.png$") then
                                            table.insert(frames, dir_path .. "/" .. f)
                                        end
                                    end
                                    if #frames > 0 then
                                        state_data.animations[sub][dir] = frames
                                        state_data.has_frames = true
                                    end
                                end
                            end
                            if not state_data.default_anim then
                                state_data.default_anim = sub
                            end
                        end
                    end
                end
            end

            -- 3. Estrutura direta <state>/<dir>/frame_XXX.png (ex: morte)
            local has_direct_dir = false
            for _, dir in ipairs(DIRECTIONS_8) do
                local dir_path = state_path .. "/" .. dir
                if dir_exists(dir_path) then
                    has_direct_dir = true
                    break
                end
            end

            if has_direct_dir then
                local anim_name = state_data.default_anim or "default"
                if not state_data.animations[anim_name] then
                    state_data.animations[anim_name] = {}
                end
                for _, dir in ipairs(DIRECTIONS_8) do
                    local dir_path = state_path .. "/" .. dir
                    if dir_exists(dir_path) then
                        local frames = {}
                        local f_items = get_directory_items(dir_path)
                        table.sort(f_items)
                        for _, f in ipairs(f_items) do
                            if f:match("%.png$") then
                                table.insert(frames, dir_path .. "/" .. f)
                            end
                        end
                        if #frames > 0 then
                            state_data.animations[anim_name][dir] = frames
                            state_data.has_frames = true
                        end
                    end
                end
                state_data.default_anim = anim_name
            end

            states[state_name] = state_data
        end
    end

    return states
end

-- Parser de metadata.json do Pixelab
local function parse_metadata_json(char_dir, meta_json_str)
    local ok, data = pcall(json.decode, meta_json_str)
    if not (ok and data and type(data.states) == "table") then
        return nil
    end

    local states = {}
    for _, s in ipairs(data.states) do
        local folder = s.folder or (s.character and s.character.name)
        if folder and folder ~= "" then
            local state_data = {
                name = folder,
                rotations = {},
                animations = {},
                default_anim = nil,
                has_frames = false
            }

            local frames_info = s.frames or {}
            local rot_info = frames_info.rotations or {}
            for dir, rel_path in pairs(rot_info) do
                state_data.rotations[dir] = char_dir .. "/" .. rel_path
            end

            local anim_info = frames_info.animations or {}
            for anim_name, dir_dict in pairs(anim_info) do
                state_data.animations[anim_name] = {}
                for dir, frame_list in pairs(dir_dict) do
                    local full_frames = {}
                    for _, fp in ipairs(frame_list) do
                        table.insert(full_frames, char_dir .. "/" .. fp)
                    end
                    if #full_frames > 0 then
                        state_data.animations[anim_name][dir] = full_frames
                        state_data.has_frames = true
                    end
                end
                if not state_data.default_anim then
                    state_data.default_anim = anim_name
                end
            end

            states[folder] = state_data
        end
    end

    return states
end

-- Carregar conjunto completo do personagem
function SpriteAnim.load_character(char_name)
    if not char_name or char_name == "" then return nil end
    local key = string.lower(char_name)
    if loaded_characters[key] ~= nil then
        local c = loaded_characters[key]
        return (c ~= false and c) or nil
    end

    local resolved_path, path_type = resolve_character_dir(char_name)
    if not resolved_path then
        loaded_characters[key] = false
        return nil
    end

    local sprite_set = {
        name = key,
        base_dir = resolved_path,
        has_animations = false,
        has_rotations = false,
        single_image_path = nil,
        states = {},
        anim_map = {
            character = key,
            states = {
                idle = "Rotacao",
                walk = "andando",
                run = "correndo",
                death = "morte",
                ally_death = "aliado_morre"
            },
            skills = {
                slash = "Habilidade_1",
                fury_reward = "Habilidade_2",
                whirlwind_dash = "Habilidade_3",
                blade_throw = "Habilidade_4",
                [1] = "Habilidade_1",
                [2] = "Habilidade_2",
                [3] = "Habilidade_3",
                [4] = "Habilidade_4"
            },
            preferred_anims = {
                aliado_morre = "ela_caindo_no_chao_chorando",
                morte = "ela_caindo_no_chao_morta_apos_levar_um_golpe_fatal"
            },
            fps = DEFAULT_FPS
        }
    }

    if path_type == "folder" then
        -- 1. Carregar anim_map.lua específico se existir
        local anim_map_candidates = {
            resolved_path .. "/anim_map.lua",
            "assets/sprites/" .. key .. "/anim_map.lua",
            "client/assets/sprites/" .. key .. "/anim_map.lua"
        }
        for _, amp in ipairs(anim_map_candidates) do
            if file_exists(amp) then
                local custom_map = load_lua_table(amp)
                if custom_map then
                    -- Mesclar anim_map
                    if custom_map.states then
                        for k, v in pairs(custom_map.states) do
                            sprite_set.anim_map.states[k] = v
                        end
                    end
                    if custom_map.skills then
                        for k, v in pairs(custom_map.skills) do
                            sprite_set.anim_map.skills[k] = v
                        end
                    end
                    if custom_map.preferred_anims then
                        for k, v in pairs(custom_map.preferred_anims) do
                            sprite_set.anim_map.preferred_anims[k] = v
                        end
                    end
                    if custom_map.fps then
                        sprite_set.anim_map.fps = custom_map.fps
                    end
                    break
                end
            end
        end

        -- 2. Tentar metadata.json
        local meta_path = resolved_path .. "/metadata.json"
        local parsed_states = nil
        if file_exists(meta_path) then
            local meta_text = read_text_file(meta_path)
            if meta_text then
                parsed_states = parse_metadata_json(resolved_path, meta_text)
            end
        end

        -- 3. Fallback: descoberta por convenção de diretórios
        if not parsed_states or next(parsed_states) == nil then
            parsed_states = scan_directory_convention(resolved_path)
        end

        if parsed_states and next(parsed_states) ~= nil then
            sprite_set.states = parsed_states
            sprite_set.has_animations = true
            sprite_set.has_rotations = true
            print(string.format("[Client] Loaded animated 8-direction sprite set for '%s' from %s/", char_name, resolved_path))
        end
    elseif path_type == "single" then
        sprite_set.single_image_path = resolved_path
        sprite_set.has_rotations = false
        sprite_set.has_animations = false
        print(string.format("[Client] Loaded single character sprite '%s' for '%s'", resolved_path, char_name))
    end

    -- Se não encontrou estados animados nem single_image_path, tentar single fallback <key>.png
    if not sprite_set.has_animations and not sprite_set.single_image_path then
        local fallback_singles = {
            "assets/sprites/" .. key .. ".png",
            "client/assets/sprites/" .. key .. ".png",
            "assets/sprites/" .. char_name .. ".png"
        }
        for _, p in ipairs(fallback_singles) do
            if file_exists(p) then
                sprite_set.single_image_path = p
                break
            end
        end
    end

    local valid = sprite_set.has_animations or (sprite_set.single_image_path ~= nil)
    loaded_characters[key] = valid and sprite_set or false
    return valid and sprite_set or nil
end

-- Resolução de imagem de frame com cadeia estrita de fallbacks:
-- 1. Frame exato (state, anim, dir, frame_idx)
-- 2. Direção mais próxima no mesmo state/anim
-- 3. Primeiro frame disponível da direção
-- 4. Rotação estática do mesmo estado (state.rotations[dir])
-- 5. Rotação estática de "idle" / "Rotacao"
-- 6. Sprite padrão / imagem única do personagem
-- 7. nil (cairá para placeholder em main.lua)
local function resolve_frame_image(sprite_set, state_name, direction, frame_idx)
    if not sprite_set then return nil, 0, 0, false end

    -- Fallback se for personagem de imagem única
    if not sprite_set.has_animations then
        if sprite_set.single_image_path then
            local img, w, h = load_image(sprite_set.single_image_path)
            if img then
                return img, w, h, false
            end
        end
        return nil, 0, 0, false
    end

    local dir = direction or "south"
    local f_idx = frame_idx or 1

    -- Tentar encontrar o estado solicitado
    local state = sprite_set.states[state_name]
    if not state then
        -- Mapear estado genérico via anim_map
        local mapped = sprite_set.anim_map.states[state_name] or sprite_set.anim_map.skills[state_name]
        if mapped then
            state = sprite_set.states[mapped]
        end
    end

    -- Se estado não existe, tentar fallback de estado
    if not state then
        if state_name == "run" or state_name == "correndo" then
            state = sprite_set.states["andando"] or sprite_set.states[sprite_set.anim_map.states.walk]
        elseif state_name == "walk" or state_name == "andando" then
            state = sprite_set.states["correndo"] or sprite_set.states[sprite_set.anim_map.states.run]
        end
    end
    if not state then
        state = sprite_set.states["Rotacao"] or sprite_set.states[sprite_set.anim_map.states.idle] or next(sprite_set.states)
    end

    if state then
        -- Obter animação preferida ou padrão do estado
        local anim_name = sprite_set.anim_map.preferred_anims[state.name] or state.default_anim
        local anim = anim_name and state.animations[anim_name]
        if not anim and state.animations then
            _, anim = next(state.animations)
        end

        -- 1. Frame exato na direção solicitada
        if anim and anim[dir] and #anim[dir] > 0 then
            local frames = anim[dir]
            local clamped_idx = math.min(math.max(1, f_idx), #frames)
            local path = frames[clamped_idx]
            local img, w, h = load_image(path)
            if img then
                return img, w, h, true
            end
        end

        -- 2. Direção mais próxima
        if anim then
            local fallbacks = DIRECTION_FALLBACKS[dir] or {}
            for _, alt_dir in ipairs(fallbacks) do
                if anim[alt_dir] and #anim[alt_dir] > 0 then
                    local frames = anim[alt_dir]
                    local clamped_idx = math.min(math.max(1, f_idx), #frames)
                    local img, w, h = load_image(frames[clamped_idx])
                    if img then
                        return img, w, h, true
                    end
                end
            end
        end

        -- 3. Primeiro frame disponível em qualquer direção da animação
        if anim then
            for _, d_frames in pairs(anim) do
                if #d_frames > 0 then
                    local img, w, h = load_image(d_frames[1])
                    if img then
                        return img, w, h, true
                    end
                end
            end
        end

        -- 4. Rotação estática do estado atual
        if state.rotations and state.rotations[dir] then
            local img, w, h = load_image(state.rotations[dir])
            if img then
                return img, w, h, true
            end
        end
        if state.rotations then
            local fallbacks = DIRECTION_FALLBACKS[dir] or {}
            for _, alt_dir in ipairs(fallbacks) do
                if state.rotations[alt_dir] then
                    local img, w, h = load_image(state.rotations[alt_dir])
                    if img then
                        return img, w, h, true
                    end
                end
            end
        end
    end

    -- 5. Rotação estática de "Rotacao" / idle
    local idle_state = sprite_set.states["Rotacao"] or sprite_set.states[sprite_set.anim_map.states.idle]
    if idle_state and idle_state.rotations then
        if idle_state.rotations[dir] then
            local img, w, h = load_image(idle_state.rotations[dir])
            if img then
                return img, w, h, true
            end
        end
        local fallbacks = DIRECTION_FALLBACKS[dir] or {}
        for _, alt_dir in ipairs(fallbacks) do
            if idle_state.rotations[alt_dir] then
                local img, w, h = load_image(idle_state.rotations[alt_dir])
                if img then
                    return img, w, h, true
                end
            end
        end
    end

    -- 6. Imagem única de fallback
    if sprite_set.single_image_path then
        local img, w, h = load_image(sprite_set.single_image_path)
        if img then
            return img, w, h, false
        end
    end

    -- 7. Placeholder final
    return nil, 0, 0, false
end

-- Obter ou criar estado de animação de uma entidade
function SpriteAnim.get_entity_state(entity_id, char_name)
    if not entity_id then return nil end

    local state = entity_states[entity_id]
    local char_lower = string.lower(char_name or "")

    if not state or (char_lower ~= "" and state.character_name ~= char_lower) then
        state = {
            entity_id = entity_id,
            character_name = char_lower,
            current_state = "idle",
            current_action = nil,
            direction = "south",
            facing = 1,
            frame_index = 1,
            timer = 0,
            fps = DEFAULT_FPS,
            is_locked = false,
            is_dead = false,
            is_moving = false,
            speed = 0,
            death_finished = false
        }
        entity_states[entity_id] = state
    end

    return state
end

-- Limpar estado de animação de uma entidade
function SpriteAnim.clear_entity_state(entity_id)
    if entity_id then
        entity_states[entity_id] = nil
    end
end

-- Reset de personagem em runtime
function SpriteAnim.on_character_changed(entity_id, new_char)
    if entity_id then
        SpriteAnim.clear_entity_state(entity_id)
        SpriteAnim.load_character(new_char)
    end
end

-- Disparo de habilidade/ataque
function SpriteAnim.trigger_action(entity_id, skill_name, ability_id, dir_x, dir_y)
    local state = entity_states[entity_id]
    if not state or state.is_dead then return end

    local sprite_set = SpriteAnim.load_character(state.character_name)
    if not sprite_set or not sprite_set.has_animations then return end

    local anim_map = sprite_set.anim_map
    local mapped_state = nil

    if skill_name and skill_name ~= "" then
        local sn = string.lower(skill_name)
        mapped_state = anim_map.skills[sn] or anim_map.skills[skill_name]
    end

    if not mapped_state and ability_id then
        mapped_state = anim_map.skills[ability_id]
    end

    if mapped_state and sprite_set.states[mapped_state] then
        state.current_state = "attack"
        state.current_action = mapped_state
        state.frame_index = 1
        state.timer = 0
        state.is_locked = true

        if dir_x and dir_y and (dir_x ~= 0 or dir_y ~= 0) then
            state.direction = calc_direction_8way(dir_x, dir_y, state.direction)
            if dir_x > 0.05 then
                state.facing = 1
            elseif dir_x < -0.05 then
                state.facing = -1
            end
        end
    end
end

-- Reação quando um aliado morre (passiva da Arya: "aliado_morre")
function SpriteAnim.trigger_ally_death(entity_id)
    local state = entity_states[entity_id]
    if not state or state.is_dead then return end

    local sprite_set = SpriteAnim.load_character(state.character_name)
    if not sprite_set or not sprite_set.has_animations then return end

    local mapped_state = sprite_set.anim_map.states.ally_death or "aliado_morre"
    if sprite_set.states[mapped_state] then
        state.current_state = "ally_death"
        state.current_action = mapped_state
        state.frame_index = 1
        state.timer = 0
        state.is_locked = true
    end
end

-- Notificar estado de morte/reviver
function SpriteAnim.set_dead(entity_id, is_dead)
    local state = entity_states[entity_id]
    if not state then return end

    if is_dead then
        if not state.is_dead then
            state.is_dead = true
            state.current_state = "death"
            state.current_action = nil
            state.frame_index = 1
            state.timer = 0
            state.is_locked = false
            state.death_finished = false
        end
    else
        if state.is_dead then
            state.is_dead = false
            state.death_finished = false
            state.current_state = "idle"
            state.current_action = nil
            state.frame_index = 1
            state.timer = 0
            state.is_locked = false
        end
    end
end

-- Retorna a quantidade total de frames para um determinado estado e direção
local function get_state_frame_count(sprite_set, state_name, direction)
    if not sprite_set or not sprite_set.has_animations then return 1 end

    local state = sprite_set.states[state_name]
    if not state then
        local mapped = sprite_set.anim_map.states[state_name] or sprite_set.anim_map.skills[state_name]
        if mapped then
            state = sprite_set.states[mapped]
        end
    end

    if not state or not state.animations then return 9 end

    local anim_name = sprite_set.anim_map.preferred_anims[state.name] or state.default_anim
    local anim = anim_name and state.animations[anim_name]
    if not anim and state.animations then
        _, anim = next(state.animations)
    end

    if anim and anim[direction] and #anim[direction] > 0 then
        return #anim[direction]
    end

    return 9 -- Padrão Pixelab
end

-- Atualização da máquina de estados (chamada em love.update para cada entidade)
function SpriteAnim.update(dt, entity_id, data)
    if not entity_id or not data then return end

    local char_name = data.character_name or ""
    local state = SpriteAnim.get_entity_state(entity_id, char_name)
    local sprite_set = SpriteAnim.load_character(char_name)

    state.direction = data.direction or state.direction or "south"
    state.is_moving = data.is_moving or false
    state.speed = data.speed or 0
    if data.facing then
        state.facing = data.facing
    end

    local is_dead = data.is_dead or false
    if is_dead ~= state.is_dead then
        SpriteAnim.set_dead(entity_id, is_dead)
    end

    local fps = (sprite_set and sprite_set.anim_map and sprite_set.anim_map.fps) or DEFAULT_FPS
    state.fps = fps
    local frame_duration = 1 / fps

    if state.is_dead then
        local death_state_name = (sprite_set and sprite_set.anim_map.states.death) or "morte"
        local total_frames = get_state_frame_count(sprite_set, death_state_name, state.direction)

        if not state.death_finished then
            state.timer = state.timer + dt
            if state.timer >= frame_duration then
                state.timer = state.timer - frame_duration
                state.frame_index = state.frame_index + 1
                if state.frame_index >= total_frames then
                    state.frame_index = total_frames
                    state.death_finished = true
                end
            end
        else
            state.frame_index = total_frames
        end
        return
    end

    -- Se estiver executando uma ação bloqueante (ataque ou aliado_morre)
    if state.is_locked and state.current_action then
        local total_frames = get_state_frame_count(sprite_set, state.current_action, state.direction)
        state.timer = state.timer + dt
        if state.timer >= frame_duration then
            state.timer = state.timer - frame_duration
            state.frame_index = state.frame_index + 1
            if state.frame_index > total_frames then
                -- Fim da animação one-shot: desbloquear e retornar ao estado de locomoção/idle
                state.is_locked = false
                state.current_action = nil
                state.frame_index = 1
                state.timer = 0
            end
        end
        return
    end

    -- Locomoção ou Idle
    if state.is_moving then
        local is_running = (state.speed >= 2.5)
        local target_state = is_running and "run" or "walk"
        local mapped_target = sprite_set and sprite_set.anim_map.states[target_state] or (is_running and "correndo" or "andando")

        if state.current_state ~= target_state then
            state.current_state = target_state
            state.frame_index = 1
            state.timer = 0
        end

        local total_frames = get_state_frame_count(sprite_set, mapped_target, state.direction)
        state.timer = state.timer + dt
        if state.timer >= frame_duration then
            state.timer = state.timer - frame_duration
            state.frame_index = (state.frame_index % total_frames) + 1
        end
    else
        state.current_state = "idle"
        state.frame_index = 1
        state.timer = 0
    end
end

-- API principal de consulta de frame para renderização
-- get_frame(params) -> image, ox, oy, has_8way
-- Aceita tabela com campos ou parâmetros individuais
function SpriteAnim.get_frame(arg1, arg2, arg3, arg4)
    local char_name, state_name, direction, frame_idx
    local is_dead = false
    local is_moving = false
    local entity_id = nil

    if type(arg1) == "table" then
        entity_id = arg1.entity_id or arg1.id
        char_name = arg1.character_name or arg1.char_name
        direction = arg1.direction
        is_dead = arg1.is_dead or false
        is_moving = arg1.is_moving or false
        state_name = arg1.state or arg1.anim_state
        frame_idx = arg1.frame_index or arg1.frame
    else
        char_name = arg1
        state_name = arg2
        direction = arg3
        frame_idx = arg4
    end

    local sprite_set = SpriteAnim.load_character(char_name)
    if not sprite_set then
        return nil, SPRITE_BASE_SIZE / 2, SPRITE_BASE_SIZE, false
    end

    local ent_state = nil
    if entity_id then
        ent_state = SpriteAnim.get_entity_state(entity_id, char_name)
    end

    -- Determinar estado e frame ativo
    local active_state = state_name
    local active_frame = frame_idx
    local active_dir = direction or (ent_state and ent_state.direction) or "south"

    if ent_state then
        active_dir = direction or ent_state.direction or "south"
        active_frame = frame_idx or ent_state.frame_index or 1

        if is_dead or ent_state.is_dead then
            active_state = sprite_set.anim_map.states.death or "morte"
        elseif ent_state.is_locked and ent_state.current_action then
            active_state = ent_state.current_action
        elseif ent_state.current_state == "attack" and ent_state.current_action then
            active_state = ent_state.current_action
        elseif ent_state.current_state == "ally_death" and ent_state.current_action then
            active_state = ent_state.current_action
        elseif is_moving or ent_state.is_moving then
            local is_running = (ent_state.speed >= 2.5)
            active_state = is_running and (sprite_set.anim_map.states.run or "correndo")
                                      or (sprite_set.anim_map.states.walk or "andando")
        else
            active_state = sprite_set.anim_map.states.idle or "Rotacao"
        end
    else
        if not active_state or active_state == "" then
            active_state = is_dead and (sprite_set.anim_map.states.death or "morte")
                        or (is_moving and (sprite_set.anim_map.states.walk or "andando")
                        or (sprite_set.anim_map.states.idle or "Rotacao"))
        end
        active_frame = active_frame or 1
    end

    local img, w, h, has_8way = resolve_frame_image(sprite_set, active_state, active_dir, active_frame)
    if not img then
        return nil, SPRITE_BASE_SIZE / 2, SPRITE_BASE_SIZE, false
    end

    local ox = w / 2
    local oy = h

    return img, ox, oy, has_8way
end

return SpriteAnim
