local CombatSystem = {}

-- Estado transitório por tick para garantir visibilidade imediata antes do flush do CommandBuffer
local pending_slow_state = {} -- [entity_id] = { tick = number, expected_prop_until = string|nil, slowed_until = number, slow_multiplier = number }
local pending_velocity = {}   -- [entity_id] = { tick = number, expected_vx = number, expected_vy = number, vx = number, vy = number }

local function read_raw_velocity_xy(entity_id)
    if not (Loci and Loci.get_velocity and entity_id) then
        return 0, 0, false
    end
    local vel = Loci.get_velocity(entity_id)
    if not vel then
        return 0, 0, false
    end
    if type(vel.x_float) == "function" then
        return vel:x_float(), vel:y_float(), true
    end
    return tonumber(vel.x) or 0, tonumber(vel.y) or 0, true
end

local function get_velocity_xy(entity_id, current_tick)
    local raw_vx, raw_vy, has_vel = read_raw_velocity_xy(entity_id)
    if not has_vel then
        return 0, 0, false
    end
    local pv = pending_velocity[entity_id]
    if pv and pv.tick == (tonumber(current_tick) or 0) then
        if math.abs(raw_vx - pv.expected_vx) < 1e-6 and math.abs(raw_vy - pv.expected_vy) < 1e-6 then
            return pv.vx, pv.vy, true
        end
    end
    return raw_vx, raw_vy, true
end

function CombatSystem.set_velocity_tracked(entity_id, vx, vy, current_tick)
    local raw_vx, raw_vy, has_vel = read_raw_velocity_xy(entity_id)
    Loci.Commands.set_velocity(entity_id, { x = vx, y = vy })
    local after_vx, after_vy, has_after = read_raw_velocity_xy(entity_id)
    if has_vel and has_after and (math.abs(after_vx - vx) > 1e-6 or math.abs(after_vy - vy) > 1e-6) then
        pending_velocity[entity_id] = {
            tick = tonumber(current_tick) or 0,
            expected_vx = after_vx,
            expected_vy = after_vy,
            vx = vx,
            vy = vy,
        }
    else
        pending_velocity[entity_id] = nil
    end
end

local function resolve_current_tick(current_tick)
    if current_tick ~= nil then
        return tonumber(current_tick) or 0
    end
    local cf = package.loaded["systems.character_factory"]
    if cf and type(cf.get_current_tick) == "function" then
        return tonumber(cf.get_current_tick()) or 0
    end
    return 0
end

-- Constantes baseadas na documentação (Single Source of Truth)
CombatSystem.CONST = {
    DEFENSE_K = 100,               -- Constante para calcular redução de dano (K)
    CRIT_CHANCE_BASE = 0.10,       -- 10% de chance base de crítico
    CRIT_MULTIPLIER = 2.25,        -- Dano x 2.25 quando crita
    FRAGILITY_MULT = 1.30,         -- 30% a mais de dano se o alvo for "Frágil"
    VISUAL_SCALE = 8               -- Escala do cliente (8 pixels = 1 unidade/metro no mundo)
}

-- Tipos de Dano Suportados
CombatSystem.DamageType = {
    PHYSICAL = 1,
    MAGICAL = 2,
    TRUE = 3 -- Ignora defesas
}

-- Helper para inicializar os atributos num player
function CombatSystem.init_entity(entity_id, max_hp, phys_def, mag_def)
    Loci.Commands.set_property(entity_id, "max_hp", tostring(max_hp))
    Loci.Commands.set_property(entity_id, "hp", tostring(max_hp))
    Loci.Commands.set_property(entity_id, "phys_def", tostring(phys_def))
    Loci.Commands.set_property(entity_id, "mag_def", tostring(mag_def))
    
    -- Status effects (0 = off, 1 = on)
    Loci.Commands.set_property(entity_id, "fragile", "0")
    Loci.Commands.set_property(entity_id, "shield", "0")
    Loci.Commands.set_property(entity_id, "shield_active", "0")
    Loci.Commands.set_property(entity_id, "shield_end_tick", "0")
    Loci.Commands.set_property(entity_id, "slowed_until", "0")
    Loci.Commands.set_property(entity_id, "slow_multiplier", "1")
    pending_slow_state[entity_id] = nil
    pending_velocity[entity_id] = nil
    
    Loci.Log.info("[Combat] Atributos base definidos para " .. tostring(entity_id))
end

-- Retorna (is_slowed, slow_multiplier, slowed_until) considerando estado pendente do mesmo tick
function CombatSystem.get_slow_state(entity_id, current_tick)
    local cur = resolve_current_tick(current_tick)
    local raw_until_prop = Loci and Loci.get_entity_property and Loci.get_entity_property(entity_id, "slowed_until")
    local pending = pending_slow_state[entity_id]
    local slowed_until, slow_mult

    if pending and pending.tick == cur and raw_until_prop == pending.expected_prop_until then
        slowed_until = pending.slowed_until
        slow_mult = pending.slow_multiplier
    else
        slowed_until = tonumber(raw_until_prop) or 0
        slow_mult = tonumber(Loci and Loci.get_entity_property and Loci.get_entity_property(entity_id, "slow_multiplier")) or 1.0
    end

    if slowed_until > cur and slow_mult >= 0.0 and slow_mult < 1.0 then
        return true, slow_mult, slowed_until
    end
    return false, 1.0, 0
