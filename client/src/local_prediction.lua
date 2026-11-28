-- Predição local de movimento do jogador (handler de `_prediction_handler` do SDK).
-- Extraído de client/main.lua para permitir teste unitário.
--
-- Replica propositalmente a cinemática padrão de caminhada do `sdk-love2d`
-- (`move_speed * tick_rate * dt`) e aplica o cast lock autoritativo
-- (`casting_until`, publicado pelo servidor em ticks): durante a conjuração a
-- predição zera vx/vy para não divergir do servidor.

local LocalPrediction = {}

local function get_entity_prop(ent, key)
    if not ent then return nil end
    if ent.get then
        local v = ent:get(key)
        if v ~= nil then return v end
    end
    if ent[key] ~= nil then return ent[key] end
    return ent.properties and ent.properties[key] or nil
end

function LocalPrediction.is_casting(ent, cur_tick)
    local casting_until = tonumber(get_entity_prop(ent, "casting_until")) or 0
    return casting_until > (tonumber(cur_tick) or 0)
end

function LocalPrediction.get_slow_multiplier(ent, cur_tick)
    local slowed_until = tonumber(get_entity_prop(ent, "slowed_until")) or 0
    if slowed_until > (tonumber(cur_tick) or 0) then
        local mult = tonumber(get_entity_prop(ent, "slow_multiplier"))
        if mult ~= nil and mult >= 0.0 and mult <= 1.0 then
            return mult
        end
    end
    return 1.0
end

local function is_dead(ent)
    local d = get_entity_prop(ent, "is_dead")
    return d == true or d == "true" or d == 1 or d == "1"
end

-- env:
--   cur_tick              tick autoritativo do servidor (loci._last_state_tick)
--   tick_rate             ticks por segundo (loci.get_server_tick_rate())
--   default_speed         fallback de velocidade (loci.netcode.default_move_speed)
--   project_step(e,x,y)   projeção opcional de deslocamento (ex.: bodyblock tangencial)
--   clamp(ent)            função de clamp aos limites da arena (opcional)
function LocalPrediction.predict_local_movement(ent, dx, dy, dt, env)
    if not ent then return end
    env = env or {}

    if is_dead(ent) or LocalPrediction.is_casting(ent, env.cur_tick) then
        ent.vx = 0
        ent.vy = 0
        if env.clamp then env.clamp(ent) end
        return
    end

    local in_dx = dx or 0
    local in_dy = dy or 0
    local len = math.sqrt(in_dx * in_dx + in_dy * in_dy)

    if len > 0 then
        local ndx = in_dx / len
        local ndy = in_dy / len
        local default_speed = tonumber(env.default_speed) or 2.0
        local raw_speed = get_entity_prop(ent, "move_speed")
            or get_entity_prop(ent, "speed")
            or default_speed
        local move_speed = (tonumber(raw_speed) or 2.0) * LocalPrediction.get_slow_multiplier(ent, env.cur_tick)
        local tick_rate = tonumber(env.tick_rate) or 30.0
        local speed_sec = move_speed * tick_rate

        local step_x = ndx * speed_sec * dt
        local step_y = ndy * speed_sec * dt
        if type(env.project_step) == "function" then
            step_x, step_y = env.project_step(ent, step_x, step_y)
        end

        ent.x = (ent.x or 0) + step_x
        ent.y = (ent.y or 0) + step_y
        if dt > 0 and tick_rate > 0 then
            ent.vx = step_x / (tick_rate * dt)
            ent.vy = step_y / (tick_rate * dt)
        else
            ent.vx = ndx * move_speed
            ent.vy = ndy * move_speed
        end
    else
        ent.vx = 0
        ent.vy = 0
    end

    if env.clamp then env.clamp(ent) end
end

return LocalPrediction
