-- Loci2D Default Arena Server Script
-- Versão com sistema de dano básico

local SPEED = 5.0
local MAX_HP = 100

function on_player_join(entity_id)
    Loci.Log.info("=== PLAYER JOIN START === " .. tostring(entity_id))
    
    -- Inicializa propriedades básicas
    Loci.Commands.set_property(entity_id, "kills", "0")
    Loci.Commands.set_property(entity_id, "deaths", "0")
    Loci.Commands.set_property(entity_id, "assists", "0")
    Loci.Commands.set_property(entity_id, "team", "1")
    Loci.Commands.set_property(entity_id, "hp", tostring(MAX_HP))
    Loci.Commands.set_property(entity_id, "max_hp", tostring(MAX_HP))
    Loci.Commands.set_property(entity_id, "dead", "false")
    
    Loci.Log.info("=== PLAYER JOIN END === " .. tostring(entity_id))
end

function on_move_intent(entity_id, dir_x, dir_y)
    -- Impede movimento de jogadores mortos
    local is_dead = Loci.get_entity_property(entity_id, "dead") == "true"
    if is_dead then
        return false, "Você está morto e não pode se mover"
    end
    
    Loci.Commands.set_velocity(entity_id, {x = dir_x * SPEED, y = dir_y * SPEED})
end

function on_action(entity_id, ability_id, aim_x, aim_y)
    Loci.Log.info("Action: " .. tostring(entity_id) .. " ability " .. tostring(ability_id))
    
    -- Impede ações de jogadores mortos
    local is_dead = Loci.get_entity_property(entity_id, "dead") == "true"
    if is_dead then
        return false, "Você está morto e não pode usar habilidades"
    end
    
    -- Sistema de dano com morte simples
    local my_pos = Loci.get_entity_position(entity_id)
    if my_pos then
        local entities = Loci.get_entities_in_radius(my_pos, 5.0)
        
        for _, target_id in ipairs(entities) do
            if target_id ~= entity_id then
                local target_dead = Loci.get_entity_property(target_id, "dead") == "true"
                if not target_dead then
                    local current_hp = tonumber(Loci.get_entity_property(target_id, "hp") or MAX_HP)
                    local damage = 25
                    local new_hp = math.max(0, current_hp - damage)
                    
                    Loci.Commands.set_property(target_id, "hp", tostring(new_hp))
                    Loci.Log.info("DAMAGE: " .. tostring(entity_id) .. " -> " .. tostring(target_id) .. " : " .. tostring(new_hp) .. "/" .. tostring(MAX_HP))
                    
                    -- Se morreu, marca como morto e atualiza estatísticas
                    if new_hp <= 0 then
                        Loci.Commands.set_property(target_id, "dead", "true")
                        
                        local kills = tonumber(Loci.get_entity_property(entity_id, "kills") or "0") + 1
                        Loci.Commands.set_property(entity_id, "kills", tostring(kills))
                        
                        local deaths = tonumber(Loci.get_entity_property(target_id, "deaths") or "0") + 1
                        Loci.Commands.set_property(target_id, "deaths", tostring(deaths))
                        
                        Loci.Log.info("KILL: " .. tostring(entity_id) .. " killed " .. tostring(target_id))
                    end
                end
            end
        end
    end
end

function on_player_leave(entity_id)
    Loci.Log.info("Player leave: " .. tostring(entity_id))
    Loci.Commands.destroy_entity(entity_id)
end
