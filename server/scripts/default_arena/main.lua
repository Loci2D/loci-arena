-- Loci Arena - Authoritative Game Logic (Lua Server Script)
-- This script runs inside the loci2d server environment.
-- Rules, physics modifications, damage and game mechanics must be handled here.

-- Movement speed in units per tick.
-- At 30 Hz server tick rate: 2.0 units/tick = 60 units/s (480 px/s with VISUAL_SCALE = 8).
local SPEED = 2.0

-- Limites seguros da arena e projeção de velocidade nas bordas (via VFS nativo do Loci2D)
local ArenaBounds = require("core.arena_bounds")
-- Bodyblock entre jogadores calibrado ao tamanho visual da base/sombra:
-- Sprite 32x32 @ SPRITE_SCALE=2 -> 64x64px; sombra nos pés: 52px de largura (shadow_radius_x = 26px).
-- A VISUAL_SCALE = 8: 6.5 unidades de mundo = 52px centro-a-centro (contato externo das sombras/silhuetas).
-- Mantém ArenaBounds.PLAYER_COLLIDER_RADIUS = 2.0 intacto para paridade com as paredes [-498, +498] da engine Rust.
local BODYBLOCK_DIST = 6.5
local MIN_COLLISION_DIST = BODYBLOCK_DIST
local FRONTAL_LOCK_DOT = 0.98 -- ~11.5° de tolerância frontal pura para evitar oscilação esquerda/direita

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

local function get_current_xy(entity_id)
    local pos = Loci.get_entity_position(entity_id)
    if not pos then return nil, nil end
    return get_coords(pos)
end

local function set_position_clamped(entity_id, x, y)
    local cx, cy = ArenaBounds.clamp_xy(x, y)
    Loci.Commands.set_position(entity_id, { x = cx, y = cy })
end

-- Importa os sistemas modulares da arena (via VFS nativo do Loci2D)
local CombatSystem = require("core.combat_system")
local CharacterFactory = require("systems.character_factory")
local ProjectileSystem = require("systems.projectile_system")
local SlowZone = require("systems.slow_zone")
local RespawnSystem = require("respawn_system")
local ArenaObstacles = require("data.arena_obstacles")

local function get_effective_walk_speed(entity_id, base_speed, current_tick)
    local spd = base_speed or SPEED
    local cur_tick = current_tick or ((CharacterFactory and CharacterFactory.get_current_tick) and CharacterFactory.get_current_tick() or 0)
    local slow_mult = CombatSystem.get_slow_multiplier(entity_id, cur_tick)
    return spd * slow_mult
end

local function is_player_alive(entity_id)
    if not connected_players[entity_id] then return false end
    if RespawnSystem and RespawnSystem.is_dead(entity_id) then return false end
    if Loci and Loci.get_entity_property then
        local dead_prop = Loci.get_entity_property(entity_id, "is_dead")
        if dead_prop == "true" or dead_prop == true or dead_prop == "1" or dead_prop == 1 then
            return false
        end
    end
    return true
end

local function is_entity_dashing(entity_id)
    if not (Loci and Loci.get_entity_property) then return false end
    local dashing_until = tonumber(Loci.get_entity_property(entity_id, "dashing_until")) or 0
    local current_tick = (CharacterFactory and CharacterFactory.get_current_tick) and CharacterFactory.get_current_tick() or 0
    return current_tick < dashing_until
end

local function is_entity_casting(entity_id, current_tick)
    if not (Loci and Loci.get_entity_property) then return false end
    local casting_until = tonumber(Loci.get_entity_property(entity_id, "casting_until")) or 0
    local tick = current_tick or ((CharacterFactory and CharacterFactory.get_current_tick) and CharacterFactory.get_current_tick() or 0)
    return tick < casting_until
end

local function is_entity_incapacitated(entity_id, current_tick)
    if not (Loci and Loci.get_entity_property) then return false end
    local tick = current_tick or ((CharacterFactory and CharacterFactory.get_current_tick) and CharacterFactory.get_current_tick() or 0)
    local paralyzed_until = tonumber(Loci.get_entity_property(entity_id, "paralyzed_until")) or 0
    local stunned_until = tonumber(Loci.get_entity_property(entity_id, "stunned_until")) or 0
    return tick < paralyzed_until or tick < stunned_until or is_entity_casting(entity_id, tick)
