-- Loci Arena - Authoritative Game Logic (Lua Server Script)
-- This script runs inside the loci2d server environment.
-- Rules, physics modifications, damage and game mechanics must be handled here.

-- Arena personalizada com fireball e dash
local fireballs = {}
local current_tick = 0

-- Configurações da fireball
local FIREBALL_SPEED = 2.0
local FIREBALL_LIFETIME = 120  -- ticks (~4 segundos)
local FIREBALL_DAMAGE = 10
local FIREBALL_RADIUS = 2
local FIREBALL_SPAWN_OFFSET = 0.0
local HIT_RADIUS = 5.0

-- Configurações de movimento
local PLAYER_SPEED = 5.0

-- Configurações de dash
local DASH_DISTANCE = 25.0
local DASH_COOLDOWN = 30
local dash_cooldowns = {}

-- Configurações de escudo
local SHIELD_DURATION = 180  -- ticks (~6 segundos)
local SHIELD_REDUCTION = 0.5  -- 50% de redução de dano
local shield_active_list = {}  -- lista de {entity_id, end_tick}

-- Rastrear última direção de movimento
local last_move_directions = {}

-- Função para verificar se é jogador
local function is_player(entity_id)
    local kind = Loci.get_entity_property(entity_id, "kind")
    return kind == "player"
end

-- Função para aplicar dano
local function apply_damage(entity_id, damage)
    -- Verificar escudo
    local shield_active = false
    for _, shield in ipairs(shield_active_list) do
        if shield.entity_id == entity_id and current_tick < shield.end_tick then
            shield_active = true
            break
        end
    end
    
    if shield_active then
        damage = damage * SHIELD_REDUCTION
    end
    
    local current_hp = Loci.get_entity_property(entity_id, "hp") or 100
    local new_hp = current_hp - damage
    Loci.Commands.set_property(entity_id, "hp", tostring(new_hp))
    
    if new_hp <= 0 then
        Loci.Commands.destroy_entity(entity_id)
    end
end

function on_player_join(entity_id)
    Loci.Log.info("[Arena] Player joined with entity ID " .. tostring(entity_id))
    
    Loci.Commands.set_property(entity_id, "team", "1")
    Loci.Commands.set_property(entity_id, "hp", "100")
    Loci.Commands.set_property(entity_id, "max_hp", "100")
    Loci.Commands.set_property(entity_id, "score", "0")
    Loci.Commands.set_property(entity_id, "kind", "player")
end

function on_move_intent(entity_id, dir_x, dir_y)
    -- Rastrear direção
    if dir_x ~= 0 or dir_y ~= 0 then
        last_move_directions[entity_id] = {x = dir_x, y = dir_y}
    end
    
    -- Normalizar movimento
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if len > 0 then
        dir_x = dir_x / len
        dir_y = dir_y / len
    end
    
    Loci.Commands.set_velocity(entity_id, {
        x = dir_x * PLAYER_SPEED,
        y = dir_y * PLAYER_SPEED
    })
    return true
end

