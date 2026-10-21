-- Procedural Animation System
-- Estilo "fantoche/South Park" - caminhada com rotação/balanço

local WALK_CONFIG = {
    step_frequency  = 13,      -- Ritmo dos passos ao caminhar
    max_tilt_deg    = 6,       -- Inclinação lateral da troca de peso dos pés (graus)
    bob_pixels      = 1.5,     -- Elevação vertical do passo em pixels nativos (16x16)
    stop_smoothness = 12,      -- Velocidade do retorno à posição neutra ao parar
    squash_amount   = 0.05,    -- Compressão no solo a cada passada (squash & stretch)
}

local ProceduralAnim = {}

-- Estado de animação por entidade
local anim_states = {}

-- Obter ou criar estado de animação para uma entidade
function ProceduralAnim.get_state(entity_id)
    if not anim_states[entity_id] then
        anim_states[entity_id] = {
            walk_timer = 0,
            tilt_angle = 0,
            target_tilt = 0,
            bob_offset = 0,
            squash_x = 1,
            squash_y = 1,
            facing = 1,
            last_moving = false
        }
    end
    return anim_states[entity_id]
end

-- Limpar estado de animação de uma entidade
function ProceduralAnim.clear_state(entity_id)
    anim_states[entity_id] = nil
end

-- Atualizar animação de caminhada
function ProceduralAnim.update_walk(dt, entity_id, is_moving, facing_dir)
    local state = ProceduralAnim.get_state(entity_id)
    
    -- Atualiza facing se fornecido
    if facing_dir ~= 0 then
        state.facing = facing_dir
    end
    
    if is_moving then
        state.walk_timer = state.walk_timer + dt
        local cycle = state.walk_timer * WALK_CONFIG.step_frequency
        local max_rad = math.rad(WALK_CONFIG.max_tilt_deg)
        
        -- Rotação lateral (til) baseada no facing
        state.target_tilt = math.sin(cycle) * max_rad * state.facing
        
        -- Elevação vertical (bob)
        state.bob_offset = -math.abs(math.sin(cycle)) * WALK_CONFIG.bob_pixels
        
        -- Squash & stretch suave
        local squash = math.sin(cycle * 2) * WALK_CONFIG.squash_amount
        state.squash_x = 1 + squash
        state.squash_y = 1 - squash
        
        state.last_moving = true
    else
        -- Parado: desaceleração suave de volta à posição neutra
        state.target_tilt = 0
        local stop_t = math.min(1, WALK_CONFIG.stop_smoothness * dt)
        state.bob_offset = state.bob_offset + (0 - state.bob_offset) * stop_t
        state.squash_x = state.squash_x + (1 - state.squash_x) * stop_t
        state.squash_y = state.squash_y + (1 - state.squash_y) * stop_t
        
        -- Zera timer se parado por um tempo
        if state.last_moving then
            state.walk_timer = 0
            state.last_moving = false
        end
    end
    
    -- Interpolação suave do ângulo de rotação (Lerp protegido contra dt spikes)
    local tilt_t = math.min(1, 16 * dt)
    state.tilt_angle = state.tilt_angle + (state.target_tilt - state.tilt_angle) * tilt_t
    
    return state
end

return ProceduralAnim