end

local function get_expected_intent_velocity(entity_id)
    local intent = player_intents[entity_id]
    if not intent or (intent.dir_x == 0 and intent.dir_y == 0) then
        return 0, 0
    end
    if not is_player_alive(entity_id) or is_entity_dashing(entity_id) or is_entity_incapacitated(entity_id) then
        return 0, 0
    end
    local spd = get_effective_walk_speed(entity_id, intent.speed)
    return intent.dir_x * spd, intent.dir_y * spd
end

local function get_bodyblock_xy(entity_id, use_post_step, override_positions)
    if override_positions and override_positions[entity_id] then
        local p = override_positions[entity_id]
        return p.x, p.y
    end
    local x, y = get_current_xy(entity_id)
    if not x then
        local lp = last_tick_positions[entity_id]
        if lp then return lp.x, lp.y end
        return nil, nil
    end
    if use_post_step then
        x, y = ArenaBounds.predict_post_step_xy(entity_id, x, y)
    end
    return x, y
end

-- Projeta o vetor de velocidade (vx, vy) contra o círculo de bodyblock de outro jogador em (ox, oy),
-- preservando o deslizamento tangencial suave (slide normal vector) em colisões anguladas
-- e aplicando trava limpa em colisões estritamente frontais (dot >= FRONTAL_LOCK_DOT).
local function project_velocity_against_player(my_x, my_y, ox, oy, vx, vy, other_vx, other_vy, orig_vx, orig_vy)
    local v_len_sq = vx * vx + vy * vy
    if v_len_sq <= 1e-10 then
        return 0, 0, false
    end

    local dx = ox - my_x
    local dy = oy - my_y
    local cur_dist_sq = dx * dx + dy * dy

    local v_len = math.sqrt(v_len_sq)
    local other_spd = math.sqrt((other_vx or 0) * (other_vx or 0) + (other_vy or 0) * (other_vy or 0))
    local max_reach = MIN_COLLISION_DIST + v_len + other_spd + 0.25
    if cur_dist_sq > max_reach * max_reach then
        return vx, vy, false
    end

    local cur_dist = math.sqrt(cur_dist_sq)
    if cur_dist <= 1e-6 then
        return 0, 0, true
    end

    local nx = dx / cur_dist
    local ny = dy / cur_dist

    -- Componente de velocidade avançando na direção do outro jogador
    local v_into = vx * nx + vy * ny
    if v_into <= 0 then
        return vx, vy, false
    end

    local dir_dot = v_into / v_len
    local other_into = math.max(0.0, -((other_vx or 0) * nx + (other_vy or 0) * ny))
    -- Usa a intenção original para calcular a divisão de folga em colisões mútuas,
    -- tornando a projeção idempotente em múltiplas passagens (evita sub-encolhimento no passo 2).
    local share_into = math.max(v_into, ((orig_vx or vx) * nx + (orig_vy or vy) * ny))

    -- Colisão estritamente frontal: para suavemente no contato exato sem oscilação lateral
    if dir_dot >= FRONTAL_LOCK_DOT then
        local gap = math.max(0.0, cur_dist - MIN_COLLISION_DIST)
        local max_forward = gap
        if other_into > 1e-6 and share_into > 1e-6 then
            max_forward = gap * (share_into / (share_into + other_into))
        end
        if v_into > max_forward + 1e-6 then
            if max_forward <= 1e-5 then
                return 0, 0, true
            end
            return nx * max_forward, ny * max_forward, true
        end
        return vx, vy, false
    end

    -- Colisão em ângulo: decompõe em componente normal e tangencial para deslizar pelo perímetro
    local tx = vx - v_into * nx
    local ty = vy - v_into * ny
    local t_sq = tx * tx + ty * ty
    local min_sq = MIN_COLLISION_DIST * MIN_COLLISION_DIST

    local needed_normal_dist = (t_sq >= min_sq) and 0.0 or math.sqrt(min_sq - t_sq)
    local max_normal = math.max(0.0, cur_dist - needed_normal_dist)
    if other_into > 1e-6 and share_into > 1e-6 then
        max_normal = max_normal * (share_into / (share_into + other_into))
    end

    if v_into > max_normal + 1e-6 then
        return tx + nx * max_normal, ty + ny * max_normal, true
    end

    return vx, vy, false
