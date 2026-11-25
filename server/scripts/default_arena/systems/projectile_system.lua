-- Projectile System (Authoritative Server)
-- Gerencia o ciclo de vida, física sensora (CCD) e handlers de impacto de projéteis nativos (EntityType::Projectile).

local CombatSystem = require("core.combat_system")
local CharacterFactory = require("systems.character_factory")
local ArenaBounds = require("core.arena_bounds")

local ProjectileSystem = {}

-- Registro determinístico de projéteis ativos:
-- active_projectiles[proj_id] = metadados do projétil
-- projectile_order = array ordenado de IDs para iteração segura no sandbox (sem depender de pairs)
local active_projectiles = {}
local projectile_order = {}

-- Mapeamento de handlers de impacto por habilidade: impact_handlers[skill_id] = function(proj, impact_x, impact_y, target_id)
local impact_handlers = {}

local DEFAULT_LAYER_SOLID_WALL = 1
local DEFAULT_LAYER_PLAYER = 2
local DEFAULT_LAYER_PROJECTILE = 8

local function get_coords(pos)
    if not pos then return 0, 0 end
    if type(pos.x_float) == "function" then
        return pos:x_float(), pos:y_float()
    elseif pos.x and pos.y then
        return pos.x, pos.y
    end
    return 0, 0
end

local function get_entity_xy(entity_id)
    if not (Loci and Loci.get_entity_position and entity_id) then
        return nil, nil
    end
    local pos = Loci.get_entity_position(entity_id)
    if not pos then
        return nil, nil
    end
    return get_coords(pos)
end

local function is_entity_dead(entity_id)
    if not (Loci and Loci.get_entity_property and entity_id) then
        return false
    end
    local dead_prop = Loci.get_entity_property(entity_id, "is_dead")
    if dead_prop == "true" or dead_prop == true or dead_prop == "1" or dead_prop == 1 then
        return true
    end
    local hp = tonumber(Loci.get_entity_property(entity_id, "hp"))
    if hp ~= nil and hp <= 0 then
        return true
    end
    return false
end

local function get_default_collision_filter()
    local layer = DEFAULT_LAYER_PROJECTILE
    local mask = DEFAULT_LAYER_SOLID_WALL + DEFAULT_LAYER_PLAYER
    if Loci and Loci.Physics and Loci.Physics.Layer then
        local L = Loci.Physics.Layer
        layer = L.PROJECTILE or DEFAULT_LAYER_PROJECTILE
        local wall_bit = L.SOLID_WALL or DEFAULT_LAYER_SOLID_WALL
        local player_bit = L.PLAYER or DEFAULT_LAYER_PLAYER
        mask = wall_bit + player_bit
    end
    return layer, mask
end

local function remove_from_tracking(proj_id)
    active_projectiles[proj_id] = nil
    for i = #projectile_order, 1, -1 do
        if projectile_order[i] == proj_id then
            table.remove(projectile_order, i)
            break
        end
    end
end

local function destroy_projectile(proj_id)
    remove_from_tracking(proj_id)
    if Loci and Loci.Commands and Loci.Commands.destroy_entity then
        Loci.Commands.destroy_entity(proj_id)
    end
end

-- Handler padrão de impacto (suporta dano direto ou explosão em área AoE + Crowd Control / Stun)
local function execute_default_aoe_impact(proj, impact_x, impact_y, direct_target_id)
    local aoe_radius = tonumber(proj.aoe_radius) or 0
    local hit_ids = nil

    if aoe_radius > 0 and Loci and Loci.get_entities_in_radius then
        hit_ids = Loci.get_entities_in_radius({ x = impact_x, y = impact_y }, aoe_radius)
    elseif direct_target_id then
        hit_ids = { direct_target_id }
    end

    local hit_count = 0
    local current_tick = (CharacterFactory and CharacterFactory.get_current_tick and CharacterFactory.get_current_tick()) or 0

    if hit_ids then
        for _, target_id in ipairs(hit_ids) do
            if target_id ~= proj.caster_id and not ProjectileSystem.is_projectile(target_id) and not is_entity_dead(target_id) then
                local target_team = (Loci and Loci.get_entity_property and Loci.get_entity_property(target_id, "team")) or "2"
                if tostring(target_team) ~= tostring(proj.team) then
                    if proj.damage and proj.damage > 0 then
                        CombatSystem.process_hit(proj.caster_id, target_id, proj.damage, proj.damage_type)
                    end

                    if proj.stun_duration_ticks and proj.stun_duration_ticks > 0 then
                        local stun_until = current_tick + proj.stun_duration_ticks
                        Loci.Commands.set_property(target_id, "stunned_until", tostring(stun_until))
                        Loci.Commands.set_velocity(target_id, { x = 0, y = 0 })
                    end

                    if proj.slow_duration_ticks and proj.slow_duration_ticks > 0 and not is_entity_dead(target_id) then
                        CombatSystem.apply_slow(target_id, proj.slow_multiplier or 0.5, proj.slow_duration_ticks, current_tick)
                    end

                    hit_count = hit_count + 1
                end
            end
        end
    end

    return hit_count
