-- Loci Arena - Authoritative Game Logic (Lua Server Script)
-- This script runs inside the loci2d server environment.
-- Rules, physics modifications, damage and game mechanics must be handled here.

-- Movement speed in units per tick.
-- At 30 Hz server tick rate: 5.0 units/tick = 150 units (pixels) per second.
local SPEED = 3.0

-- Estado local do jogo (servidor não expõe get_property)
local player_hp = {}           -- HP local de cada jogador
local player_max_hp = {}        -- HP máximo de cada jogador
local player_is_dead = {}       -- Status de morte de cada jogador
local player_kills = {}         -- Kills de cada jogador
local player_deaths = {}        -- Deaths de cada jogador
local PROJECTILE_DAMAGE = 10   -- Dano por acerto

-- Sistema de Dano com detecção de colisão pelo cliente
-- O cliente calcula a colisão e envia o target_id via propriedade temporária
local PROJECTILE_RANGE = 200.0      -- Alcance máximo do tiro
local PROJECTILE_RADIUS = 10.0      -- Margem de erro para colisão
local PROJECTILE_DAMAGE = 10       -- Dano por acerto

-- Função auxiliar para calcular distância
local function distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- Função para causar dano a um alvo específico
local function damage_target(attacker_id, target_id)
    Loci.Log.info("[Damage] Processing attack from entity " .. attacker_id .. " to target " .. target_id)

    -- Verificar se o alvo existe no estado local
    if not player_hp[target_id] then
        Loci.Log.info("[Damage] Target " .. target_id .. " not found")
        return false
    end

    -- Aplicar dano
    local current_hp = player_hp[target_id]
    local new_hp = math.max(0, current_hp - PROJECTILE_DAMAGE)

    player_hp[target_id] = new_hp

    -- Sincronizar com o cliente via set_property
    Loci.Commands.set_property(target_id, "hp", tostring(new_hp))
    Loci.Log.info("[Damage] Entity " .. attacker_id .. " hit entity " .. target_id .. " for " .. PROJECTILE_DAMAGE .. " damage (HP: " .. new_hp .. ")")

    -- Verificar se o jogador morreu
    if new_hp <= 0 and not player_is_dead[target_id] then
        player_is_dead[target_id] = true
        Loci.Commands.set_property(target_id, "is_dead", "true")

        -- Incrementar deaths do alvo
        player_deaths[target_id] = (player_deaths[target_id] or 0) + 1
        Loci.Commands.set_property(target_id, "deaths", tostring(player_deaths[target_id]))

        -- Incrementar kills do atacante
        player_kills[attacker_id] = (player_kills[attacker_id] or 0) + 1
        Loci.Commands.set_property(attacker_id, "kills", tostring(player_kills[attacker_id]))

        Loci.Log.info("[Death] Entity " .. target_id .. " has died! Attacker kills: " .. player_kills[attacker_id] .. " Target deaths: " .. player_deaths[target_id])
    end

    return true
end

function on_player_join(entity_id)
    Loci.Log.info("[Arena] Player joined with entity ID " .. tostring(entity_id))

    -- Initialize entity game properties
    Loci.Commands.set_property(entity_id, "team", "1")
    Loci.Commands.set_property(entity_id, "hp", "100")
    Loci.Commands.set_property(entity_id, "max_hp", "100")
    Loci.Commands.set_property(entity_id, "score", "0")
    Loci.Commands.set_property(entity_id, "is_dead", "false")
    Loci.Commands.set_property(entity_id, "kills", "0")
    Loci.Commands.set_property(entity_id, "deaths", "0")

    -- Initialize local state (server doesn't expose get_property)
    player_hp[entity_id] = 100
    player_max_hp[entity_id] = 100
    player_is_dead[entity_id] = false
    player_kills[entity_id] = 0
    player_deaths[entity_id] = 0
end

function on_move_intent(entity_id, dir_x, dir_y)
    -- Verificar se o jogador está morto
    if player_is_dead[entity_id] then
        return false, "Você está morto"
    end

    -- Normalize movement vector so diagonal movement doesn't provide a speed boost
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if len > 0 then
        dir_x = dir_x / len
        dir_y = dir_y / len
    end

    -- Set server authoritative velocity (displacement per tick)
    Loci.Commands.set_velocity(entity_id, {
        x = dir_x * SPEED,
        y = dir_y * SPEED
    })

    return true
end

function on_action(entity_id, ability_id, aim_x, aim_y)
    Loci.Log.info("[Arena] Action from entity " .. tostring(entity_id) .. " -> Ability: " .. tostring(ability_id))

    -- Verificar se o jogador está morto
    if player_is_dead[entity_id] then
        return false, "Você está morto"
    end

    -- Feature placeholder: Handle skills, spells, dash, attack
    if ability_id == 1 then
        -- Primary attack sem alvo (tiro errou)
        Loci.Log.info("[Arena] Shot missed (no target)")
        return true
    end

    -- Se ability_id > 10000, contém target_id codificado
    if ability_id > 10000 then
        local target_id = ability_id - 10000
        Loci.Log.info("[Arena] Decoded target_id: " .. target_id)

        -- Aplicar dano ao alvo
        if target_id and target_id ~= entity_id then
            local success = damage_target(entity_id, target_id)
            if success then
                return true
            else
                return false, "Falha ao aplicar dano"
            end
        else
            Loci.Log.info("[Arena] Shot missed (invalid target)")
            return true
        end
    end

    return false, "Ability not implemented or on cooldown"
end

function on_player_leave(entity_id)
    Loci.Log.info("[Arena] Player left: " .. tostring(entity_id))
    Loci.Commands.destroy_entity(entity_id)

    -- Clean up local state
    player_hp[entity_id] = nil
    player_max_hp[entity_id] = nil
    player_is_dead[entity_id] = nil
    player_kills[entity_id] = nil
    player_deaths[entity_id] = nil
end