end

-- Projeta velocidade considerando paredes da arena e todos os outros jogadores vivos (não em dash),
-- permitindo contornar suavemente o perímetro sem penetração, travamento ou fuga das bordas.
local function project_bodyblock_velocity(entity_id, my_x, my_y, vx, vy, use_post_step, override_positions)
    local orig_vx, orig_vy = vx, vy
    vx, vy = ArenaBounds.project_velocity(my_x, my_y, vx, vy)

    if not is_player_alive(entity_id) or is_entity_dashing(entity_id) then
        return vx, vy
    end
    if vx * vx + vy * vy <= 1e-10 then
        return 0, 0
    end

    for _ = 1, 2 do
        local changed = false
        for other_id, _ in safe_pairs(connected_players) do
            if other_id ~= entity_id and is_player_alive(other_id) and not is_entity_dashing(other_id) then
                local ox, oy = get_bodyblock_xy(other_id, use_post_step, override_positions)
                if ox and oy then
                    local other_vx, other_vy = get_expected_intent_velocity(other_id)
                    local new_vx, new_vy, did_project = project_velocity_against_player(
                        my_x, my_y, ox, oy, vx, vy, other_vx, other_vy, orig_vx, orig_vy
                    )
                    if did_project then
                        vx, vy = new_vx, new_vy
                        changed = true
                    end
                end
            end
        end

        local wvx, wvy = ArenaBounds.project_velocity(my_x, my_y, vx, vy)
        if math.abs(wvx - vx) > 1e-6 or math.abs(wvy - vy) > 1e-6 then
            vx, vy = wvx, wvy
            changed = true
        end

        if not changed then
            break
        end
    end

    -- Evita inversão/oscilação quando espremido em cunha entre dois corpos ou corpo + parede
    if (orig_vx * vx + orig_vy * vy) <= 1e-6 or (vx * vx + vy * vy) <= 1e-8 then
        return 0, 0
    end

    return vx, vy
end

local function compute_walk_velocity(entity_id, dir_x, dir_y, speed, use_post_step, override_positions)
    local x, y = get_bodyblock_xy(entity_id, use_post_step, override_positions)
    if not x then return 0, 0 end

    local effective_speed = speed or SPEED
    local vx = (dir_x or 0) * effective_speed
    local vy = (dir_y or 0) * effective_speed

    return project_bodyblock_velocity(entity_id, x, y, vx, vy, use_post_step, override_positions)
end

