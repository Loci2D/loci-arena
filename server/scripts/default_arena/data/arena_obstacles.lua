-- Módulo de Obstáculos da Arena
-- Define os obstáculos estáticos da arena usando a API do servidor loci2d

local ArenaObstacles = {}

-- Definição dos obstáculos da arena
ArenaObstacles.blueprints = {
    -- Paredes horizontais (cobertura tática)
    wall_center_1 = {
        shape = "aabb",
        position = { x = -30, y = -200 },
        dimensions = { width = 60, height = 10 },
        is_solid = true,
        collision_type = "static"
    },
    wall_center_2 = {
        shape = "aabb",
        position = { x = -30, y = 200 },
        dimensions = { width = 60, height = 10 },
        is_solid = true,
        collision_type = "static"
    },

    -- Pilares nos cantos (cobertura)
    pillar_nw = {
        shape = "circle",
        position = { x = -400, y = -400 },
        radius = 30,
        is_solid = true,
        collision_type = "static"
    },
    pillar_ne = {
        shape = "circle",
        position = { x = 400, y = -400 },
        radius = 30,
        is_solid = true,
        collision_type = "static"
    },
    pillar_sw = {
        shape = "circle",
        position = { x = -400, y = 400 },
        radius = 30,
        is_solid = true,
        collision_type = "static"
    },
    pillar_se = {
        shape = "circle",
        position = { x = 400, y = 400 },
        radius = 30,
        is_solid = true,
        collision_type = "static"
    },

    -- Caixa central (destrutível no futuro)
    crate_center = {
        shape = "aabb",
        position = { x = -15, y = -15 },
        dimensions = { width = 30, height = 30 },
        is_solid = true,
        collision_type = "static"
    }
}

-- Tabela para rastrear IDs dos obstáculos criados
ArenaObstacles.created_ids = {}

-- Função para inicializar os obstáculos da arena
function ArenaObstacles.initialize()
    -- Verificar se a API de obstáculos está disponível
    if not Loci.Commands.spawn_static_obstacle then
        if Loci and Loci.Log then
            Loci.Log.info("[ArenaObstacles] API de obstáculos não disponível")
        end
        return false
    end

    -- Criar cada obstáculo
    for name, blueprint in pairs(ArenaObstacles.blueprints) do
        local obstacle_data = {
            blueprint = name,
            position = blueprint.position,
            shape = blueprint.shape,
            is_solid = blueprint.is_solid
        }

        -- Adicionar dimensões específicas por forma
        if blueprint.shape == "aabb" then
            obstacle_data.dimensions = blueprint.dimensions
        elseif blueprint.shape == "circle" then
            obstacle_data.radius = blueprint.radius
        end

        local success, obstacle_id = Loci.Commands.spawn_static_obstacle(obstacle_data)

        if success and obstacle_id then
            ArenaObstacles.created_ids[name] = obstacle_id
            if Loci and Loci.Log then
                Loci.Log.info(string.format("[ArenaObstacles] Obstáculo %s criado (ID: %s)", name, tostring(obstacle_id)))
            end
        else
            if Loci and Loci.Log then
                Loci.Log.info(string.format("[ArenaObstacles] Falha ao criar obstáculo %s", name))
            end
        end
    end

    if Loci and Loci.Log then
        Loci.Log.info(string.format("[ArenaObstacles] %d obstáculos criados com sucesso", #ArenaObstacles.created_ids))
    end

    return true
end

-- Função para limpar todos os obstáculos
function ArenaObstacles.cleanup()
    -- Nota: A API de remoção de obstáculos pode não estar disponível
    -- Esta função é preparada para uso futuro
    if Loci and Loci.Log then
        Loci.Log.info("[ArenaObstacles] Cleanup de obstáculos (remoção não implementada)")
    end
end

return ArenaObstacles
