-- Loci Arena - Authoritative Game Logic (Lua Server Script)
-- This script runs inside the loci2d server environment.
-- Rules, physics modifications, damage and game mechanics must be handled here.

-- Movement speed in units per tick.
-- At 30 Hz server tick rate: 5.0 units/tick = 150 units (pixels) per second.
local SPEED = 3.0
-- Rastreamento de jogadores conectados e contagem de times ativos
local connected_players = {} -- [entity_id] = { team = "1" ou "2" }
local team_counts = { ["1"] = 0, ["2"] = 0 }

-- Rastreamento de posições anteriores e intenções de movimento para bloquear deslize/sabonete na colisão
local last_tick_positions = {} -- [entity_id] = { x = x, y = y }
local player_intents = {}      -- [entity_id] = { dir_x = dir_x, dir_y = dir_y, speed = speed }

local function safe_pairs(t)
    if type(dpairs) == "function" then
        return dpairs(t)
    elseif type(pairs) == "function" then
        return pairs(t)
    end
    return function() return nil end
end

local function get_coords(pos)
    if not pos then return 0, 0 end
    if type(pos.x_float) == "function" then
        return pos:x_float(), pos:y_float()
    elseif pos.x and pos.y then
        return pos.x, pos.y
    end
    return 0, 0
end

-- =============================================================================
-- Module Loader Polyfill (require)
-- Suporte a múltiplos arquivos e importações modulares no ambiente sandbox do Lua.
-- =============================================================================
local _LOADED = {}
local SEARCH_PATTERNS = {
    "server/scripts/%s.lua",
    "server/scripts/%s/init.lua",
    "server/scripts/default_arena/%s.lua",
    "scripts/%s.lua",
    "scripts/%s/init.lua",
    "scripts/default_arena/%s.lua",
    "%s.lua"
}

function require(modname)
    if _LOADED[modname] then
        return _LOADED[modname]
    end

    local clean_name = modname:gsub("%.", "/")
    local chunk, err = nil, nil
    local tried = {}

    for _, pattern in ipairs(SEARCH_PATTERNS) do
        local path = string.format(pattern, clean_name)
        chunk, err = loadfile(path)
        if chunk then
            break
        end
        table.insert(tried, path)
    end

    if not chunk then
        error(string.format("module '%s' not found:\n\tno file '%s'\n\tlast error: %s",
            modname, table.concat(tried, "'\n\tno file '"), tostring(err)))
    end

    local result = chunk()
    _LOADED[modname] = (result ~= nil) and result or true
    return _LOADED[modname]
end

-- Importa os sistemas modulares da arena
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("default_arena.systems.character_factory")
local RespawnSystem = require("default_arena.respawn_system")

local function is_blocked_by_player(entity_id, dir_x, dir_y)
    if not dir_x or not dir_y or (dir_x == 0 and dir_y == 0) then
        return false
    end

    local my_pos_ud = Loci.get_entity_position(entity_id)
    if not my_pos_ud then return false end
    local my_x, my_y = get_coords(my_pos_ud)

    -- Distância máxima de contato: 4.15 (raios 2.0 + 2.0 + margem)
    local MIN_BLOCK_DIST_SQ = 4.15 * 4.15

    for other_id, _ in safe_pairs(connected_players) do
        if other_id ~= entity_id then
            local other_pos_ud = Loci.get_entity_position(other_id)
            if other_pos_ud then
                local ox, oy = get_coords(other_pos_ud)
                local dx = ox - my_x
                local dy = oy - my_y
                local dist_sq = dx * dx + dy * dy

                if dist_sq <= MIN_BLOCK_DIST_SQ then
                    -- Produto escalar: verifica se o movimento aponta contra o corpo do outro jogador
                    local dot = dir_x * dx + dir_y * dy
                    if dot > 0.01 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function on_tick(current_tick)
    CharacterFactory.update_tick(current_tick)
    RespawnSystem.process_tick(current_tick)

    -- 1. Salva posições antes da integração de física do tick
    for entity_id, _ in safe_pairs(connected_players) do
        local pos = Loci.get_entity_position(entity_id)
        if pos then
            local px, py = get_coords(pos)
            last_tick_positions[entity_id] = { x = px, y = py }
        end
    end

    -- 2. Atualiza velocidade pretendida para jogadores
    for entity_id, intent in safe_pairs(player_intents) do
        if intent and (intent.dir_x ~= 0 or intent.dir_y ~= 0) then
            local paralyzed_until = tonumber(Loci.get_entity_property(entity_id, "paralyzed_until")) or 0
            local stunned_until = tonumber(Loci.get_entity_property(entity_id, "stunned_until")) or 0
            local dashing_until = tonumber(Loci.get_entity_property(entity_id, "dashing_until")) or 0
            
            if current_tick >= paralyzed_until and current_tick >= stunned_until and current_tick >= dashing_until then
                if is_blocked_by_player(entity_id, intent.dir_x, intent.dir_y) then
                    -- Se já está em contato bloqueado com outro jogador, mantém 100% estático (sem jitter/sem ir e voltar)
                    Loci.Commands.set_velocity(entity_id, { x = 0, y = 0 })
                else
                    Loci.Commands.set_velocity(entity_id, {
                        x = intent.dir_x * intent.speed,
                        y = intent.dir_y * intent.speed
                    })
                end
            end
        end
    end