-- Resolve eventuais sobreposições residuais de bodyblock (ex.: término de dash sobre outro jogador,
-- spawn sobreposto ou intenções simultâneas no mesmo tick) mantendo limites seguros da arena.
local function resolve_bodyblock_overlaps(post_positions)
    local ids = {}
    for entity_id, _ in safe_pairs(connected_players) do
        if post_positions[entity_id] and is_player_alive(entity_id) and not is_entity_dashing(entity_id) then
            table.insert(ids, entity_id)
        end
    end
    if #ids < 2 then return end
    table.sort(ids)

    local modified = {}
    local min_sep_sq = (MIN_COLLISION_DIST - 1e-3) * (MIN_COLLISION_DIST - 1e-3)

    for _ = 1, 2 do
        local any_overlap = false
        for i = 1, #ids do
            for j = i + 1, #ids do
                local id_a = ids[i]
                local id_b = ids[j]
                local pa = post_positions[id_a]
                local pb = post_positions[id_b]

                local dx = pb.x - pa.x
                local dy = pb.y - pa.y
                local dist_sq = dx * dx + dy * dy

                if dist_sq < min_sep_sq then
                    any_overlap = true
                    local dist = math.sqrt(dist_sq)
                    local nx, ny = 1.0, 0.0
                    if dist > 1e-4 then
                        nx = dx / dist
                        ny = dy / dist
                    end

                    local overlap = MIN_COLLISION_DIST - dist
                    local intent_a = player_intents[id_a]
                    local intent_b = player_intents[id_b]
                    local moving_a = intent_a and (intent_a.dir_x ~= 0 or intent_a.dir_y ~= 0) and not is_entity_casting(id_a)
                    local moving_b = intent_b and (intent_b.dir_x ~= 0 or intent_b.dir_y ~= 0) and not is_entity_casting(id_b)

                    local old_ax, old_ay = pa.x, pa.y
                    local old_bx, old_by = pb.x, pb.y

                    if moving_a and not moving_b then
                        local nax, nay = ArenaBounds.clamp_xy(pa.x - nx * overlap, pa.y - ny * overlap)
                        local moved_a = math.sqrt((nax - old_ax) ^ 2 + (nay - old_ay) ^ 2)
                        pa.x, pa.y = nax, nay
                        local rem = math.max(0.0, overlap - moved_a)
                        if rem > 1e-4 then
                            pb.x, pb.y = ArenaBounds.clamp_xy(pb.x + nx * rem, pb.y + ny * rem)
                            modified[id_b] = true
                        end
                        modified[id_a] = true
                    elseif moving_b and not moving_a then
                        local nbx, nby = ArenaBounds.clamp_xy(pb.x + nx * overlap, pb.y + ny * overlap)
                        local moved_b = math.sqrt((nbx - old_bx) ^ 2 + (nby - old_by) ^ 2)
                        pb.x, pb.y = nbx, nby
                        local rem = math.max(0.0, overlap - moved_b)
                        if rem > 1e-4 then
                            pa.x, pa.y = ArenaBounds.clamp_xy(pa.x - nx * rem, pa.y - ny * rem)
                            modified[id_a] = true
                        end
                        modified[id_b] = true
                    else
                        local half = overlap * 0.5
                        local nax, nay = ArenaBounds.clamp_xy(pa.x - nx * half, pa.y - ny * half)
                        local nbx, nby = ArenaBounds.clamp_xy(pb.x + nx * half, pb.y + ny * half)
                        local sep_dx = nbx - nax
                        local sep_dy = nby - nay
                        local sep_dist = math.sqrt(sep_dx * sep_dx + sep_dy * sep_dy)
                        if sep_dist < MIN_COLLISION_DIST - 1e-4 then
                            local rem = MIN_COLLISION_DIST - sep_dist
                            -- Compensa o lado bloqueado pela parede empurrando o lado livre
                            local ax_clamped = (math.abs(nax - (pa.x - nx * half)) > 1e-4) or (math.abs(nay - (pa.y - ny * half)) > 1e-4)
                            local bx_clamped = (math.abs(nbx - (pb.x + nx * half)) > 1e-4) or (math.abs(nby - (pb.y + ny * half)) > 1e-4)
                            if bx_clamped and not ax_clamped then
                                nax, nay = ArenaBounds.clamp_xy(nax - nx * rem, nay - ny * rem)
                            elseif ax_clamped and not bx_clamped then
                                nbx, nby = ArenaBounds.clamp_xy(nbx + nx * rem, nby + ny * rem)
                            end
                        end
                        pa.x, pa.y = nax, nay
                        pb.x, pb.y = nbx, nby
                        modified[id_a] = true
                        modified[id_b] = true
                    end
                end
            end
        end
        if not any_overlap then break end
    end

    for entity_id, _ in safe_pairs(modified) do
        local p = post_positions[entity_id]
        if p then
            set_position_clamped(entity_id, p.x, p.y)
        end
    end
end

