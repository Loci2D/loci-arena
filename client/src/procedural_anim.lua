-- Character Direction and Visual State System
-- Gerencia orientação e seleção de direção (8-way) para sprites do Pixelab sem deformações procedurais

local DIRECTIONS_8 = {
    "east",
    "south-east",
    "south",
    "south-west",
    "west",
    "north-west",
    "north",
    "north-east",
}

local INV_SQRT2 = math.sqrt(0.5)
local DIRECTION_VECTORS = {
    ["east"]       = {  1.0,        0.0 },
    ["south-east"] = {  INV_SQRT2,  INV_SQRT2 },
    ["south"]      = {  0.0,        1.0 },
    ["south-west"] = { -INV_SQRT2,  INV_SQRT2 },
    ["west"]       = { -1.0,        0.0 },
    ["north-west"] = { -INV_SQRT2, -INV_SQRT2 },
    ["north"]      = {  0.0,       -1.0 },
    ["north-east"] = {  INV_SQRT2, -INV_SQRT2 },
}

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

local ProceduralAnim = {}

-- Estado visual por entidade
local anim_states = {}

-- Obter ou criar estado para uma entidade
function ProceduralAnim.get_state(entity_id)
    if not anim_states[entity_id] then
        anim_states[entity_id] = {
            direction = "south",
            facing = 1,
            is_moving = false,
            last_dx = nil,
            last_dy = nil,
            -- Campos mantidos neutros para total compatibilidade retroativa
            tilt_angle = 0,
            bob_offset = 0,
            squash_x = 1,
            squash_y = 1
        }
    end
    return anim_states[entity_id]
end

-- Limpar estado de uma entidade
function ProceduralAnim.clear_state(entity_id)
    anim_states[entity_id] = nil
end

-- Registrar explicitamente um vetor de direção/facing (ex.: a partir de input de movimento ou cast)
function ProceduralAnim.set_facing_vector(entity_id, dx, dy)
    if not entity_id or type(dx) ~= "number" or type(dy) ~= "number" then
        return
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 0.05 then
        return
    end
    local state = ProceduralAnim.get_state(entity_id)
    local ndx, ndy = dx / len, dy / len
    state.last_dx = ndx
    state.last_dy = ndy
    state.direction = calc_direction_8way(ndx, ndy, state.direction)
    if ndx > 0.05 then
        state.facing = 1
    elseif ndx < -0.05 then
        state.facing = -1
    end
end

-- Obter o último vetor unitário de direção/facing da entidade
function ProceduralAnim.get_facing_vector(entity_id)
    local state = entity_id and anim_states[entity_id]
    if not state then
        return 1.0, 0.0
    end
    if state.last_dx and state.last_dy then
        return state.last_dx, state.last_dy
    end
    if state.direction and state.direction ~= "south" and DIRECTION_VECTORS[state.direction] then
        local v = DIRECTION_VECTORS[state.direction]
        return v[1], v[2]
    end
    return (state.facing == -1) and -1.0 or 1.0, 0.0
end

-- Resolver direção de disparo para quick-cast (integra auto-aim -> movimento ativo -> facing quando parado)
function ProceduralAnim.resolve_cast_direction(entity_id, move_dx, move_dy, auto_aim_dx, auto_aim_dy)
    -- 1. Prioridade: alvo de mira automática (card #92), quando disponível
    if type(auto_aim_dx) == "number" and type(auto_aim_dy) == "number" then
        local alen = math.sqrt(auto_aim_dx * auto_aim_dx + auto_aim_dy * auto_aim_dy)
        if alen >= 0.1 then
            local ndx, ndy = auto_aim_dx / alen, auto_aim_dy / alen
            ProceduralAnim.set_facing_vector(entity_id, ndx, ndy)
            return ndx, ndy
        end
    end

    -- 2. Movimento ativo (joystick virtual ou teclado)
    local mdx = tonumber(move_dx) or 0
    local mdy = tonumber(move_dy) or 0
    if math.abs(mdx) >= 0.1 or math.abs(mdy) >= 0.1 then
        local mlen = math.sqrt(mdx * mdx + mdy * mdy)
        local ndx, ndy = mdx / mlen, mdy / mlen
        ProceduralAnim.set_facing_vector(entity_id, ndx, ndy)
        return ndx, ndy
    end

    -- 3. Fallback quando parado e sem alvo de auto-aim: última direção/facing do personagem
    return ProceduralAnim.get_facing_vector(entity_id)
end

-- Atualizar orientação de caminhada (8 direções)
-- Suporta tanto (dt, id, is_moving, vx, vy) quanto a chamada legada (dt, id, is_moving, facing_dir)
function ProceduralAnim.update_walk(dt, entity_id, is_moving, arg1, arg2)
    local state = ProceduralAnim.get_state(entity_id)
    state.is_moving = is_moving or false

    if type(arg1) == "number" and type(arg2) == "number" then
        -- Chamada com vetor de velocidade (vx, vy)
        local vx, vy = arg1, arg2
        if is_moving and (math.abs(vx) > 0.05 or math.abs(vy) > 0.05) then
            ProceduralAnim.set_facing_vector(entity_id, vx, vy)
        end
    elseif type(arg1) == "number" and arg1 ~= 0 then
        -- Chamada legada passando facing_dir (-1 ou 1)
        state.facing = arg1
        if arg1 > 0 then
            state.direction = "east"
            state.last_dx, state.last_dy = 1.0, 0.0
        else
            state.direction = "west"
            state.last_dx, state.last_dy = -1.0, 0.0
        end
    end

    -- Deformações de bobbing, tilt e squash neutralizadas para manter fidelidade estrita ao pixel art
    state.tilt_angle = 0
    state.bob_offset = 0
    state.squash_x = 1
    state.squash_y = 1

    return state
end

return ProceduralAnim