end

--- Registra ou sobrescreve o handler de impacto para um `skill_id`.
function ProjectileSystem.register_impact_handler(skill_id, handler_fn)
    if type(skill_id) == "string" and type(handler_fn) == "function" then
        impact_handlers[skill_id] = handler_fn
    end
end

-- Handlers nativos das habilidades de projétil da Arena
ProjectileSystem.register_impact_handler("blade_throw", function(proj, impact_x, impact_y, direct_target_id)
    local hit_count = execute_default_aoe_impact(proj, impact_x, impact_y, direct_target_id)
    if Loci and Loci.Log then
        local travel_dist = math.sqrt((impact_x - proj.start_x) ^ 2 + (impact_y - proj.start_y) ^ 2)
        Loci.Log.info(string.format(
            "[Blade Throw] Impacto do projétil %s de %s em (%.1f, %.1f) (dist=%.1f, acertou %d alvos)",
            tostring(proj.id), tostring(proj.caster_id), impact_x, impact_y, travel_dist, hit_count
        ))
    end
    return hit_count
end)

ProjectileSystem.register_impact_handler("fireball", function(proj, impact_x, impact_y, direct_target_id)
    local hit_count = execute_default_aoe_impact(proj, impact_x, impact_y, direct_target_id)
    if Loci and Loci.Log then
        Loci.Log.info(string.format(
            "[Fireball] Impacto do projétil %s de %s em (%.1f, %.1f) (acertou %d alvos na explosão)",
            tostring(proj.id), tostring(proj.caster_id), impact_x, impact_y, hit_count
        ))
    end
    return hit_count
end)

--- Verifica se um `entity_id` corresponde a um projétil ativo ou do tipo Projectile.
function ProjectileSystem.is_projectile(entity_id)
    if not entity_id then return false end
    if active_projectiles[entity_id] ~= nil then
        return true
    end
    if Loci and Loci.get_entity_type then
        local ok, etype = pcall(Loci.get_entity_type, entity_id)
        if ok and (etype == "Projectile" or etype == "projectile") then
            return true
        end
    end
    if Loci and Loci.get_entity_property then
        local prop_type = Loci.get_entity_property(entity_id, "entity_type")
        if prop_type == "projectile" or prop_type == "Projectile" then
            return true
        end
    end
    return false
end

--- Obtém os metadados rastreados de um projétil ativo.
function ProjectileSystem.get_projectile(proj_id)
    return active_projectiles[proj_id]
end

--- Retorna a quantidade de projéteis ativos rastreados.
function ProjectileSystem.get_active_count()
    return #projectile_order
end