function on_tick(current_tick)
    CharacterFactory.update_tick(current_tick)
    ProjectileSystem.update_tick(current_tick)
    RespawnSystem.process_tick(current_tick)

    -- 1. Salva posições antes da integração de física do tick (apenas para vivos),
    --    calcula posições pós-step previstas e projeta dash ativo contra as bordas.
    local post_positions = {}
    for entity_id, _ in safe_pairs(connected_players) do
        if is_player_alive(entity_id) then
            local pos = Loci.get_entity_position(entity_id)
            if pos then
                local px, py = get_coords(pos)
                last_tick_positions[entity_id] = { x = px, y = py }

                local cur_vx, cur_vy = ArenaBounds.get_current_velocity(entity_id)
                local post_x, post_y = ArenaBounds.predict_post_step_xy(entity_id, px, py, cur_vx, cur_vy)

                -- Área de teste de Slow CC: retângulo [20, 30] x [20, 30]
                SlowZone.process_entity(entity_id, px, py, post_x, post_y, current_tick)
                post_positions[entity_id] = { x = post_x, y = post_y }

                if is_entity_dashing(entity_id) then
                    if cur_vx ~= 0 or cur_vy ~= 0 then
                        local proj_vx, proj_vy = ArenaBounds.project_velocity(post_x, post_y, cur_vx, cur_vy)
                        if math.abs(proj_vx - cur_vx) > 1e-6 or math.abs(proj_vy - cur_vy) > 1e-6 then
                            Loci.Commands.set_velocity(entity_id, { x = proj_vx, y = proj_vy })
                        end
                    end
                end
            end
        else
            last_tick_positions[entity_id] = nil
        end
    end

    -- 1.5. Separa qualquer sobreposição residual de bodyblock (ex.: pós-dash ou spawn sobreposto)
    resolve_bodyblock_overlaps(post_positions)

    -- 2. Atualiza velocidade pretendida para jogadores vivos (com bodyblock + deslizamento tangencial + paredes)
    for entity_id, intent in safe_pairs(player_intents) do
        if not is_player_alive(entity_id) then
            player_intents[entity_id] = nil
        elseif intent and (intent.dir_x ~= 0 or intent.dir_y ~= 0) then
            -- Se estiver executando dash, a velocidade física da habilidade prevalece
            if not is_entity_dashing(entity_id) then
                if not is_entity_incapacitated(entity_id, current_tick) then
                    local effective_speed = get_effective_walk_speed(entity_id, intent.speed, current_tick)
                    local vx, vy = compute_walk_velocity(entity_id, intent.dir_x, intent.dir_y, effective_speed, true, post_positions)
                    Loci.Commands.set_velocity(entity_id, { x = vx, y = vy })
                end
            end
        end
    end
end

function on_init()
    -- Inicializa obstáculos da arena
    ArenaObstacles.initialize()
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

    local dashing_until = tonumber(Loci.get_entity_property(entity_id, "dashing_until")) or 0
    if CharacterFactory.get_current_tick() < dashing_until then
        -- Durante o dash ativo, mantém a velocidade física do impulso sem cancelá-la;
        -- player_intents já foi atualizado acima para refletir soltura/troca de tecla no fim do dash.
        return true
    end

    if is_entity_casting(entity_id) then
        -- Cast lock: a intenção fica registrada para retomar o movimento ao fim da
        -- conjuração, mas a velocidade é zerada enquanto casting_until estiver ativo.
        Loci.Commands.set_velocity(entity_id, { x = 0, y = 0 })
        return true
    end

    -- Velocidade autoritativa já projetada contra bodyblock (com deslizamento tangencial), slow e paredes da arena
    local current_tick = CharacterFactory.get_current_tick()
    local px, py = get_current_xy(entity_id)
    if px and py then
        SlowZone.process_entity(entity_id, px, py, px, py, current_tick)
    end

    local effective_speed = move_speed
    local is_slowed, slow_mult, slowed_until = CombatSystem.get_slow_state(entity_id, current_tick)
    if is_slowed and current_tick < slowed_until then
        effective_speed = move_speed * slow_mult
    end

    local vx, vy = compute_walk_velocity(entity_id, dir_x, dir_y, effective_speed, false)
    Loci.Commands.set_velocity(entity_id, { x = vx, y = vy })
    return true
end

