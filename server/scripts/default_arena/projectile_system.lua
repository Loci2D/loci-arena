-- Sistema de Projéteis para Loci Arena
-- Gerencia spawn, movimento, colisão e dano de projéteis
-- OBSERVAÇÃO: Este sistema usa raycast instantâneo porque o servidor loci2d
-- não parece suportar spawn de entidades dinâmicas com física autoritativa.

local projectile_system = {}

-- Configurações
local PROJECTILE_RANGE = 200.0      -- Alcance máximo do tiro
local PROJECTILE_DAMAGE = 10       -- Dano por acerto
local PROJECTILE_COOLDOWN = 15      -- Cooldown em ticks (0.5 segundos a 30Hz)

-- Cooldown por jogador
local player_cooldowns = {}

-- Função auxiliar para calcular distância
local function distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- Função auxiliar para obter posição de uma entidade
local function get_entity_position(entity_id)
    local ent = Loci.get_entity(entity_id)
    if ent then
        return ent.x, ent.y
    end
    return 0, 0
end

-- Função auxiliar para obter todas as entidades
local function get_all_entities()
    local entities = {}
    -- Tentar diferentes métodos para obter entidades
    if Loci.get_all_entities then
        local all_ents = Loci.get_all_entities()
        for id, ent in pairs(all_ents) do
            entities[id] = ent
        end
    elseif Loci.Entities then
        for id, ent in pairs(Loci.Entities) do
            entities[id] = ent
        end
    elseif Loci.World and Loci.World.entities then
        for id, ent in pairs(Loci.World.entities) do
            entities[id] = ent
        end
    end
    return entities
end

-- Disparar projétil usando raycast instantâneo
function projectile_system.spawn(owner_id, origin_x, origin_y, dir_x, dir_y)
    -- Verificar cooldown
    local current_tick = Loci.get_tick and Loci.get_tick() or 0
    local last_shot = player_cooldowns[owner_id] or 0
    
    if current_tick - last_shot < PROJECTILE_COOLDOWN then
        return false, "Projétil em cooldown"
    end
    
    -- Atualizar cooldown
    player_cooldowns[owner_id] = current_tick
    
    -- Calcular ponto final do raycast
    local end_x = origin_x + dir_x * PROJECTILE_RANGE
    local end_y = origin_y + dir_y * PROJECTILE_RANGE
    
    -- Verificar colisão com jogadores usando raycast
    local entities = get_all_entities()
    local closest_hit = nil
    local closest_dist = PROJECTILE_RANGE
    
    for ent_id, ent in pairs(entities) do
        -- Pular o próprio dono do projétil
        if ent_id == owner_id then
            goto skip_entity
        end
        
        -- Verificar se é um jogador (tem HP)
        local hp = Loci.Commands.get_property and Loci.Commands.get_property(ent_id, "hp")
        if hp then
            local ent_x, ent_y = get_entity_position(ent_id)
            
            -- Calcular distância da origem até o alvo
            local dist_to_target = distance(origin_x, origin_y, ent_x, ent_y)
            
            -- Verificar se está dentro do alcance
            if dist_to_target <= PROJECTILE_RANGE then
                -- Verificar se está na direção do tiro (produto escalar)
                local to_target_x = ent_x - origin_x
                local to_target_y = ent_y - origin_y
                local dot_product = to_target_x * dir_x + to_target_y * dir_y
                
                -- Se o produto escalar for positivo, está na direção
                if dot_product > 0 then
                    -- Calcular distância perpendicular à linha de tiro
                    local proj_length = dot_product
                    local closest_point_x = origin_x + dir_x * proj_length
                    local closest_point_y = origin_y + dir_y * proj_length
                    local perp_dist = distance(closest_point_x, closest_point_y, ent_x, ent_y)
                    
                    -- Se a distância perpendicular for pequena (5.0 = raio do jogador)
                    if perp_dist < 10.0 then
                        if dist_to_target < closest_dist then
                            closest_dist = dist_to_target
                            closest_hit = ent_id
                        end
                    end
                end
            end
        end
        
        ::skip_entity::
    end
    
    -- Aplicar dano se houve acerto
    if closest_hit then
        local current_hp = tonumber(Loci.Commands.get_property(closest_hit, "hp")) or 100
        local new_hp = math.max(0, current_hp - PROJECTILE_DAMAGE)
        
        Loci.Commands.set_property(closest_hit, "hp", tostring(new_hp))
        Loci.Log.info("[Projectile] Hit! Entity " .. closest_hit .. " took " .. PROJECTILE_DAMAGE .. " damage (HP: " .. new_hp .. ")")
        return true, "hit"
    else
        Loci.Log.info("[Projectile] Missed from entity " .. owner_id)
        return true, "miss"
    end
end

-- Função placeholder para compatibilidade
function projectile_system.update()
    -- Raycast instantâneo não precisa de update
end

-- Função placeholder para compatibilidade
function projectile_system.destroy(projectile_id)
    -- Raycast instantâneo não tem entidades para destruir
end

-- Limpar cooldowns
function projectile_system.clear()
    player_cooldowns = {}
end

-- Obter número de projéteis ativos (sempre 0 para raycast)
function projectile_system.get_count()
    return 0
end

return projectile_system