end

-- Retorna o multiplicador efetivo de velocidade (1.0 se não estiver em slow)
function CombatSystem.get_slow_multiplier(entity_id, current_tick)
    local _, mult = CombatSystem.get_slow_state(entity_id, current_tick)
    return mult
end

-- Aplica desaceleração (Slow CC) e reduz imediatamente a velocidade caso a entidade esteja em movimento
function CombatSystem.apply_slow(entity_id, slow_multiplier, duration_ticks, current_tick)
    if not entity_id then return false end

    local is_dead = Loci and Loci.get_entity_property and Loci.get_entity_property(entity_id, "is_dead")
    if is_dead == "true" or is_dead == true or is_dead == "1" or is_dead == 1 then
        return false
    end
    local hp_raw = Loci and Loci.get_entity_property and Loci.get_entity_property(entity_id, "hp")
    if hp_raw ~= nil and (tonumber(hp_raw) or 0) <= 0 then
        return false
    end

    local mult = tonumber(slow_multiplier)
    if mult == nil then mult = 0.5 end
    mult = math.max(0.0, math.min(1.0, mult))

    local dur = tonumber(duration_ticks) or 0
    if dur <= 0 or mult >= 1.0 then
        return false
    end

    local cur_tick = resolve_current_tick(current_tick)
    local was_slowed, prev_mult, prev_until = CombatSystem.get_slow_state(entity_id, cur_tick)

    local effective_mult = was_slowed and math.min(mult, prev_mult) or mult
    local effective_until = math.max(prev_until, cur_tick + dur)

    Loci.Commands.set_property(entity_id, "slow_multiplier", tostring(effective_mult))
    Loci.Commands.set_property(entity_id, "slowed_until", tostring(effective_until))

    local after_prop_until = Loci and Loci.get_entity_property and Loci.get_entity_property(entity_id, "slowed_until")
    if after_prop_until ~= tostring(effective_until) then
        pending_slow_state[entity_id] = {
            tick = cur_tick,
            expected_prop_until = after_prop_until,
            slowed_until = effective_until,
            slow_multiplier = effective_mult,
        }
    else
        pending_slow_state[entity_id] = nil
    end

    -- Resposta imediata a input contínuo: se a entidade já estiver em movimento retilíneo
    -- (e não em dash/CC incapacitante), ajusta a velocidade instantaneamente neste mesmo tick.
    local dashing_until = tonumber(Loci.get_entity_property and Loci.get_entity_property(entity_id, "dashing_until")) or 0
    local stunned_until = tonumber(Loci.get_entity_property and Loci.get_entity_property(entity_id, "stunned_until")) or 0
    local paralyzed_until = tonumber(Loci.get_entity_property and Loci.get_entity_property(entity_id, "paralyzed_until")) or 0
    local casting_until = tonumber(Loci.get_entity_property and Loci.get_entity_property(entity_id, "casting_until")) or 0

    if cur_tick >= dashing_until and cur_tick >= stunned_until and cur_tick >= paralyzed_until and cur_tick >= casting_until then
        local vx, vy, has_vel = get_velocity_xy(entity_id, cur_tick)
        if has_vel and (vx ~= 0 or vy ~= 0) then
            local base_divisor = (was_slowed and prev_mult > 0) and prev_mult or 1.0
            local vel_scale = effective_mult / base_divisor
            if math.abs(vel_scale - 1.0) > 1e-6 then
                CombatSystem.set_velocity_tracked(entity_id, vx * vel_scale, vy * vel_scale, cur_tick)
            end
        end
    end

    return true
end

-- Limpa o estado de lentidão de uma entidade
function CombatSystem.clear_slow(entity_id, current_tick)
    if not entity_id then return end
    if Loci and Loci.Commands and Loci.Commands.set_property then
        Loci.Commands.set_property(entity_id, "slowed_until", "0")
        Loci.Commands.set_property(entity_id, "slow_multiplier", "1")
    end
    local after_prop_until = Loci and Loci.get_entity_property and Loci.get_entity_property(entity_id, "slowed_until")
    if current_tick ~= nil and after_prop_until ~= nil and after_prop_until ~= "0" then
        pending_slow_state[entity_id] = {
            tick = resolve_current_tick(current_tick),
            expected_prop_until = after_prop_until,
            slowed_until = 0,
            slow_multiplier = 1.0,
        }
    else
        pending_slow_state[entity_id] = nil
    end
end

-- Helper para aplicar escudo temporário em uma entidade
function CombatSystem.apply_shield(entity_id, amount, duration_ticks, current_tick)
    current_tick = current_tick or 0
    local end_tick = current_tick + (duration_ticks or 0)
    Loci.Commands.set_property(entity_id, "shield", tostring(amount))
    Loci.Commands.set_property(entity_id, "shield_active", "1")
    Loci.Commands.set_property(entity_id, "shield_end_tick", tostring(end_tick))
    if Loci and Loci.Log then
        Loci.Log.info(string.format("[Combat] Escudo de %d aplicado a %s ate tick %d",
            amount, tostring(entity_id), end_tick))
    end
