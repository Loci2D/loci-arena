-- Loci Arena - Authoritative Game Logic (Lua Server Script)
-- This script runs inside the loci2d server environment.
-- Rules, physics modifications, damage and game mechanics must be handled here.

-- Movement speed in units per tick.
-- At 30 Hz server tick rate: 5.0 units/tick = 150 units (pixels) per second.
local SPEED = 3.0

-- ========================================
-- SISTEMA DE ESCUDO (INTEGRADO)
-- ========================================

-- Configurações do Escudo
local SHIELD_CAPACITY_PERCENT = 0.1  -- Capacidade do escudo como porcentagem do HP (0.1 = 10%)
local SHIELD_ABILITY_ID = 2             -- ID da habilidade de escudo

-- Estado local do sistema de escudo
local player_shield_active = {}       -- Se o escudo está ativo
local player_shield_capacity = {}     -- Capacidade restante do escudo

-- Desativar o escudo (definido antes para poder ser chamado por outras funções)
local function shield_deactivate(entity_id)
    player_shield_active[entity_id] = false
    player_shield_capacity[entity_id] = nil

    -- Sincronizar com o cliente
    Loci.Commands.set_property(entity_id, "is_shielded", "false")
    Loci.Commands.set_property(entity_id, "shield_capacity", "0")
end

-- Ativar o escudo para um jogador
local function shield_activate(entity_id)
    -- Se já está ativo, ignorar (cliente gerencia duração)
    if player_shield_active[entity_id] then
        return false, "Escudo já está ativo"
    end

    -- Calcular capacidade do escudo baseada no HP máximo
    local max_hp = player_max_hp[entity_id] or 100
    local shield_capacity = math.floor(max_hp * SHIELD_CAPACITY_PERCENT)

    -- Ativar escudo com capacidade calculada
    player_shield_active[entity_id] = true
    player_shield_capacity[entity_id] = shield_capacity

    -- Sincronizar com o cliente
    Loci.Commands.set_property(entity_id, "is_shielded", "true")
    Loci.Commands.set_property(entity_id, "shield_capacity", tostring(shield_capacity))
    Loci.Commands.set_property(entity_id, "shield_max_capacity", tostring(shield_capacity))

    Loci.Log.info("[Shield] Entity " .. entity_id .. " activated shield with capacity " .. shield_capacity .. " (" .. (SHIELD_CAPACITY_PERCENT * 100) .. "% of max HP)")
    return true, "Escudo ativado"
end

-- Verificar se um jogador está defendendo e absorver dano
local function shield_apply_damage_reduction(entity_id, original_damage)
    if not player_shield_active[entity_id] then
        return original_damage, false  -- Sem escudo
    end

    -- Obter capacidade restante
    local remaining_capacity = player_shield_capacity[entity_id] or 0

    -- Se não tem mais capacidade, desativar
    if remaining_capacity <= 0 then
        shield_deactivate(entity_id)
        return original_damage, false
    end

    -- Calcular quanto dano o escudo absorve
    local absorbed = math.min(remaining_capacity, original_damage)
    local damage_to_player = original_damage - absorbed

    -- Atualizar capacidade restante
    player_shield_capacity[entity_id] = remaining_capacity - absorbed

    -- Sincronizar nova capacidade com o cliente
    Loci.Commands.set_property(entity_id, "shield_capacity", tostring(player_shield_capacity[entity_id]))

    -- Se a capacidade chegou a 0, desativar escudo
    if player_shield_capacity[entity_id] <= 0 then
        shield_deactivate(entity_id)
    end

    return damage_to_player, true
end

-- Limpar estado de um jogador (quando sai do jogo)
local function shield_cleanup(entity_id)
    player_shield_active[entity_id] = nil
    player_shield_capacity[entity_id] = nil
end

-- ========================================
-- FIM DO SISTEMA DE ESCUDO
-- ========================================

-- Estado local do jogo (servidor não expõe get_property)
local player_hp = {}           -- HP local de cada jogador
local player_max_hp = {}        -- HP máximo de cada jogador
local player_is_dead = {}       -- Status de morte de cada jogador
local player_kills = {}         -- Kills de cada jogador
local player_deaths = {}        -- Deaths de cada jogador
local PROJECTILE_DAMAGE = 10   -- Dano por acerto

-- Sistema de Respawn - Movido para o cliente (servidor não fornece dt confiável)
local dead_players = {}  -- Lista de jogadores mortos

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

    -- Aplicar redução de dano se o alvo estiver com escudo
    local damage = PROJECTILE_DAMAGE
    local damage_reduced = false
    damage, damage_reduced = shield_apply_damage_reduction(target_id, damage)

    -- Aplicar dano
    local current_hp = player_hp[target_id]
    local new_hp = math.max(0, current_hp - damage)

    player_hp[target_id] = new_hp

    -- Sincronizar com o cliente via set_property
    Loci.Commands.set_property(target_id, "hp", tostring(new_hp))
    Loci.Log.info("[Damage] Entity " .. attacker_id .. " hit entity " .. target_id .. " for " .. damage .. " damage (HP: " .. new_hp .. ")")

    -- Verificar se o jogador morreu
    if new_hp <= 0 and not player_is_dead[target_id] then
        player_is_dead[target_id] = true
        Loci.Commands.set_property(target_id, "is_dead", "true")

        -- Adicionar à lista de mortos para respawn
        dead_players[target_id] = true

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

    -- ability_id = 1 é pedido de respawn (processar mesmo se morto)
    if ability_id == 1 then
        if player_is_dead[entity_id] then
            -- Reviver o jogador
            player_hp[entity_id] = 100
            player_is_dead[entity_id] = false
            dead_players[entity_id] = nil

            Loci.Commands.set_property(entity_id, "hp", "100")
            Loci.Commands.set_property(entity_id, "is_dead", "false")

            -- Limpar estado do escudo ao respawnar
            shield_deactivate(entity_id)

            Loci.Log.info("[Respawn] Entity " .. entity_id .. " requested respawn and was revived!")
            return true
        else
            -- Jogador não está morto, isso é um tiro normal
            Loci.Log.info("[Arena] Shot missed (no target)")
            return true
        end
    end

    -- ability_id = 2 é ativação do escudo
    if ability_id == SHIELD_ABILITY_ID then
        if player_is_dead[entity_id] then
            return false, "Você está morto"
        end

        local success, msg = shield_activate(entity_id)
        if success then
            return true
        else
            return false, msg
        end
    end

    -- ability_id = 1002 é desativação do escudo (expirou por tempo no cliente)
    if ability_id == SHIELD_ABILITY_ID + 1000 then
        if player_shield_active[entity_id] then
            shield_deactivate(entity_id)
            return true
        end
        return true  -- Já estava desativado, ok
    end

    -- Verificar se o jogador está morto (para ações normais)
    if player_is_dead[entity_id] then
        return false, "Você está morto"
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
    dead_players[entity_id] = nil

    -- Clean up shield state
    shield_cleanup(entity_id)
end

-- Sistema de Respawn - Processa a cada tick (se o servidor suportar on_tick)
-- REMOVIDO: O servidor não fornece delta time confiável. Respawn movido para o cliente.
-- function on_tick(dt) ... end