end

function on_player_join(entity_id)
    -- Proteção contra chamadas duplicadas ([Join] inicial seguido por [Session] re-joined)
    local existing_record = connected_players[entity_id]
    local existing_prop_team = (Loci and Loci.get_entity_property) and Loci.get_entity_property(entity_id, "team") or nil

    if existing_record or (existing_prop_team and existing_prop_team ~= "") then
        local current_team = tostring((existing_record and existing_record.team) or existing_prop_team)
        if not existing_record then
            connected_players[entity_id] = { team = current_team }
            team_counts[current_team] = (team_counts[current_team] or 0) + 1
        end
        if Loci and Loci.Log then
            Loci.Log.info("[Arena] Player " .. tostring(entity_id) .. " session re-joined. Mantendo time " .. current_team)
        end
        Loci.Commands.set_property(entity_id, "team", current_team)
        return
    end

    if Loci and Loci.Log then
        Loci.Log.info("[Arena] Player joined with entity ID " .. tostring(entity_id))
    end
    
    -- Aloca jogadores no time com menor quantidade ativa para manter o equilíbrio
    local team_id = (team_counts["1"] <= team_counts["2"]) and "1" or "2"
    team_counts[team_id] = team_counts[team_id] + 1
    connected_players[entity_id] = { team = team_id }

    -- Inicializa propriedades básicas de match
    Loci.Commands.set_property(entity_id, "team", team_id)
    Loci.Commands.set_property(entity_id, "score", "0")
    Loci.Commands.set_property(entity_id, "kills", "0")
    Loci.Commands.set_property(entity_id, "deaths", "0")
    Loci.Commands.set_property(entity_id, "is_dead", "false")

    -- Instancia o personagem (agora definido como Arya para teste)
    CharacterFactory.create_character(entity_id, "arya")
    if Loci and Loci.Log then
        Loci.Log.info(string.format("[Arena] Entity ID %s alocado no Time %s (Time 1: %d, Time 2: %d)",
            tostring(entity_id), team_id, team_counts["1"], team_counts["2"]))
    end
end

function on_move_intent(entity_id, dir_x, dir_y)
    if RespawnSystem.is_dead(entity_id) then
        player_intents[entity_id] = nil
        return false, "Você está morto"
    end

    local paralyzed_until = tonumber(Loci.get_entity_property(entity_id, "paralyzed_until")) or 0
    if CharacterFactory.get_current_tick() < paralyzed_until then
        -- Cancel velocity during paralysis
        Loci.Commands.set_velocity(entity_id, {x = 0, y = 0})
        player_intents[entity_id] = nil
        return false, "Personagem paralisado por choque térmico/emocional."
    end

    local stunned_until = tonumber(Loci.get_entity_property(entity_id, "stunned_until")) or 0
    if CharacterFactory.get_current_tick() < stunned_until then
        Loci.Commands.set_velocity(entity_id, {x = 0, y = 0})
        player_intents[entity_id] = nil
        return false, "Personagem atordoado (Stun)."
    end

    local dashing_until = tonumber(Loci.get_entity_property(entity_id, "dashing_until")) or 0
    if CharacterFactory.get_current_tick() < dashing_until then
        -- Durante o dash ativo, mantém a velocidade do impulso sem ser cancelada pelos comandos de caminhada
        return true
    end

    -- Normalize movement vector so diagonal movement doesn't provide a speed boost
    local raw_dir_x, raw_dir_y = dir_x, dir_y
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if len > 0 then
        dir_x = dir_x / len
        dir_y = dir_y / len
    else
        dir_x = 0
        dir_y = 0
    end

    local move_speed = tonumber(Loci.get_entity_property(entity_id, "move_speed") or SPEED) or SPEED

    if dir_x == 0 and dir_y == 0 then
        player_intents[entity_id] = nil
    else
        player_intents[entity_id] = {
            dir_x = dir_x,
            dir_y = dir_y,
            raw_x = raw_dir_x,
            raw_y = raw_dir_y,
            speed = move_speed
        }
    end

    -- Se já estiver bloqueado por outro jogador nessa direção, trava estático imediatamente
    if is_blocked_by_player(entity_id, dir_x, dir_y) then
        Loci.Commands.set_velocity(entity_id, { x = 0, y = 0 })
        return true
    end

    -- Set server authoritative velocity (displacement per tick)
    Loci.Commands.set_velocity(entity_id, {
        x = dir_x * move_speed,
        y = dir_y * move_speed
    })
    return true