function on_action(entity_id, ability_id, aim_x, aim_y)
    Loci.Log.info("[Arena] Action from entity " .. tostring(entity_id) .. " -> Ability: " .. tostring(ability_id))

    -- Ability ID 999: Troca de personagem provisória
    if ability_id == 999 then
        if RespawnSystem and RespawnSystem.is_dead and RespawnSystem.is_dead(entity_id) then
            return false, "Não é possível trocar de personagem enquanto estiver morto."
        end

        local char_cycle = { "arya", "warrior", "archer", "mage", "cleric", "enchanter" }
        local current_char = string.lower(Loci.get_entity_property(entity_id, "character_name") or "unknown")

        -- Encontra o índice atual e calcula o próximo
        local current_idx = 0
        for idx, name in ipairs(char_cycle) do
            if name == current_char then
                current_idx = idx - 1
                break
            end
        end
        local next_idx = (current_idx + 1) % #char_cycle
        local new_character_name = char_cycle[next_idx + 1]

        Loci.Log.info("[Arena] Trocando personagem de " .. current_char .. " para " .. new_character_name)

        -- Recria o personagem com os novos dados
        CharacterFactory.on_entity_remove(entity_id) -- Limpa estado antigo
        CharacterFactory.create_character(entity_id, new_character_name)

        -- Atualiza a velocidade da intenção de movimento ativa para o novo personagem
        if player_intents[entity_id] then
            local new_speed = tonumber(Loci.get_entity_property(entity_id, "move_speed") or SPEED) or SPEED
            player_intents[entity_id].speed = new_speed
        end

        Loci.Log.info("[Arena] Personagem trocado para " .. new_character_name)
        return true
    end

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
    -- Delega colisões envolvendo projéteis para o ProjectileSystem (comportamento de sensor sem empurrão físico)
    if ProjectileSystem.is_projectile(entity_a) or ProjectileSystem.is_projectile(entity_b) then
        ProjectileSystem.on_collision(entity_a, entity_b)
        return
    end

    -- Só processa colisão sólida e body-blocking se ambos forem jogadores conectados e vivos
    if not (connected_players[entity_a] and connected_players[entity_b]) then
        return
    end
    if not (is_player_alive(entity_a) and is_player_alive(entity_b)) then
        return
    end
    -- Dashing atravessa inimigos e aliados sem interromper o impulso
    if is_entity_dashing(entity_a) or is_entity_dashing(entity_b) then
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

    -- Jogador em cast lock tem intenção registrada mas está enraizado: trata como parado
    -- para não sofrer o split de posição do "ambos se movendo" durante a conjuração.
    local moving_a = intent_a and (intent_a.dir_x ~= 0 or intent_a.dir_y ~= 0) and not is_entity_casting(entity_a)
    local moving_b = intent_b and (intent_b.dir_x ~= 0 or intent_b.dir_y ~= 0) and not is_entity_casting(entity_b)

    -- Separação calibrada de bodyblock (6.5u = 52px centro-a-centro)
    local MIN_DIST = MIN_COLLISION_DIST

    -- Vetor relativo de B para A (onde A está em relação a B)
    local rel_x = cur_a_x - cur_b_x
    local rel_y = cur_a_y - cur_b_y
    local rel_dist = math.sqrt(rel_x * rel_x + rel_y * rel_y)
    local nx = (rel_dist > 1e-4) and (rel_x / rel_dist) or ((entity_a < entity_b) and -1.0 or 1.0)
    local ny = (rel_dist > 1e-4) and (rel_y / rel_dist) or 0.0

    local res_a_x, res_a_y = cur_a_x, cur_a_y
    local res_b_x, res_b_y = cur_b_x, cur_b_y

    -- Caso 1: Jogador A está se movendo e Jogador B está parado
    if moving_a and not moving_b then
        if rel_dist > 1e-4 then
            local dot_away = intent_a.dir_x * nx + intent_a.dir_y * ny
            if dot_away > 0.1 then
                return
            end
        end

        -- Mantém B estritamente parado na posição anterior
        res_b_x, res_b_y = ArenaBounds.clamp_xy(prev_b.x, prev_b.y)
        res_a_x, res_a_y = ArenaBounds.clamp_xy(res_b_x + nx * MIN_DIST, res_b_y + ny * MIN_DIST)
        set_position_clamped(entity_b, res_b_x, res_b_y)
        Loci.Commands.set_velocity(entity_b, { x = 0, y = 0 })
        set_position_clamped(entity_a, res_a_x, res_a_y)

        local overrides = { [entity_a] = { x = res_a_x, y = res_a_y }, [entity_b] = { x = res_b_x, y = res_b_y } }
        local vx, vy = compute_walk_velocity(entity_a, intent_a.dir_x, intent_a.dir_y, intent_a.speed, false, overrides)
        Loci.Commands.set_velocity(entity_a, { x = vx, y = vy })

    -- Caso 2: Jogador B está se movendo e Jogador A está parado
    elseif moving_b and not moving_a then
        local inv_nx, inv_ny = -nx, -ny
        if rel_dist > 1e-4 then
            local dot_away = intent_b.dir_x * inv_nx + intent_b.dir_y * inv_ny
            if dot_away > 0.1 then
                return
            end
        end

        res_a_x, res_a_y = ArenaBounds.clamp_xy(prev_a.x, prev_a.y)
        res_b_x, res_b_y = ArenaBounds.clamp_xy(res_a_x + inv_nx * MIN_DIST, res_a_y + inv_ny * MIN_DIST)
        set_position_clamped(entity_a, res_a_x, res_a_y)
        Loci.Commands.set_velocity(entity_a, { x = 0, y = 0 })
        set_position_clamped(entity_b, res_b_x, res_b_y)

        local overrides = { [entity_a] = { x = res_a_x, y = res_a_y }, [entity_b] = { x = res_b_x, y = res_b_y } }
        local vx, vy = compute_walk_velocity(entity_b, intent_b.dir_x, intent_b.dir_y, intent_b.speed, false, overrides)
        Loci.Commands.set_velocity(entity_b, { x = vx, y = vy })

    -- Caso 3: Ambos estão se movendo (colisão mútua)
    elseif moving_a and moving_b then
        local mid_x = (prev_a.x + prev_b.x) * 0.5
        local mid_y = (prev_a.y + prev_b.y) * 0.5
        res_a_x, res_a_y = ArenaBounds.clamp_xy(mid_x + nx * (MIN_DIST * 0.5), mid_y + ny * (MIN_DIST * 0.5))
        res_b_x, res_b_y = ArenaBounds.clamp_xy(mid_x - nx * (MIN_DIST * 0.5), mid_y - ny * (MIN_DIST * 0.5))

        set_position_clamped(entity_a, res_a_x, res_a_y)
        set_position_clamped(entity_b, res_b_x, res_b_y)

        local overrides = { [entity_a] = { x = res_a_x, y = res_a_y }, [entity_b] = { x = res_b_x, y = res_b_y } }
        local vax, vay = compute_walk_velocity(entity_a, intent_a.dir_x, intent_a.dir_y, intent_a.speed, false, overrides)
        local vbx, vby = compute_walk_velocity(entity_b, intent_b.dir_x, intent_b.dir_y, intent_b.speed, false, overrides)
        Loci.Commands.set_velocity(entity_a, { x = vax, y = vay })
        Loci.Commands.set_velocity(entity_b, { x = vbx, y = vby })

    -- Caso 4: Ambos parados
    else
        local mid_x = (prev_a.x + prev_b.x) * 0.5
        local mid_y = (prev_a.y + prev_b.y) * 0.5
        set_position_clamped(entity_a, mid_x + nx * (MIN_DIST * 0.5), mid_y + ny * (MIN_DIST * 0.5))
        set_position_clamped(entity_b, mid_x - nx * (MIN_DIST * 0.5), mid_y - ny * (MIN_DIST * 0.5))
        Loci.Commands.set_velocity(entity_a, { x = 0, y = 0 })
        Loci.Commands.set_velocity(entity_b, { x = 0, y = 0 })
    end
end

function on_static_collision(entity_id, obstacle_id, nx, ny)
    if ProjectileSystem.is_projectile(entity_id) then
        ProjectileSystem.on_static_collision(entity_id, obstacle_id, nx, ny)
    end
end

function on_boundary_collision(entity_id, nx, ny)
    if ProjectileSystem.is_projectile(entity_id) then
        ProjectileSystem.on_boundary_collision(entity_id, nx, ny)
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
