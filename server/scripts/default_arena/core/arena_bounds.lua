-- Arena Bounds & Collision Projection Utilities
-- Single source of truth para limites da arena e projeção de velocidade nas bordas.
-- Espelha MapBounds::default_arena() [-500, +500] com colisor circular de raio 2.0 -> [-498, +498].

local ArenaBounds = {}

ArenaBounds.ARENA_MIN = -500.0
ArenaBounds.ARENA_MAX = 500.0
ArenaBounds.PLAYER_COLLIDER_RADIUS = 2.0
ArenaBounds.SAFE_MIN = ArenaBounds.ARENA_MIN + ArenaBounds.PLAYER_COLLIDER_RADIUS
ArenaBounds.SAFE_MAX = ArenaBounds.ARENA_MAX - ArenaBounds.PLAYER_COLLIDER_RADIUS

--- Clampa coordenadas (x, y) ao retângulo seguro para o centro do jogador [-498, +498].
function ArenaBounds.clamp_xy(x, y)
    local cx = math.max(ArenaBounds.SAFE_MIN, math.min(ArenaBounds.SAFE_MAX, x or 0))
    local cy = math.max(ArenaBounds.SAFE_MIN, math.min(ArenaBounds.SAFE_MAX, y or 0))
    return cx, cy
end

--- Projeta o vetor de velocidade (vx, vy) a partir de (x, y) contra os limites seguros da arena.
--- Zera ou limita apenas o componente que ultrapassaria [SAFE_MIN, SAFE_MAX], preservando deslize tangencial.
function ArenaBounds.project_velocity(x, y, vx, vy)
    local px = x or 0
    local py = y or 0
    local out_vx = vx or 0
    local out_vy = vy or 0

    if out_vx > 0 and px + out_vx > ArenaBounds.SAFE_MAX then
        out_vx = math.max(0.0, ArenaBounds.SAFE_MAX - px)
    elseif out_vx < 0 and px + out_vx < ArenaBounds.SAFE_MIN then
        out_vx = math.min(0.0, ArenaBounds.SAFE_MIN - px)
    end

    if out_vy > 0 and py + out_vy > ArenaBounds.SAFE_MAX then
        out_vy = math.max(0.0, ArenaBounds.SAFE_MAX - py)
    elseif out_vy < 0 and py + out_vy < ArenaBounds.SAFE_MIN then
        out_vy = math.min(0.0, ArenaBounds.SAFE_MIN - py)
    end

    return out_vx, out_vy
end

--- Obtém a velocidade atual da entidade no estado autoritativo do servidor (ou 0, 0 se indisponível).
function ArenaBounds.get_current_velocity(entity_id)
    if not (Loci and Loci.get_velocity and entity_id) then
        return 0, 0
    end

    local vel = Loci.get_velocity(entity_id)
    if not vel then
        return 0, 0
    end

    if type(vel.x_float) == "function" then
        return vel:x_float(), vel:y_float()
    end

    return vel.x or 0, vel.y or 0
end

--- Estima a posição da entidade após a integração física do tick atual.
--- Necessário em callbacks de tick (`on_tick`), pois o `CommandBuffer` só aplica novos
--- `set_velocity` no fim do tick enquanto a física integra a velocidade já ativa.
function ArenaBounds.predict_post_step_xy(entity_id, x, y, cur_vx, cur_vy)
    if cur_vx == nil or cur_vy == nil then
        cur_vx, cur_vy = ArenaBounds.get_current_velocity(entity_id)
    end
    return ArenaBounds.clamp_xy((x or 0) + (cur_vx or 0), (y or 0) + (cur_vy or 0))
end

return ArenaBounds
