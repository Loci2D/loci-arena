-- Team Utils (Authoritative Server)
-- Helpers compartilhados para habilidades de suporte: seleção de aliados,
-- cura direta e verificação de estado de entidades.

local TeamUtils = {}

local function get_coords(pos)
    if not pos then return 0, 0 end
    if type(pos.x_float) == "function" then
        return pos:x_float(), pos:y_float()
    elseif pos.x and pos.y then
        return pos.x, pos.y
    end
    return 0, 0
end

TeamUtils.get_coords = get_coords

--- Normaliza o vetor de mira (aim_x, aim_y) para comprimento 1. Fallback +X se nulo.
function TeamUtils.normalize_aim(aim_x, aim_y)
    local len = math.sqrt((aim_x or 0) ^ 2 + (aim_y or 0) ^ 2)
    if len > 0 then
        return aim_x / len, aim_y / len
    end
    return 1, 0
end

function TeamUtils.get_entity_xy(entity_id)
    if not (Loci and Loci.get_entity_position and entity_id) then
        return nil, nil
    end
    local pos = Loci.get_entity_position(entity_id)
    if not pos then
        return nil, nil
    end
    return get_coords(pos)
end

function TeamUtils.is_entity_dead(entity_id)
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

-- Raio que cobre a arena inteira ([-500, +500]) para enumerar entidades por time
local TEAM_SCAN_RADIUS = 2000.0

local function is_same_team(entity_id, reference_team)
    if not (Loci and Loci.get_entity_property) then return false end
    local team = Loci.get_entity_property(entity_id, "team")
    if team == nil then return false end
    return tostring(team) == tostring(reference_team)
end

local function is_projectile_entity(entity_id)
    if Loci and Loci.get_entity_property then
        local etype = Loci.get_entity_property(entity_id, "entity_type")
        if etype == "projectile" or etype == "Projectile" then
            return true
        end
    end
    if Loci and Loci.get_entity_type then
        local ok, etype = pcall(Loci.get_entity_type, entity_id)
        if ok and (etype == "Projectile" or etype == "projectile") then
            return true
        end
    end
    return false
end

--- Retorna ids de entidades aliadas vivas (mesmo `team` do caster) dentro de
-- `radius` unidades de (cx, cy). `include_self` controla se o próprio caster entra.
function TeamUtils.get_allies(caster_id, cx, cy, radius, include_self)
    local caster_team = Loci.get_entity_property(caster_id, "team")
    local ids = {}
    local nearby = (Loci.get_entities_in_radius and Loci.get_entities_in_radius({ x = cx, y = cy }, radius or TEAM_SCAN_RADIUS)) or {}
    for _, id in ipairs(nearby) do
        if (id == caster_id and include_self) or (id ~= caster_id) then
            if is_same_team(id, caster_team)
                and not is_projectile_entity(id)
                and not TeamUtils.is_entity_dead(id) then
                table.insert(ids, id)
            end
        end
    end
    return ids
end

--- Retorna ids de inimigos vivos dentro de `radius` unidades de (cx, cy).
function TeamUtils.get_enemies(caster_id, cx, cy, radius)
    local caster_team = Loci.get_entity_property(caster_id, "team")
    local ids = {}
    local nearby = (Loci.get_entities_in_radius and Loci.get_entities_in_radius({ x = cx, y = cy }, radius or TEAM_SCAN_RADIUS)) or {}
    for _, id in ipairs(nearby) do
        if id ~= caster_id
            and not is_projectile_entity(id)
            and not TeamUtils.is_entity_dead(id) then
            local team = Loci.get_entity_property(id, "team")
            if team ~= nil and tostring(team) ~= tostring(caster_team) then
                table.insert(ids, id)
            end
        end
    end
    return ids
end

--- Retorna aliados dentro de um cone de mira: o ângulo entre a direção do aliado
-- (a partir do caster) e o vetor de mira deve ter produto escalar >= `cone_dot`.
-- Cada entrada: { id, x, y, dist, dot, hp, max_hp }.
function TeamUtils.get_allies_in_cone(caster_id, aim_x, aim_y, range, cone_dot, include_self)
    local cx, cy = TeamUtils.get_entity_xy(caster_id)
    if not cx then return {} end

    local min_dot = cone_dot or 0.1
    local out = {}
    local allies = TeamUtils.get_allies(caster_id, cx, cy, range, include_self)
    for _, id in ipairs(allies) do
        local x, y = TeamUtils.get_entity_xy(id)
        if x then
            local dx, dy = x - cx, y - cy
            local dist = math.sqrt(dx * dx + dy * dy)
            local dot = 1.0
            if dist > 0.001 then
                dot = (dx / dist) * aim_x + (dy / dist) * aim_y
            end
            if dot >= min_dot then
                table.insert(out, {
                    id = id,
                    x = x,
                    y = y,
                    dist = dist,
                    dot = dot,
                    hp = tonumber(Loci.get_entity_property(id, "hp")) or 0,
                    max_hp = tonumber(Loci.get_entity_property(id, "max_hp")) or 1,
                })
            end
        end
    end
    return out
end

--- Cura direta de HP (sem passar por mitigação). Retorna a quantidade realmente curada.
function TeamUtils.heal(entity_id, amount)
    if not entity_id or (amount or 0) <= 0 then return 0 end
    if TeamUtils.is_entity_dead(entity_id) then return 0 end

    local hp = tonumber(Loci.get_entity_property(entity_id, "hp")) or 0
    local max_hp = tonumber(Loci.get_entity_property(entity_id, "max_hp")) or hp
    if hp >= max_hp then return 0 end

    local healed = math.min(max_hp - hp, amount)
    Loci.Commands.set_property(entity_id, "hp", tostring(hp + healed))
    return healed
end

return TeamUtils