end

-- Helper para limpar/remover escudo de uma entidade
function CombatSystem.clear_shield(entity_id)
    Loci.Commands.set_property(entity_id, "shield", "0")
    Loci.Commands.set_property(entity_id, "shield_active", "0")
    Loci.Commands.set_property(entity_id, "shield_end_tick", "0")
end

-- Calcula a Redução de Dano (%) usando a fórmula Diminishing Returns
function CombatSystem.calculate_mitigation(defense)
    if defense < 0 then defense = 0 end
    return defense / (defense + CombatSystem.CONST.DEFENSE_K)
end

-- Processa um ataque passando pelas regras do jogo
-- Retorna uma tabela com o resultado do ataque
function CombatSystem.process_hit(attacker_id, target_id, base_damage, dmg_type, force_crit)
    
    -- 1. Obter HP atual
    local target_hp = tonumber(Loci.get_entity_property(target_id, "hp"))
    if not target_hp or target_hp <= 0 then 
        return { success = false, reason = "target_dead" } 
    end

    -- 2. Identificar qual Defesa usar
    local def = 0
    if dmg_type == CombatSystem.DamageType.PHYSICAL then
        def = tonumber(Loci.get_entity_property(target_id, "phys_def")) or 0
    elseif dmg_type == CombatSystem.DamageType.MAGICAL then
        def = tonumber(Loci.get_entity_property(target_id, "mag_def")) or 0
    end
    -- Dano Verdadeiro (TRUE) fica com def = 0

    -- 3. Calcular Dano Mitigado
    local mitigation = CombatSystem.calculate_mitigation(def)
    local final_damage = base_damage * (1 - mitigation)

    -- 4. Processar Crítico (RNG)
    local is_crit = force_crit or (math.random() <= CombatSystem.CONST.CRIT_CHANCE_BASE)
    if is_crit then
        final_damage = final_damage * CombatSystem.CONST.CRIT_MULTIPLIER
        
        -- TODO: Implementar lógica de Sangramento se for Físico ou Queimadura se for Mágico
    end

    -- 5. Processar Modificadores e Debuffs (ex: Fragilidade)
    local is_fragile = Loci.get_entity_property(target_id, "fragile") == "1"
    if is_fragile then
        final_damage = final_damage * CombatSystem.CONST.FRAGILITY_MULT
    end

    -- 5.5. Verificar Escudo (absorve dano mitigado/final antes de reduzir o HP)
    local shield = tonumber(Loci.get_entity_property(target_id, "shield")) or 0
    local shield_absorbed = 0
    if shield > 0 and final_damage > 0 then
        shield_absorbed = math.min(shield, final_damage)
        final_damage = final_damage - shield_absorbed
        shield = shield - shield_absorbed
        Loci.Commands.set_property(target_id, "shield", tostring(shield))
        
        if shield <= 0 then
            shield = 0
            Loci.Commands.set_property(target_id, "shield", "0")
            Loci.Commands.set_property(target_id, "shield_active", "0")
            Loci.Commands.set_property(target_id, "shield_end_tick", "0")
        end
        
        if Loci and Loci.Log then
            Loci.Log.info(string.format("[Combat] Escudo absorveu %d de dano para %s (Restante no escudo: %d)", 
                math.floor(shield_absorbed), tostring(target_id), math.floor(shield)))
        end
    end

    -- 6. Aplicar Dano no HP (mantendo no mínimo 0)
    target_hp = math.max(0, target_hp - final_damage)
    Loci.Commands.set_property(target_id, "hp", tostring(target_hp))

    if Loci and Loci.Log then
        Loci.Log.info(string.format("[Combat] Dano %d (Mitig: %.1f%%, Escudo: %d) causado em %s", 
            math.floor(final_damage), mitigation * 100, math.floor(shield_absorbed), tostring(target_id)))
    end

    -- 7. Checar Morte
    if target_hp == 0 then
        local RespawnSystem = require("respawn_system")
        RespawnSystem.mark_dead(target_id)
        
        -- Atualizar KDA
        local current_deaths = tonumber(Loci.get_entity_property(target_id, "deaths")) or 0
        Loci.Commands.set_property(target_id, "deaths", tostring(current_deaths + 1))
        
        if attacker_id and attacker_id ~= target_id then
            local current_kills = tonumber(Loci.get_entity_property(attacker_id, "kills")) or 0
            Loci.Commands.set_property(attacker_id, "kills", tostring(current_kills + 1))
        end

        Loci.Log.info("[Combat] " .. tostring(target_id) .. " foi eliminado por " .. tostring(attacker_id))
        
        local CharacterFactory = require("systems.character_factory")
        CharacterFactory.on_entity_die(target_id)
    end

    return {
        success = true,
        damage_dealt = final_damage,
        shield_absorbed = shield_absorbed,
        was_critical = is_crit,
        lethal = (target_hp == 0)
    }
end

return CombatSystem