end

function on_action(entity_id, ability_id, aim_x, aim_y)
    Loci.Log.info("[Arena] Action from entity " .. tostring(entity_id) .. " -> Ability: " .. tostring(ability_id))
    
    if RespawnSystem.is_dead(entity_id) then
        return false, "Você está morto"
    end

    local paralyzed_until = tonumber(Loci.get_entity_property(entity_id, "paralyzed_until")) or 0
    if CharacterFactory.get_current_tick() < paralyzed_until then
        return false, "Personagem paralisado por choque térmico/emocional."
    end

    local stunned_until = tonumber(Loci.get_entity_property(entity_id, "stunned_until")) or 0
    if CharacterFactory.get_current_tick() < stunned_until then
        return false, "Personagem atordoado (Stun)."
    end

    local disarmed_until = tonumber(Loci.get_entity_property(entity_id, "disarmed_until")) or 0
    if CharacterFactory.get_current_tick() < disarmed_until then
        return false, "Personagem desarmado (sem espada)."
    end

    -- Busca a habilidade equipada no slot correspondente ao ability_id
    local skill_name = CharacterFactory.get_skill_by_slot(entity_id, ability_id)
    if not skill_name then
        return false, "Ability not equipped or invalid slot"
    end

    -- Executa a habilidade via CharacterFactory
    local success, err = CharacterFactory.execute_skill(entity_id, skill_name, aim_x, aim_y)
    if not success then
        return false, err or "Ability execution failed"
    end

    return true
end