--- Spawna um projétil autoritativo (`EntityType::Projectile`) com sensor CCD, lifetime, velocidade e filtro de colisão.
function ProjectileSystem.spawn(params)
    assert(type(params) == "table", "ProjectileSystem.spawn expects a params table")

    local caster_id = params.caster_id
    local skill_id = tostring(params.skill_id or params.blueprint or "projectile")
    local blueprint = tostring(params.blueprint or skill_id)

    -- Normaliza direção de disparo (padrão +X se nulo)
    local dir_x = tonumber(params.dir_x) or 0
    local dir_y = tonumber(params.dir_y) or 0
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if len > 0 then
        dir_x = dir_x / len
        dir_y = dir_y / len
    else
        dir_x, dir_y = 1.0, 0.0
    end

    -- Posição inicial
    local start_x = tonumber(params.x)
    local start_y = tonumber(params.y)
    if start_x == nil or start_y == nil then
        local cx, cy = get_entity_xy(caster_id)
        start_x = start_x or cx or 0.0
        start_y = start_y or cy or 0.0
    end

    local speed = tonumber(params.speed) or 4.0
    local range = tonumber(params.range) or 56.0
    local radius = tonumber(params.radius) or 1.5
    local aoe_radius = tonumber(params.aoe_radius) or 0.0
    local lifetime_ticks = tonumber(params.lifetime_ticks) or math.max(1, math.ceil(range / math.max(0.001, speed)))
    -- Margem de +1 tick no motor para permitir que o script processe explosão de alcance máximo no fim do voo
    local engine_lifetime = lifetime_ticks + 1

    local team = params.team
    if not team and caster_id and Loci and Loci.get_entity_property then
        team = Loci.get_entity_property(caster_id, "team")
    end
    team = tostring(team or "1")

    local default_layer, default_mask = get_default_collision_filter()
    local layer = tonumber(params.collision_layer or params.layer) or default_layer
    local mask = tonumber(params.collision_mask or params.mask) or default_mask

    local vx = dir_x * speed
    local vy = dir_y * speed

    local properties = {
        entity_type = "projectile",
        skill_id = skill_id,
        skill_name = skill_id,
        owner_id = tostring(caster_id or 0),
        team = team,
        dir_x = tostring(dir_x),
        dir_y = tostring(dir_y),
        aoe_radius = tostring(aoe_radius),
        range = tostring(range),
    }
    if type(params.properties) == "table" then
        for k, v in pairs(params.properties) do
            properties[tostring(k)] = tostring(v)
        end
    end

    local proj_id = Loci.Commands.spawn_entity({
        blueprint = blueprint,
        entity_type = "Projectile",
        position = { x = start_x, y = start_y },
        velocity = { x = vx, y = vy },
        move_speed = speed,
        radius = radius,
        is_sensor = true,
        lifetime_ticks = engine_lifetime,
        collision_layer = layer,
        collision_mask = mask,
        properties = properties,
    })

    -- Garante aplicação explícita dos comandos de sensor, lifetime, velocidade e layer
    if Loci.Commands.set_sensor then
        Loci.Commands.set_sensor(proj_id, true)
    end
    if Loci.Commands.set_lifetime then
        Loci.Commands.set_lifetime(proj_id, engine_lifetime)
    end
    if Loci.Commands.set_velocity then
        Loci.Commands.set_velocity(proj_id, { x = vx, y = vy })
    end
    if Loci.Commands.set_collision_filter then
        Loci.Commands.set_collision_filter(proj_id, layer, mask)
    end

    local current_tick = (CharacterFactory and CharacterFactory.get_current_tick and CharacterFactory.get_current_tick()) or 0

    local record = {
        id = proj_id,
        caster_id = caster_id,
        skill_id = skill_id,
        blueprint = blueprint,
        team = team,
        start_x = start_x,
        start_y = start_y,
        dir_x = dir_x,
        dir_y = dir_y,
        speed = speed,
        vx = vx,
        vy = vy,
        range = range,
        radius = radius,
        aoe_radius = aoe_radius,
        damage = tonumber(params.damage) or 0,
        damage_type = params.damage_type or CombatSystem.DamageType.PHYSICAL,
        stun_duration_ticks = tonumber(params.stun_duration_ticks) or 0,
        slow_duration_ticks = tonumber(params.slow_duration_ticks) or 0,
        slow_multiplier = tonumber(params.slow_multiplier) or 0.5,
        lifetime_ticks = lifetime_ticks,
        spawn_tick = current_tick,
        steps_taken = 0,
        detonate_on_max_range = params.detonate_on_max_range == true,
        on_impact = params.on_impact,
        resolved = false,
    }

    active_projectiles[proj_id] = record
    table.insert(projectile_order, proj_id)

    return proj_id, record
end

local function trigger_impact(proj, impact_x, impact_y, target_id)
    if not proj or proj.resolved then
        return
    end
    proj.resolved = true

    -- Atualiza coordenada autoritativa final antes do despawn para sincronização visual no cliente
    if Loci and Loci.Commands and Loci.Commands.set_position then
        local cx, cy = impact_x, impact_y
        if ArenaBounds and ArenaBounds.ARENA_MIN and ArenaBounds.ARENA_MAX then
            cx = math.max(ArenaBounds.ARENA_MIN, math.min(ArenaBounds.ARENA_MAX, cx))
            cy = math.max(ArenaBounds.ARENA_MIN, math.min(ArenaBounds.ARENA_MAX, cy))
        end
        Loci.Commands.set_position(proj.id, { x = cx, y = cy })
    end

    local handler = proj.on_impact or impact_handlers[proj.skill_id] or execute_default_aoe_impact
    handler(proj, impact_x, impact_y, target_id)
end

