-- Slow Hazard Zone (Área de Teste de Slow CC)
-- Define o retângulo de coordenadas (20, 20), (30, 20), (20, 30), (30, 30) -> [20, 30] x [20, 30].

local CombatSystem = require("core.combat_system")

local SlowZone = {}

SlowZone.MIN_X = 20.0
SlowZone.MAX_X = 30.0
SlowZone.MIN_Y = 20.0
SlowZone.MAX_Y = 30.0

SlowZone.SLOW_MULTIPLIER = 0.5      -- 50% de desaceleração
SlowZone.SLOW_DURATION_TICKS = 60   -- 2.0s a 30 Hz (mantém ativo na área e expira 2s após sair)

function SlowZone.contains(x, y)
    if x == nil or y == nil then
        return false
    end
    return x >= SlowZone.MIN_X and x <= SlowZone.MAX_X
       and y >= SlowZone.MIN_Y and y <= SlowZone.MAX_Y
end

function SlowZone.process_entity(entity_id, px, py, post_x, post_y, current_tick)
    if SlowZone.contains(px, py) or SlowZone.contains(post_x, post_y) then
        return CombatSystem.apply_slow(
            entity_id,
            SlowZone.SLOW_MULTIPLIER,
            SlowZone.SLOW_DURATION_TICKS,
            current_tick
        )
    end
    return false
end

return SlowZone
