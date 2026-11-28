-- Módulo de Obstáculos da Arena
-- Define os obstáculos estáticos da arena usando a API do servidor loci2d

local ArenaObstacles = {}

-- Definição ordenada dos obstáculos da arena (ordem determinística para VFS/replay)
-- Nota: `position` representa o centro (cx, cy) tanto para AABB quanto para círculo.
ArenaObstacles.obstacle_list = {
    -- Paredes horizontais (cobertura tática)
    {
        name = "wall_center_1",
        shape = "aabb",
        position = { x = 0, y = -200 },
        dimensions = { width = 60, height = 10 },
        is_solid = true,
        collision_type = "solid"
    },
    {
        name = "wall_center_2",
        shape = "aabb",
        position = { x = 0, y = 200 },
        dimensions = { width = 60, height = 10 },
        is_solid = true,
        collision_type = "solid"
    },

    -- Pilares nos cantos (cobertura)
    {
        name = "pillar_nw",
        shape = "circle",
        position = { x = -400, y = -400 },
        radius = 30,
        is_solid = true,
        collision_type = "solid"
    },
    {
        name = "pillar_ne",
        shape = "circle",
        position = { x = 400, y = -400 },
        radius = 30,
        is_solid = true,
        collision_type = "solid"
    },
    {
        name = "pillar_sw",
        shape = "circle",
        position = { x = -400, y = 400 },
        radius = 30,
        is_solid = true,
        collision_type = "solid"
    },
    {
        name = "pillar_se",
        shape = "circle",
        position = { x = 400, y = 400 },
        radius = 30,
        is_solid = true,
        collision_type = "solid"
    },

    -- Caixa tática próxima ao centro (mantém (0, 0) livre para spawn de jogadores)
    {
        name = "crate_center",
        shape = "aabb",
        position = { x = 0, y = -100 },
        dimensions = { width = 30, height = 30 },
        is_solid = true,
        collision_type = "solid"
    }
}

-- Índice por nome para consultas e testes
ArenaObstacles.blueprints = {}
for _, blueprint in ipairs(ArenaObstacles.obstacle_list) do
    ArenaObstacles.blueprints[blueprint.name] = blueprint
end

-- Tabelas para rastrear IDs dos obstáculos criados
ArenaObstacles.created_ids = {}
ArenaObstacles.created_list = {}

-- Função para inicializar os obstáculos da arena
function ArenaObstacles.initialize()
    -- Verificar se a API de obstáculos está disponível
    if not (Loci and Loci.Commands and Loci.Commands.spawn_static_obstacle) then
        if Loci and Loci.Log then
            Loci.Log.info("[ArenaObstacles] API de obstáculos não disponível")
        end
        return false
    end

    ArenaObstacles.created_ids = {}
    ArenaObstacles.created_list = {}
    local count = 0

    -- Criar cada obstáculo em ordem determinística (ipairs é seguro na VM do loci2d)
    for _, blueprint in ipairs(ArenaObstacles.obstacle_list) do
        local name = blueprint.name
        local obstacle_data = {
            blueprint = name,
            position = { x = blueprint.position.x, y = blueprint.position.y },
            shape = blueprint.shape,
            is_solid = blueprint.is_solid,
            collision_type = blueprint.collision_type or "solid"
        }

        -- Nota: AABB exige width e height diretamente na raiz da tabela
        if blueprint.shape == "aabb" then
            obstacle_data.width = blueprint.dimensions.width
            obstacle_data.height = blueprint.dimensions.height
        elseif blueprint.shape == "circle" then
            obstacle_data.radius = blueprint.radius
        end

        local obstacle_id = Loci.Commands.spawn_static_obstacle(obstacle_data)

        if obstacle_id then
            ArenaObstacles.created_ids[name] = obstacle_id
            table.insert(ArenaObstacles.created_list, obstacle_id)
            count = count + 1
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
        Loci.Log.info(string.format("[ArenaObstacles] %d obstáculos criados com sucesso", count))
    end

    return count > 0
end

-- Função para limpar todos os obstáculos criados
function ArenaObstacles.cleanup()
    local destroy_fn = Loci and Loci.Commands and Loci.Commands.destroy_static_obstacle
    local removed = 0

    if destroy_fn then
        for _, obstacle_id in ipairs(ArenaObstacles.created_list) do
            destroy_fn(obstacle_id)
            removed = removed + 1
        end
    end

    ArenaObstacles.created_ids = {}
    ArenaObstacles.created_list = {}

    if Loci and Loci.Log then
        Loci.Log.info(string.format("[ArenaObstacles] Cleanup concluído (%d obstáculos removidos)", removed))
    end
    return removed
end

return ArenaObstacles
