-- Movement Intent Synchronization & Resync State Machine (Issue #54)
-- Garante que reconexões, ausência temporária da entidade local, controle de grupo
-- (stun/paralisia/morte) e término de dash ressincronizem imediatamente o vetor de movimento.

local MovementSync = {}
MovementSync.__index = MovementSync

function MovementSync.is_entity_incapacitated(ent, cur_tick)
    if not ent then return true end
    cur_tick = tonumber(cur_tick) or 0
    local props = ent.properties
    local dead = ent.is_dead == true
        or ent.is_dead == "true"
        or ent.is_dead == 1
        or ent.is_dead == "1"
        or (props and (props["is_dead"] == true or props["is_dead"] == "true" or props["is_dead"] == 1 or props["is_dead"] == "1"))
    if dead then return true end

    local stunned_until = tonumber(ent.stunned_until or (props and props["stunned_until"])) or 0
    if stunned_until > 0 and cur_tick < stunned_until then
        return true
    end

    local paralyzed_until = tonumber(ent.paralyzed_until or (props and props["paralyzed_until"])) or 0
    if paralyzed_until > 0 and cur_tick < paralyzed_until then
        return true
    end

    return false
end

function MovementSync.is_entity_dashing(ent, cur_tick)
    if not ent then return false end
    cur_tick = tonumber(cur_tick) or 0
    local props = ent.properties
    local dashing_until = tonumber(ent.dashing_until or (props and props["dashing_until"])) or 0
    return dashing_until > 0 and cur_tick < dashing_until
end

function MovementSync.new()
    return setmetatable({
        last_sent_dx = 0,
        last_sent_dy = 0,
        needs_resync = true,
        was_incapacitated = false,
        was_dashing = false,
        last_move_sent_time = 0,
    }, MovementSync)
end

function MovementSync:mark_needs_resync()
    self.needs_resync = true
end

function MovementSync:on_entity_missing()
    self.needs_resync = true
end

function MovementSync:on_connection_lost()
    self.needs_resync = true
end

function MovementSync:on_reconnected()
    self.needs_resync = true
end

-- Avalia estado de controle de grupo, dash e bordas de entrada para decidir se
-- deve emitir loci.send_move(dx, dy). Retorna true quando enviou intenção.
function MovementSync:step(my_entity, dx, dy, cur_tick, now, loci_api)
    if not my_entity then
        self:on_entity_missing()
        return false
    end

    dx = tonumber(dx) or 0
    dy = tonumber(dy) or 0
    now = tonumber(now) or 0

    local incapacitated = MovementSync.is_entity_incapacitated(my_entity, cur_tick)
    if incapacitated then
        self.was_incapacitated = true
        return false
    end

    if self.was_incapacitated then
        self.was_incapacitated = false
        self.needs_resync = true
    end

    local dashing = MovementSync.is_entity_dashing(my_entity, cur_tick)
    if self.was_dashing and not dashing then
        self.needs_resync = true
    end
    self.was_dashing = dashing

    local sdk_has_keepalive = loci_api
        and loci_api.netcode
        and loci_api.netcode.intent_keepalive_interval ~= nil
        and loci_api.netcode.intent_keepalive_interval > 0

    local keepalive_fallback = (not sdk_has_keepalive)
        and (dx ~= 0 or dy ~= 0)
        and ((now - (self.last_move_sent_time or 0)) >= 0.100)

    local changed = (dx ~= self.last_sent_dx) or (dy ~= self.last_sent_dy)

    if self.needs_resync or changed or keepalive_fallback then
        self.last_sent_dx = dx
        self.last_sent_dy = dy
        self.needs_resync = false
        self.last_move_sent_time = now
        if loci_api and loci_api.send_move then
            loci_api.send_move(dx, dy)
        end
        return true
    end

    return false
end

return MovementSync
