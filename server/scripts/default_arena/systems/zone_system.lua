-- Zone System (Authoritative Server)
-- Gerencia zonas de efeito no tempo (ex.: Santuário Sagrado do Cleric).
-- Cada zona registra um callback `on_tick(zone, entity_ids, tick)` disparado a cada
-- `tick_interval` ticks enquanto a zona estiver ativa, recebendo os ids das entidades
-- filtradas por time/raio no momento da pulsação.

local CharacterFactory = require("systems.character_factory")
local TeamUtils = require("core.team_utils")

local ZoneSystem = {}

local active_zones = {}
local zone_order = {}
local next_zone_id = 1

--- Spawna uma zona de efeito.
-- params:
--   x, y            : centro da zona (unidades do mundo)
--   radius          : raio da zona
--   team            : time aliado da zona (string)
--   affects         : "allies" | "enemies" | "all" (default "allies")
--   duration_ticks  : duração total da zona
--   tick_interval   : intervalo entre pulsos (default 30 = 1s)
--   first_delay     : ticks até o primeiro pulso (default = tick_interval)
--   on_tick         : function(zone, entity_ids, tick)
--   on_expire       : function(zone) opcional, chamado na expiração
-- Retorna o id da zona criada.
function ZoneSystem.spawn_zone(params)
    assert(type(params) == "table", "ZoneSystem.spawn_zone expects a params table")

    local current_tick = CharacterFactory.get_current_tick()
    local interval = tonumber(params.tick_interval) or 30
    local zone = {
        id = next_zone_id,
        x = tonumber(params.x) or 0,
        y = tonumber(params.y) or 0,
        radius = tonumber(params.radius) or 0,
        team = tostring(params.team or "1"),
        affects = params.affects or "allies",
        duration_ticks = tonumber(params.duration_ticks) or 0,
        interval = interval,
        next_tick = current_tick + (tonumber(params.first_delay) or interval),
        end_tick = current_tick + (tonumber(params.duration_ticks) or 0),
        on_tick = params.on_tick,
        on_expire = params.on_expire,
    }
    next_zone_id = next_zone_id + 1

    active_zones[zone.id] = zone
    table.insert(zone_order, zone.id)
    return zone.id
end

local function collect_zone_targets(zone)
    local nearby = (Loci.get_entities_in_radius
        and Loci.get_entities_in_radius({ x = zone.x, y = zone.y }, zone.radius)) or {}

    local ids = {}
    for _, id in ipairs(nearby) do
        if not TeamUtils.is_entity_dead(id) then
            local include = false
            if zone.affects == "all" then
                include = true
            else
                local team = Loci.get_entity_property(id, "team")
                local same_team = team ~= nil and tostring(team) == zone.team
                include = (zone.affects == "enemies") and not same_team or (zone.affects ~= "enemies") and same_team
            end
            if include then
                table.insert(ids, id)
            end
        end
    end
    return ids
end

function ZoneSystem.update_tick(current_tick)
    for i = #zone_order, 1, -1 do
        local zone_id = zone_order[i]
        local zone = active_zones[zone_id]

        if not zone then
            table.remove(zone_order, i)
        elseif current_tick >= zone.end_tick then
            if type(zone.on_expire) == "function" then
                zone.on_expire(zone)
            end
            active_zones[zone_id] = nil
            table.remove(zone_order, i)
        elseif type(zone.on_tick) == "function" and current_tick >= zone.next_tick then
            local ids = collect_zone_targets(zone)
            zone.on_tick(zone, ids, current_tick)
            zone.next_tick = current_tick + zone.interval
        end
    end
end

--- Quantidade de zonas ativas (útil para testes).
function ZoneSystem.get_active_count()
    return #zone_order
end

--- Limpa todas as zonas (útil para testes).
function ZoneSystem.clear()
    active_zones = {}
    zone_order = {}
end

return ZoneSystem
