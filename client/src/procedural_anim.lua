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

-- Atualizar orientação de caminhada (8 direções)
-- Suporta tanto (dt, id, is_moving, vx, vy) quanto a chamada legada (dt, id, is_moving, facing_dir)
function ProceduralAnim.update_walk(dt, entity_id, is_moving, arg1, arg2)
    local state = ProceduralAnim.get_state(entity_id)
    state.is_moving = is_moving or false

    if type(arg1) == "number" and type(arg2) == "number" then
        -- Chamada com vetor de velocidade (vx, vy)
        local vx, vy = arg1, arg2
        if is_moving and (math.abs(vx) > 0.05 or math.abs(vy) > 0.05) then
            state.direction = calc_direction_8way(vx, vy, state.direction)
            if vx > 0.05 then
                state.facing = 1
            elseif vx < -0.05 then
                state.facing = -1
            end
        end
    elseif type(arg1) == "number" and arg1 ~= 0 then
        -- Chamada legada passando facing_dir (-1 ou 1)
        state.facing = arg1
        if arg1 > 0 then
            state.direction = "east"
        else
            state.direction = "west"
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
