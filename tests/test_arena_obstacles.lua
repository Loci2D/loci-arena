-- Test: Arena Obstacles
-- Cobertura: inicialização dos obstáculos e validação de configuração

local function run_test()
    print("=== Test: Arena Obstacles ===")

    -- Test 1: Carregar módulo de obstáculos
    print("\n[1/3] Carregando módulo arena_obstacles...")
    local ok, ArenaObstacles = pcall(require, "server.scripts.default_arena.data.arena_obstacles")
    if not ok then
        print("  [FAIL] Não foi possível carregar arena_obstacles.lua")
        return false
    end
    print("  [PASS] Módulo arena_obstacles carregado com sucesso")

    -- Test 2: Validar blueprints de obstáculos
    print("\n[2/3] Validando blueprints de obstáculos...")
    if not ArenaObstacles.blueprints then
        print("  [FAIL] ArenaObstacles.blueprints não existe")
        return false
    end

    local expected_obstacles = {
        "wall_center_1",
        "wall_center_2",
        "pillar_nw",
        "pillar_ne",
        "pillar_sw",
        "pillar_se",
        "crate_center"
    }

    local obstacle_count = 0
    for name, blueprint in pairs(ArenaObstacles.blueprints) do
        obstacle_count = obstacle_count + 1
        if not blueprint.shape then
            print("  [FAIL] Obstáculo " .. name .. " não tem shape definido")
            return false
        end
        if not blueprint.position then
            print("  [FAIL] Obstáculo " .. name .. " não tem position definido")
            return false
        end
        if blueprint.is_solid ~= true then
            print("  [FAIL] Obstáculo " .. name .. " não está marcado como sólido")
            return false
        end
        if blueprint.shape == "aabb" then
            if not blueprint.dimensions or not blueprint.dimensions.width or not blueprint.dimensions.height then
                print("  [FAIL] Obstáculo AABB " .. name .. " não tem dimensions válidos")
                return false
            end
        elseif blueprint.shape == "circle" then
            if not blueprint.radius then
                print("  [FAIL] Obstáculo circle " .. name .. " não tem radius definido")
                return false
            end
        end
    end

    if obstacle_count ~= 7 then
        print("  [FAIL] Expected 7 obstáculos, found " .. obstacle_count)
        return false
    end
    print("  [PASS] Todos os 7 obstáculos têm blueprints válidos")

    -- Test 3: Validar função de inicialização
    print("\n[3/5] Validando função de inicialização...")
    if not ArenaObstacles.initialize then
        print("  [FAIL] ArenaObstacles.initialize não existe")
        return false
    end
    print("  [PASS] Função ArenaObstacles.initialize existe")

    -- Test 4: Validar posições e dimensões para colisão
    print("\n[4/5] Validando posições e dimensões para colisão...")
    local bp = ArenaObstacles.blueprints

    -- Validar paredes horizontais (AABB)
    if bp.wall_center_1.shape ~= "aabb" then
        print("  [FAIL] wall_center_1 deve ser AABB")
        return false
    end
    if bp.wall_center_1.position.y ~= -200 then
        print("  [FAIL] wall_center_1 deve estar em y = -200")
        return false
    end
    if bp.wall_center_1.dimensions.width ~= 60 or bp.wall_center_1.dimensions.height ~= 10 then
        print("  [FAIL] wall_center_1 deve ter width=60, height=10")
        return false
    end

    if bp.wall_center_2.shape ~= "aabb" then
        print("  [FAIL] wall_center_2 deve ser AABB")
        return false
    end
    if bp.wall_center_2.position.y ~= 200 then
        print("  [FAIL] wall_center_2 deve estar em y = 200")
        return false
    end

    -- Validar pilares (circle)
    if bp.pillar_nw.shape ~= "circle" then
        print("  [FAIL] pillar_nw deve ser circle")
        return false
    end
    if bp.pillar_nw.position.x ~= -400 or bp.pillar_nw.position.y ~= -400 then
        print("  [FAIL] pillar_nw deve estar em (-400, -400)")
        return false
    end
    if bp.pillar_nw.radius ~= 30 then
        print("  [FAIL] pillar_nw deve ter radius=30")
        return false
    end

    if bp.pillar_ne.shape ~= "circle" then
        print("  [FAIL] pillar_ne deve ser circle")
        return false
    end
    if bp.pillar_ne.position.x ~= 400 or bp.pillar_ne.position.y ~= -400 then
        print("  [FAIL] pillar_ne deve estar em (400, -400)")
        return false
    end

    if bp.pillar_sw.shape ~= "circle" then
        print("  [FAIL] pillar_sw deve ser circle")
        return false
    end
    if bp.pillar_sw.position.x ~= -400 or bp.pillar_sw.position.y ~= 400 then
        print("  [FAIL] pillar_sw deve estar em (-400, 400)")
        return false
    end

    if bp.pillar_se.shape ~= "circle" then
        print("  [FAIL] pillar_se deve ser circle")
        return false
    end
    if bp.pillar_se.position.x ~= 400 or bp.pillar_se.position.y ~= 400 then
        print("  [FAIL] pillar_se deve estar em (400, 400)")
        return false
    end

    -- Validar caixa central (AABB)
    if bp.crate_center.shape ~= "aabb" then
        print("  [FAIL] crate_center deve ser AABB")
        return false
    end
    if bp.crate_center.position.x ~= -15 or bp.crate_center.position.y ~= -15 then
        print("  [FAIL] crate_center deve estar em (-15, -15)")
        return false
    end
    if bp.crate_center.dimensions.width ~= 30 or bp.crate_center.dimensions.height ~= 30 then
        print("  [FAIL] crate_center deve ter width=30, height=30")
        return false
    end

    print("  [PASS] Todas as posições e dimensões estão corretas para colisão")

    -- Test 5: Validar propriedades de colisão
    print("\n[5/5] Validando propriedades de colisão...")
    for name, blueprint in pairs(bp) do
        if blueprint.is_solid ~= true then
            print("  [FAIL] Obstáculo " .. name .. " não é sólido (is_solid)")
            return false
        end
    end
    print("  [PASS] Todos os obstáculos estão marcados como sólidos")

    print("\n>>> Test: Arena Obstacles - All 5 tests passed! <<<")
    return true
end

return run_test()