function on_collision(entity_a, entity_b)
    -- Só processa colisão sólida e body-blocking se ambos forem jogadores conectados
    if not (connected_players[entity_a] and connected_players[entity_b]) then
        return
    end

    local pos_a_ud = Loci.get_entity_position(entity_a)
    local pos_b_ud = Loci.get_entity_position(entity_b)
    if not pos_a_ud or not pos_b_ud then return end

    local cur_a_x, cur_a_y = get_coords(pos_a_ud)
    local cur_b_x, cur_b_y = get_coords(pos_b_ud)

    local prev_a = last_tick_positions[entity_a] or { x = cur_a_x, y = cur_a_y }
    local prev_b = last_tick_positions[entity_b] or { x = cur_b_x, y = cur_b_y }

    local intent_a = player_intents[entity_a]
    local intent_b = player_intents[entity_b]

    local moving_a = intent_a and (intent_a.dir_x ~= 0 or intent_a.dir_y ~= 0)
    local moving_b = intent_b and (intent_b.dir_x ~= 0 or intent_b.dir_y ~= 0)

    -- Raio dos personagens da arena (2.0 cada) + folga de 0.05 para garantir separação estática
    local MIN_DIST = 4.05

    -- Caso 1: Jogador A está se movendo e Jogador B está parado
    if moving_a and not moving_b then
        -- Trava B estritamente na sua posição anterior sem sofrer empurrão espúrio
        Loci.Commands.set_position(entity_b, { x = prev_b.x, y = prev_b.y })
        Loci.Commands.set_velocity(entity_b, { x = 0, y = 0 })

        local target_x = prev_a.x
        local target_y = prev_a.y

        -- Se A andava puramente na horizontal
        if intent_a.dir_y == 0 and intent_a.dir_x ~= 0 then
            target_y = prev_a.y
            local dy = target_y - prev_b.y
            local dy2 = dy * dy
            if dy2 < MIN_DIST * MIN_DIST then
                local needed_dx = math.sqrt(MIN_DIST * MIN_DIST - dy2)
                target_x = (intent_a.dir_x > 0) and (prev_b.x - needed_dx) or (prev_b.x + needed_dx)
            else
                target_x = prev_a.x
            end

        -- Se A andava puramente na vertical
        elseif intent_a.dir_x == 0 and intent_a.dir_y ~= 0 then
            target_x = prev_a.x
            local dx = target_x - prev_b.x
            local dx2 = dx * dx
            if dx2 < MIN_DIST * MIN_DIST then
                local needed_dy = math.sqrt(MIN_DIST * MIN_DIST - dx2)
                target_y = (intent_a.dir_y > 0) and (prev_b.y - needed_dy) or (prev_b.y + needed_dy)
            else
                target_y = prev_a.y
            end

        -- Se A andava em diagonal: trava no ponto de contato sem deslize
        else
            local dx = prev_a.x - prev_b.x
            local dy = prev_a.y - prev_b.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0.001 then
                target_x = prev_b.x + (dx / dist) * MIN_DIST
                target_y = prev_b.y + (dy / dist) * MIN_DIST
            else
                target_x = prev_b.x - MIN_DIST
                target_y = prev_b.y
            end
        end

        -- Bate e para: trava posição no contato e zera totalmente a velocidade
        Loci.Commands.set_position(entity_a, { x = target_x, y = target_y })
        Loci.Commands.set_velocity(entity_a, { x = 0, y = 0 })

    -- Caso 2: Jogador B está se movendo e Jogador A está parado
    elseif moving_b and not moving_a then
        Loci.Commands.set_position(entity_a, { x = prev_a.x, y = prev_a.y })
        Loci.Commands.set_velocity(entity_a, { x = 0, y = 0 })

        local target_x = prev_b.x
        local target_y = prev_b.y

        if intent_b.dir_y == 0 and intent_b.dir_x ~= 0 then
            target_y = prev_b.y
            local dy = target_y - prev_a.y
            local dy2 = dy * dy
            if dy2 < MIN_DIST * MIN_DIST then
                local needed_dx = math.sqrt(MIN_DIST * MIN_DIST - dy2)
                target_x = (intent_b.dir_x > 0) and (prev_a.x - needed_dx) or (prev_a.x + needed_dx)
            else
                target_x = prev_b.x
            end

        elseif intent_b.dir_x == 0 and intent_b.dir_y ~= 0 then
            target_x = prev_b.x
            local dx = target_x - prev_a.x
            local dx2 = dx * dx
            if dx2 < MIN_DIST * MIN_DIST then
                local needed_dy = math.sqrt(MIN_DIST * MIN_DIST - dx2)
                target_y = (intent_b.dir_y > 0) and (prev_a.y - needed_dy) or (prev_a.y + needed_dy)
            else
                target_y = prev_b.y
            end

        else
            local dx = prev_b.x - prev_a.x
            local dy = prev_b.y - prev_a.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0.001 then
                target_x = prev_a.x + (dx / dist) * MIN_DIST
                target_y = prev_a.y + (dy / dist) * MIN_DIST
            else
                target_x = prev_a.x + MIN_DIST
                target_y = prev_a.y
            end
        end

        Loci.Commands.set_position(entity_b, { x = target_x, y = target_y })
        Loci.Commands.set_velocity(entity_b, { x = 0, y = 0 })

    -- Caso 3: Ambos estão se movendo (colisão mútua / de frente)
    elseif moving_a and moving_b then
        local dx = prev_a.x - prev_b.x
        local dy = prev_a.y - prev_b.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local nx = (dist > 0.001) and (dx / dist) or 1
        local ny = (dist > 0.001) and (dy / dist) or 0

        local mid_x = (prev_a.x + prev_b.x) * 0.5
        local mid_y = (prev_a.y + prev_b.y) * 0.5

        Loci.Commands.set_position(entity_a, { x = mid_x + nx * (MIN_DIST * 0.5), y = mid_y + ny * (MIN_DIST * 0.5) })
        Loci.Commands.set_position(entity_b, { x = mid_x - nx * (MIN_DIST * 0.5), y = mid_y - ny * (MIN_DIST * 0.5) })
        Loci.Commands.set_velocity(entity_a, { x = 0, y = 0 })
        Loci.Commands.set_velocity(entity_b, { x = 0, y = 0 })

    -- Caso 4: Ambos parados
    else
        Loci.Commands.set_position(entity_a, { x = prev_a.x, y = prev_a.y })
        Loci.Commands.set_position(entity_b, { x = prev_b.x, y = prev_b.y })
        Loci.Commands.set_velocity(entity_a, { x = 0, y = 0 })
        Loci.Commands.set_velocity(entity_b, { x = 0, y = 0 })
    end
end

function on_player_leave(entity_id)
    if Loci and Loci.Log then
        Loci.Log.info("[Arena] Player left: " .. tostring(entity_id))
    end

    -- Atualiza contagem do time ao desconectar
    local player_data = connected_players[entity_id]
    if player_data then
        local team_id = player_data.team
        if team_counts[team_id] and team_counts[team_id] > 0 then
            team_counts[team_id] = team_counts[team_id] - 1
        end
        connected_players[entity_id] = nil
    end

    player_intents[entity_id] = nil
    last_tick_positions[entity_id] = nil

    CharacterFactory.on_entity_remove(entity_id)
    RespawnSystem.cleanup(entity_id)
    Loci.Commands.destroy_entity(entity_id)
end
