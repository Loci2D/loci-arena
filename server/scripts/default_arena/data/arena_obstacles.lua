-- arena_obstacles.lua
-- Definição e criação de obstáculos estáticos da arena
-- Baseado na especificação do card #74 e API do card #82

local ArenaObstacles = {}

-- Configuração visual e física da arena
ArenaObstacles.ARENA_SIZE = 1000  -- Arena de [-500, +500]
ArenaObstacles.VISUAL_SCALE = 8   -- 8 pixels = 1 unidade no mundo

-- Lista de obstáculos a serem criados
-- Cada obstáculo tem:
--   blueprint: tipo de obstáculo (wall, pillar, crate, etc.)
--   shape: circle ou aabb
--   x, y: posição central
--   width, height: dimensões (para AABB)
--   radius: raio (para circle)
--   is_solid: true para colisão física, false para trigger zone
--   collision_type: solid ou trigger
ArenaObstacles.obstacle_blueprints = {
    -- Paredes centrais (para tática)
    {
        blueprint = "wall_center_1",
        shape = "aabb",
        x = 0,
        y = -200,
        width = 60,
        height = 20,
        is_solid = true,
        collision_type = "solid"
    },
    {
        blueprint = "wall_center_2",
        shape = "aabb",
        x = 0,
        y = 200,
        width = 60,
        height = 20,
        is_solid = true,
        collision_type = "solid"
    },
    -- Pilares nos cantos (para cobertura)
    {
        blueprint = "pillar_nw",
        shape = "circle",
        x = -350,
        y = -350,
        radius = 25,
        is_solid = true,
        collision_type = "solid"
    },
    {
        blueprint = "pillar_ne",
        shape = "circle",
        x = 350,
        y = -350,
        radius = 25,
        is_solid = true,
        collision_type = "solid"
    },
    {
        blueprint = "pillar_sw",
        shape = "circle",
        x = -350,
        y = 350,
        radius = 25,
        is_solid = true,
        collision_type = "solid"
    },
    {
        blueprint = "pillar_se",
        shape = "circle",
        x = 350,
        y = 350,
        radius = 25,
        is_solid = true,
        collision_type = "solid"
    },
    -- Caixas destrutíveis (apenas um exemplo inicial)
    {
        blueprint = "crate_center",
        shape = "aabb",
        x = 0,
        y = 0,
        width = 30,
        height = 30,
        is_solid = true,
        collision_type = "solid"
    }
}

-- Função para criar todos os obstáculos no servidor
function ArenaObstacles.spawn_all()
    if not (Loci and Loci.Commands and Loci.Commands.spawn_static_obstacle) then
        print("[ArenaObstacles] API de obstáculos não disponível")
        return false
    end

    local spawned_count = 0
    for _, blueprint in ipairs(ArenaObstacles.obstacle_blueprints) do
        local success, obstacle_id = pcall(function()
            if blueprint.shape == "circle" then
                return Loci.Commands.spawn_static_obstacle({
                    blueprint = blueprint.blueprint,
                    shape = "circle",
                    position = { x = blueprint.x, y = blueprint.y },
                    radius = blueprint.radius,
                    is_solid = blueprint.is_solid,
                    collision_type = blueprint.collision_type
                })
            else
                return Loci.Commands.spawn_static_obstacle({
                    blueprint = blueprint.blueprint,
                    shape = "aabb",
                    position = { x = blueprint.x, y = blueprint.y },
                    width = blueprint.width,
                    height = blueprint.height,
                    is_solid = blueprint.is_solid,
                    collision_type = blueprint.collision_type
                })
            end
        end)

        if success and obstacle_id then
            spawned_count = spawned_count + 1
            print(string.format("[ArenaObstacles] Obstáculo %s criado (ID: %s)", blueprint.blueprint, tostring(obstacle_id)))
        else
            print(string.format("[ArenaObstacles] Falha ao criar obstáculo %s", blueprint.blueprint))
        end
    end

    print(string.format("[ArenaObstacles] %d obstáculos criados com sucesso", spawned_count))
    return spawned_count > 0
end

-- Função para remover todos os obstáculos (útil para reset)
function ArenaObstacles.remove_all()
    if not (Loci and Loci.Commands and Loci.Commands.destroy_static_obstacle) then
        print("[ArenaObstacles] API de remoção de obstáculos não disponível")
        return false
    end

    -- Nota: Isso requer rastreamento dos IDs dos obstáculos criados
    -- Para implementação completa, seria necessário armazenar os IDs
    print("[ArenaObstacles] Remoção de obstáculos ainda não implementada")
    return false
end

return ArenaObstacles
