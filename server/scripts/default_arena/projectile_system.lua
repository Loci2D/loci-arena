-- Projectile System
-- Sistema de projéteis que viajam no tempo e detectam colisão
local CombatSystem = require("core.combat_system")

local function get_coords(pos)
    if not pos then return 0, 0 end
    if type(pos.x_float) == "function" then
        return pos:x_float(), pos:y_float()
    elseif pos.x and pos.y then
        return pos.x, pos.y
    end
    return 0, 0
end

local projectiles = {}  -- Array para usar ipairs
local next_projectile_id = 1

local ProjectileSystem = {}

-- Spawna um projétil
function ProjectileSystem.spawn(caster_id, x, y, dir_x, dir_y, speed, damage, damage_type, max_distance, aoe_radius)
    local projectile_id = next_projectile_id
    next_projectile_id = next_projectile_id + 1
    
    local proj = {
        id = projectile_id,
        caster_id = caster_id,
        x = x,
        y = y,
        dir_x = dir_x,
        dir_y = dir_y,
        speed = speed,
        damage = damage,
        damage_type = damage_type,
        max_distance = max_distance,
        traveled = 0,
        aoe_radius = aoe_radius,
        active = true
    }
    
    table.insert(projectiles, proj)
    return projectile_id
end

-- Raycast entre dois pontos para detectar colisão de tunneling
local function raycast_collision(x1, y1, x2, y2, radius, caster_id)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist == 0 then
        return nil
    end

    -- Limites da arena [-500, +500]
    local ARENA_MIN = -500
    local ARENA_MAX = 500

    -- Dividir o caminho em pequenos passos para verificar colisão
    local steps = math.ceil(dist / 1)  -- Verificar a cada 1 unidade (máxima precisão)
    local step_x = dx / steps
    local step_y = dy / steps

    for i = 0, steps do
        local check_x = x1 + step_x * i
        local check_y = y1 + step_y * i

        -- Verificar colisão com paredes da arena
        if check_x < ARENA_MIN or check_x > ARENA_MAX or check_y < ARENA_MIN or check_y > ARENA_MAX then
            -- Clamp para dentro da arena para ponto de impacto
            local impact_x = math.max(ARENA_MIN, math.min(ARENA_MAX, check_x))
            local impact_y = math.max(ARENA_MIN, math.min(ARENA_MAX, check_y))
            return { type = "wall", x = impact_x, y = impact_y }
        end

        -- Buscar entidades em raio menor para obstáculos/players (paredes já verificadas)
        local hit_ids = Loci.get_entities_in_radius({ x = check_x, y = check_y }, 50)
        if hit_ids then
            for j = 1, #hit_ids do
                local entity_id = hit_ids[j]
                local obstacle_id = Loci.get_entity_property(entity_id, "obstacle_id")
                local entity_type = Loci.get_entity_property(entity_id, "entity_type")
                local team = Loci.get_entity_property(entity_id, "team")

                -- Verificar obstáculo
                if obstacle_id or entity_type == "Static" or entity_type == "Prop" then
                    local pos = Loci.get_entity_position(entity_id)
                    local ox, oy = get_coords(pos)
                    local obs_radius = tonumber(Loci.get_entity_property(entity_id, "radius") or 20)

                    local odx = check_x - ox
                    local ody = check_y - oy
                    local odist = math.sqrt(odx * odx + ody * ody)

                    if odist < (radius + obs_radius) then
                        return { type = "obstacle", x = check_x, y = check_y }
                    end
                end

                -- Verificar player
                if entity_id ~= caster_id and team and not obstacle_id then
                    local is_dead = Loci.get_entity_property(entity_id, "is_dead")
                    if is_dead ~= "true" then
                        local pos = Loci.get_entity_position(entity_id)
                        local px, py = get_coords(pos)
                        local player_radius = tonumber(Loci.get_entity_property(entity_id, "radius") or 15)

                        local pdx = check_x - px
                        local pdy = check_y - py
                        local pdist = math.sqrt(pdx * pdx + pdy * pdy)

                        if pdist < (radius + player_radius) then
                            return { type = "player", entity_id = entity_id, x = check_x, y = check_y }
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- Atualiza todos os projéteis (chamado a cada tick)
function ProjectileSystem.update_tick(current_tick)
    if current_tick % 30 == 0 and #projectiles > 0 then
        Loci.Log.info(string.format("[Projectile] Atualizando %d projéteis ativos no tick %d",
            #projectiles, current_tick))
    end

    local to_remove = {}

    for i = #projectiles, 1, -1 do
        local proj = projectiles[i]
        if not proj.active then
            table.remove(projectiles, i)
            goto continue
        end

        -- Salvar posição anterior
        local old_x = proj.x
        local old_y = proj.y

        -- Mover projétil
        local move_x = proj.dir_x * proj.speed
        local move_y = proj.dir_y * proj.speed
        proj.x = proj.x + move_x
        proj.y = proj.y + move_y
        proj.traveled = proj.traveled + math.sqrt(move_x * move_x + move_y * move_y)

        -- Verificar se atingiu a distância máxima
        if proj.traveled >= proj.max_distance then
            Loci.Log.info(string.format("[Projectile] Projétil %d atingiu distância máxima (%.1f/%.1f)",
                proj.id, proj.traveled, proj.max_distance))
            ProjectileSystem.explode(proj)
            table.remove(projectiles, i)
            goto continue
        end

        -- Raycast entre posição antiga e nova para evitar tunneling
        local collision = raycast_collision(old_x, old_y, proj.x, proj.y, 8, proj.caster_id)

        if collision then
            if collision.type == "wall" then
                proj.x = collision.x
                proj.y = collision.y
                Loci.Log.info(string.format("[Projectile] Projétil %d bateu na parede em (%.1f, %.1f)",
                    proj.id, proj.x, proj.y))
                ProjectileSystem.explode(proj)
                table.remove(projectiles, i)
                goto continue
            elseif collision.type == "obstacle" then
                proj.x = collision.x
                proj.y = collision.y
                Loci.Log.info(string.format("[Projectile] Projétil %d bateu em obstáculo em (%.1f, %.1f)",
                    proj.id, proj.x, proj.y))
                ProjectileSystem.explode(proj)
                table.remove(projectiles, i)
                goto continue
            elseif collision.type == "player" then
                proj.x = collision.x
                proj.y = collision.y
                Loci.Log.info(string.format("[Projectile] Projétil %d bateu no player %d em (%.1f, %.1f)",
                    proj.id, collision.entity_id, proj.x, proj.y))
                ProjectileSystem.explode(proj)
                table.remove(projectiles, i)
                goto continue
            end
        end

        ::continue::
    end
end

-- Verifica colisão com obstáculos
function ProjectileSystem.check_obstacle_collision(x, y, radius)
    -- Usa get_entities_in_radius para buscar obstáculos na área
    local hit_ids = Loci.get_entities_in_radius({ x = x, y = y }, radius + 50)

    if hit_ids then
        for i = 1, #hit_ids do
            local entity_id = hit_ids[i]
            -- Verifica várias propriedades para identificar obstáculos
            local obstacle_id = Loci.get_entity_property(entity_id, "obstacle_id")
            local entity_type = Loci.get_entity_property(entity_id, "entity_type")

            -- Obstáculos têm obstacle_id definido ou entity_type = "Static" (ou "Prop" se convertido)
            if obstacle_id or entity_type == "Static" or entity_type == "Prop" then
                local pos = Loci.get_entity_position(entity_id)
                local ox, oy = get_coords(pos)
                local obs_radius = tonumber(Loci.get_entity_property(entity_id, "radius") or 20)

                local dx = x - ox
                local dy = y - oy
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist < (radius + obs_radius) then
                    return true
                end
            end
        end
    end

    return false
end

-- Verifica colisão com players
function ProjectileSystem.check_player_collision(x, y, radius, caster_id)
    -- Usa get_entities_in_radius para buscar players na área
    local hit_ids = Loci.get_entities_in_radius({ x = x, y = y }, radius + 50)

    if hit_ids then
        for _, entity_id in ipairs(hit_ids) do
            if entity_id ~= caster_id then
                -- Verifica se é um player (tem team definido mas não obstacle_id)
                local obstacle_id = Loci.get_entity_property(entity_id, "obstacle_id")
                local team = Loci.get_entity_property(entity_id, "team")

                -- É um player se tem team mas não tem obstacle_id
                if team and not obstacle_id then
                    local is_dead = Loci.get_entity_property(entity_id, "is_dead")
                    if is_dead ~= "true" then
                        local pos = Loci.get_entity_position(entity_id)
                        local px, py = get_coords(pos)
                        local player_radius = tonumber(Loci.get_entity_property(entity_id, "radius") or 15)

                        local dx = x - px
                        local dy = y - py
                        local dist = math.sqrt(dx * dx + dy * dy)

                        if dist < (radius + player_radius) then
                            return entity_id
                        end
                    end
                end
            end
        end
    end

    return false
end

-- Explode o projétil causando dano em área
function ProjectileSystem.explode(proj)
    local caster_team = Loci.get_entity_property(proj.caster_id, "team") or tostring(proj.caster_id)

    -- Buscar entidades na área de explosão
    local hit_ids = Loci.get_entities_in_radius({ x = proj.x, y = proj.y }, proj.aoe_radius)

    local hit_count = 0
    if hit_ids then
        for _, target_id in ipairs(hit_ids) do
            if target_id ~= proj.caster_id then
                local target_team = Loci.get_entity_property(target_id, "team") or tostring(target_id)
                local is_dead = Loci.get_entity_property(target_id, "is_dead")
                local obstacle_id = Loci.get_entity_property(target_id, "obstacle_id")

                if target_team ~= caster_team and not obstacle_id then
                    if is_dead ~= "true" then
                        CombatSystem.process_hit(proj.caster_id, target_id, proj.damage, proj.damage_type)
                        hit_count = hit_count + 1
                    end
                end
            end
        end
    end

    Loci.Log.info(string.format("[Projectile] Projétil %d explodiu em (%.1f, %.1f) acertando %d alvos",
        proj.id, proj.x, proj.y, hit_count))
end

-- Limpa todos os projéteis
function ProjectileSystem.clear()
    projectiles = {}
end

return ProjectileSystem