function on_action(entity_id, ability_id, dir_x, dir_y)
    Loci.Log.info("[Arena] Action from entity " .. tostring(entity_id) .. " -> Ability: " .. tostring(ability_id))
    
    if ability_id == 1 then
        -- Fireball
        local pos = Loci.get_entity_position(entity_id)
        if pos then
            local px, py = pos:x_float(), pos:y_float()
            
            -- Pegar direção (última movimento ou padrão)
            local last_dir = last_move_directions[entity_id]
            local fb_dir_x, fb_dir_y = 1, 0
            if last_dir then
                fb_dir_x = last_dir.x
                fb_dir_y = last_dir.y
                Loci.Log.info("[Arena] Fireball - Last dir: " .. fb_dir_x .. ", " .. fb_dir_y)
            else
                Loci.Log.info("[Arena] Fireball - No last dir, using default 1, 0")
            end
            
            local spawn_x = px + fb_dir_x * FIREBALL_SPAWN_OFFSET
            local spawn_y = py + fb_dir_y * FIREBALL_SPAWN_OFFSET
            
            local fireball_id = Loci.Commands.spawn_entity({
                position = {x = spawn_x, y = spawn_y},
                blueprint = "fireball",
                entity_type = "Prop",
                move_speed = FIREBALL_SPEED,
                radius = FIREBALL_RADIUS,
                properties = {
                    owner = tostring(entity_id),
                    kind = "fireball"
                }
            })
            
            if fireball_id then
                Loci.Commands.set_velocity(fireball_id, {x = fb_dir_x * FIREBALL_SPEED, y = fb_dir_y * FIREBALL_SPEED})
                fireballs[#fireballs + 1] = {
                    id = fireball_id,
                    owner = entity_id,
                    expires_at = current_tick + FIREBALL_LIFETIME
                }
            end
        end
    elseif ability_id == 2 then
        -- Dash
        local cooldown_end = dash_cooldowns[entity_id] or 0
        if current_tick < cooldown_end then
            return false, "Dash em cooldown"
        end
        
        -- Usar última direção de movimento
        local last_dir = last_move_directions[entity_id]
        local dash_dir_x, dash_dir_y = 1, 0
        if last_dir then
            dash_dir_x = last_dir.x
            dash_dir_y = last_dir.y
        end
        
        local len_sq = dash_dir_x * dash_dir_x + dash_dir_y * dash_dir_y
        if len_sq > 0.01 then
            local pos = Loci.get_entity_position(entity_id)
            if pos then
                local px, py = pos:x_float(), pos:y_float()
                local new_x = px + dash_dir_x * DASH_DISTANCE
                local new_y = py + dash_dir_y * DASH_DISTANCE
                Loci.Commands.set_position(entity_id, {x = new_x, y = new_y})
                dash_cooldowns[entity_id] = current_tick + DASH_COOLDOWN
                return true
            end
        end
        return false, "Direção inválida para dash"
    elseif ability_id == 4 then
        -- Escudo
        shield_active_list[#shield_active_list + 1] = {
            entity_id = entity_id,
            end_tick = current_tick + SHIELD_DURATION
        }
        Loci.Commands.set_property(entity_id, "shield_active", "true")
    end
    
    return true
end

function on_collision(entity_a_id, entity_b_id)
    local kind_a = Loci.get_entity_property(entity_a_id, "kind")
    local kind_b = Loci.get_entity_property(entity_b_id, "kind")
    
    if kind_a == "fireball" then
        Loci.Commands.destroy_entity(entity_a_id)
    end
    if kind_b == "fireball" then
        Loci.Commands.destroy_entity(entity_b_id)
    end
end

function on_tick(tick)
    current_tick = tick
    
    -- Gerenciar escudo ativo
    local active_shields = {}
    for _, shield in ipairs(shield_active_list) do
        if tick >= shield.end_tick then
            Loci.Commands.set_property(shield.entity_id, "shield_active", "false")
        else
            active_shields[#active_shields + 1] = shield
        end
    end
    shield_active_list = active_shields
    
    if #fireballs == 0 then
        return
    end
    
    local alive = {}
    local destroyed = {}
    
    for _, fb in ipairs(fireballs) do
        local keep = true
        local pos = Loci.get_entity_position(fb.id)
        
        if not pos or tick >= fb.expires_at then
            if not destroyed[fb.id] then
                Loci.Commands.destroy_entity(fb.id)
                destroyed[fb.id] = true
            end
            keep = false
        else
            local near = Loci.get_entities_in_radius(pos, HIT_RADIUS)
            for _, id in ipairs(near) do
                if keep and id ~= fb.id and id ~= fb.owner and not destroyed[id] then
                    local entity_kind = Loci.get_entity_property(id, "kind")
                    if is_player(id) then
                        apply_damage(id, FIREBALL_DAMAGE)
                        if not destroyed[fb.id] then
                            Loci.Commands.destroy_entity(fb.id)
                            destroyed[fb.id] = true
                        end
                        keep = false
                    elseif entity_kind == "fireball" then
                        if fb.id < id and not destroyed[fb.id] then
                            Loci.Commands.destroy_entity(fb.id)
                            destroyed[fb.id] = true
                            keep = false
                        end
                    end
                end
            end
        end
        
        if keep then
            alive[#alive + 1] = fb
        end
    end
    fireballs = alive
end

function on_player_leave(entity_id)
    Loci.Log.info("[Arena] Player left: " .. tostring(entity_id))
    Loci.Commands.destroy_entity(entity_id)
end