--- Processa colisão dinâmica envolvendo pelo menos um projétil (`on_collision`).
function ProjectileSystem.on_collision(entity_a, entity_b)
    local proj_a = active_projectiles[entity_a]
    local proj_b = active_projectiles[entity_b]

    -- Projéteis não colidem entre si
    if proj_a and proj_b then
        return true
    end
    if not proj_a and not proj_b then
        if ProjectileSystem.is_projectile(entity_a) or ProjectileSystem.is_projectile(entity_b) then
            return true
        end
        return false
    end

    local proj = proj_a or proj_b
    local target_id = proj_a and entity_b or entity_a

    if proj.resolved then
        return true
    end

    -- Ignora colisão com o próprio lançador, outros projéteis ou entidades mortas
    if target_id == proj.caster_id or ProjectileSystem.is_projectile(target_id) or is_entity_dead(target_id) then
        return true
    end

    -- Ignora aliados (projétil atravessa aliados sem parar e sem causar dano)
    local target_team = (Loci and Loci.get_entity_property and Loci.get_entity_property(target_id, "team")) or nil
    if target_team ~= nil and tostring(target_team) == tostring(proj.team) then
        return true
    end

    -- Calcula ponto de impacto real a partir da posição do projétil / projeção no raio até o alvo
    local px, py = get_entity_xy(proj.id)
    local tx, ty = get_entity_xy(target_id)

    -- Evita atingir inimigos posicionados atrás da origem do disparo
    if tx and ty then
        local rel_x = tx - proj.start_x
        local rel_y = ty - proj.start_y
        local dot = rel_x * proj.dir_x + rel_y * proj.dir_y
        if dot < -0.1 then
            return true
        end
    end

    local impact_x = px or tx or proj.start_x
    local impact_y = py or ty or proj.start_y

    if tx and ty then
        local proj_dist = ((tx - proj.start_x) * proj.dir_x) + ((ty - proj.start_y) * proj.dir_y)
        if proj_dist >= 0 and proj_dist <= proj.range then
            impact_x = proj.start_x + proj.dir_x * proj_dist
            impact_y = proj.start_y + proj.dir_y * proj_dist
        end
    end

    trigger_impact(proj, impact_x, impact_y, target_id)
    destroy_projectile(proj.id)
    return true
end

--- Processa colisão de projétil contra obstáculo estático (`on_static_collision`).
function ProjectileSystem.on_static_collision(entity_id, obstacle_id, nx, ny)
    local proj = active_projectiles[entity_id]
    if not proj and not ProjectileSystem.is_projectile(entity_id) then
        return false
    end

    if proj then
        proj.resolved = true
        if Loci and Loci.Log then
            local px, py = get_entity_xy(entity_id)
            Loci.Log.info(string.format(
                "[ProjectileSystem] Projétil %s (%s) colidiu com obstáculo %s em (%.1f, %.1f) normal=(%.2f, %.2f)",
                tostring(entity_id), tostring(proj.skill_id), tostring(obstacle_id),
                px or 0, py or 0, tonumber(nx) or 0, tonumber(ny) or 0
            ))
        end
    end

    destroy_projectile(entity_id)
    return true
end

--- Processa colisão de projétil contra os limites do mapa (`on_boundary_collision`).
function ProjectileSystem.on_boundary_collision(entity_id, nx, ny)
    local proj = active_projectiles[entity_id]
    if not proj and not ProjectileSystem.is_projectile(entity_id) then
        return false
    end

    if proj then
        proj.resolved = true
        if Loci and Loci.Log then
            local px, py = get_entity_xy(entity_id)
            Loci.Log.info(string.format(
                "[ProjectileSystem] Projétil %s (%s) atingiu limite do mapa em (%.1f, %.1f) normal=(%.2f, %.2f)",
                tostring(entity_id), tostring(proj.skill_id),
                px or 0, py or 0, tonumber(nx) or 0, tonumber(ny) or 0
            ))
        end
    end

    destroy_projectile(entity_id)
    return true
end

--- Atualiza projéteis a cada tick e processa expiração por alcance máximo / lifetime.
function ProjectileSystem.update_tick(current_tick)
    for i = #projectile_order, 1, -1 do
        local proj_id = projectile_order[i]
        local proj = active_projectiles[proj_id]

        if not proj or proj.resolved then
            table.remove(projectile_order, i)
            if proj then active_projectiles[proj_id] = nil end
        else
            local px, py = get_entity_xy(proj_id)
            if px == nil or py == nil then
                -- Entidade já foi removida pelo motor
                active_projectiles[proj_id] = nil
                table.remove(projectile_order, i)
            else
                local dx = px - proj.start_x
                local dy = py - proj.start_y
                local dist_sq = dx * dx + dy * dy
                local range_sq = (proj.range - 1e-3) * (proj.range - 1e-3)

                if dist_sq >= range_sq or proj.steps_taken >= proj.lifetime_ticks then
                    if proj.detonate_on_max_range then
                        local end_x = proj.start_x + proj.dir_x * proj.range
                        local end_y = proj.start_y + proj.dir_y * proj.range
                        trigger_impact(proj, end_x, end_y, nil)
                    else
                        proj.resolved = true
                    end
                    destroy_projectile(proj_id)
                else
                    proj.steps_taken = proj.steps_taken + 1
                end
            end
        end
    end
end

--- Limpa todos os projéteis rastreados (útil para testes).
function ProjectileSystem.clear()
    active_projectiles = {}
    projectile_order = {}
end

return ProjectileSystem
