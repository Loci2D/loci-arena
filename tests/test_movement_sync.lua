-- Unit tests for Loci Arena MovementSync (Issue #54)
-- Valida ressincronização pós-reconexão, ausência temporária da entidade,
-- controle de grupo (stun/paralisia/morte), término de dash e fallback sem keepalive do SDK.

package.path = "./client/src/?.lua;./src/?.lua;./?.lua;" .. package.path

local MovementSync = require("movement_sync")

local function make_mock_loci(with_keepalive)
    local sent_moves = {}
    local api = {
        netcode = with_keepalive and { intent_keepalive_interval = 0.100 } or {},
        send_move = function(dx, dy)
            table.insert(sent_moves, { dx = dx, dy = dy })
        end,
        sent_moves = sent_moves,
    }
    return api
end

-- 1. Initial spawn forces sync even when idle (0, 0), and avoids duplicate sends afterward
do
    local sync = MovementSync.new()
    local loci = make_mock_loci(true)
    local ent = { id = 1, properties = {} }

    local emitted = sync:step(ent, 0, 0, 10, 1.000, loci)
    assert(emitted == true and #loci.sent_moves == 1, "initial frame must sync input state")
    assert(loci.sent_moves[1].dx == 0 and loci.sent_moves[1].dy == 0, "initial idle sync must be (0,0)")

    emitted = sync:step(ent, 0, 0, 11, 1.016, loci)
    assert(emitted == false and #loci.sent_moves == 1, "steady idle must not spam send_move")
end

-- 2. Watchdog disconnect + reconnect with key HELD DOWN throughout entire outage
do
    local sync = MovementSync.new()
    local loci = make_mock_loci(true)
    local ent = { id = 1, properties = {} }

    -- Player starts holding D (1, 0)
    sync:step(ent, 1, 0, 10, 1.000, loci)
    assert(#loci.sent_moves == 1 and loci.sent_moves[1].dx == 1)

    -- Watchdog fires disconnect -> client temporarily loses my_entity
    sync:on_connection_lost()
    local emitted = sync:step(nil, 1, 0, 15, 5.100, loci)
    assert(emitted == false, "must not send moves while entity is missing")

    -- Reconnect fires and my_entity returns while player STILL holds (1, 0)
    sync:on_reconnected()
    emitted = sync:step({ id = 2, properties = {} }, 1, 0, 20, 5.200, loci)
    assert(emitted == true and #loci.sent_moves == 2, "must immediately resend held (1,0) after reconnect")
    assert(loci.sent_moves[2].dx == 1 and loci.sent_moves[2].dy == 0)
end

-- 3. Despawn / missing entity resets sync even if on_reconnected didn't fire, including release while missing
do
    local sync = MovementSync.new()
    local loci = make_mock_loci(true)
    local ent = { id = 1, properties = {} }

    sync:step(ent, 1, 0, 10, 1.000, loci)
    sync:step(nil, 0, 0, 11, 1.050, loci) -- my_entity briefly missing while user released key

    local emitted = sync:step(ent, 0, 0, 12, 1.100, loci)
    assert(emitted == true and #loci.sent_moves == 2, "returning entity must immediately sync release (0,0)")
    assert(loci.sent_moves[2].dx == 0 and loci.sent_moves[2].dy == 0)
end

-- 4. Crowd control (stun / paralysis / death) suppresses rejected send_move spam and resyncs immediately upon expiry
do
    local sync = MovementSync.new()
    local loci = make_mock_loci(true)
    local ent = { id = 1, properties = { stunned_until = "150" } }

    -- Stunned at tick 100 while pressing D: must NOT spam send_move
    local emitted = sync:step(ent, 1, 0, 100, 10.000, loci)
    assert(emitted == false and #loci.sent_moves == 0, "must not emit move intent during active stun")

    -- Still stunned at tick 120
    emitted = sync:step(ent, 1, 0, 120, 10.500, loci)
    assert(emitted == false and #loci.sent_moves == 0)

    -- Stun expires at tick 150 while holding D -> immediate resync
    emitted = sync:step(ent, 1, 0, 150, 11.000, loci)
    assert(emitted == true and #loci.sent_moves == 1, "must immediately resend held move when stun expires")
    assert(loci.sent_moves[1].dx == 1 and loci.sent_moves[1].dy == 0)

    -- Paralyzed & dead check, plus releasing key while dead
    local dead_ent = { id = 1, is_dead = true, properties = {} }
    emitted = sync:step(dead_ent, 0, 0, 155, 11.100, loci)
    assert(emitted == false and #loci.sent_moves == 1, "must suppress move intent while dead")

    local respawn_ent = { id = 1, is_dead = false, properties = {} }
    emitted = sync:step(respawn_ent, 0, 0, 460, 21.000, loci)
    assert(emitted == true and #loci.sent_moves == 2, "must resync stop (0,0) on respawn after death")
    assert(loci.sent_moves[2].dx == 0 and loci.sent_moves[2].dy == 0)
end

-- 5. Dash expiry resyncs active movement vector (since server skips player_intents update during dash)
do
    local sync = MovementSync.new()
    local loci = make_mock_loci(true)
    local ent = { id = 1, properties = { dashing_until = "210" } }

    -- Start moving right during dash (sent once at edge)
    sync:step(ent, 1, 0, 206, 1.000, loci)
    assert(#loci.sent_moves == 1)

    -- Dash ends at tick 210 while still holding (1, 0) -> resyncs immediately
    local emitted = sync:step(ent, 1, 0, 210, 1.150, loci)
    assert(emitted == true and #loci.sent_moves == 2, "must resync held move immediately when dash finishes")
end

-- 6. Fallback keepalive triggers at 100ms only when SDK lacks intent_keepalive_interval
do
    local sync_old = MovementSync.new()
    local old_sdk = make_mock_loci(false)
    local ent = { id = 1, properties = {} }

    sync_old:step(ent, 1, 0, 10, 1.000, old_sdk)
    assert(#old_sdk.sent_moves == 1)

    sync_old:step(ent, 1, 0, 11, 1.050, old_sdk)
    assert(#old_sdk.sent_moves == 1, "fallback keepalive must wait 100ms")

    sync_old:step(ent, 1, 0, 13, 1.110, old_sdk)
    assert(#old_sdk.sent_moves == 2, "fallback keepalive must fire after 100ms when SDK lacks keepalive")

    local sync_new = MovementSync.new()
    local new_sdk = make_mock_loci(true)
    sync_new:step(ent, 1, 0, 10, 1.000, new_sdk)
    sync_new:step(ent, 1, 0, 14, 1.500, new_sdk)
    assert(#new_sdk.sent_moves == 1, "must avoid duplicate sends when SDK handles keepalive natively")
end

print("All loci-arena MovementSync unit tests passed!")
