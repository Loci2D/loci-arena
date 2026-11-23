-- Blade Throw Skill Data (Habilidade 4 / Ultimate da Arya)
-- Arremessa a espada na direção visada como um projétil físico real (EntityType::Projectile,
-- is_sensor, velocidade autoritativa e lifetime_ticks — loci2d v0.6.5-rev.6+).
-- A lâmina para ao atingir o primeiro inimigo no caminho (ou parede/borda/alcance máximo)
-- e aplica dano físico e Stun em área no ponto de impacto real do servidor, mas deixa
-- Arya desarmada (impedida de usar habilidades) por 2.0s.
local CombatSystem = require("core.combat_system")

local function get_coords(pos)
    if not pos then return 0, 0 end
    if type(pos.x_float) == "function" then
        return pos:x_float(), pos:y_float()
    elseif pos.x and pos.y then
        return pos.x, pos.y
    end
    return 0, 0
end

local BladeThrow = {
    id = "blade_throw",
    name = "Arremesso de Lâmina",
    description = "Arremessa a espada. Causa dano físico e Stun em área no impacto, mas aplica Desarme na Arya por 2.0s.",
    mana_cost = 45,
    cooldown = 420, -- 14 segundos a 30Hz
    range = 56.0,                   -- unidades do mundo (cabe na tela: +-45 na vertical, +-80 na horizontal)
    damage = 400,
    damage_type = CombatSystem.DamageType.PHYSICAL,
    aoe_radius = 8.0,               -- unidades do mundo (Stun em área no impacto)
    stun_duration_ticks = 36,   -- 1.2 segundos de Stun a 30Hz
    disarm_duration_ticks = 60, -- 2.0 segundos de Desarme a 30Hz
}

-- Parâmetros balísticos da lâmina (unidades do mundo / deslocamento por tick a 30 Hz)
local SPAWN_OFFSET = 2.0   -- a lâmina nasce à frente do corpo da Arya (não atinge quem está atrás)
local PROJ_SPEED = 6.0     -- velocidade autoritativa do projétil (unidades/tick)
local PROJ_RADIUS = 1.5    -- raio de colisão da lâmina
local LIFETIME_BUFFER = 3  -- ticks extras de lifetime_ticks além do trajeto previsto (failsafe)

-- Registro de lâminas voando: [proj_id] = blade (array + índice para iteração determinística)
local active_blades = {}
local blades_by_id = {}

local function is_projectile_entity(entity_id)
    if Loci.get_entity_type then
        return Loci.get_entity_type(entity_id) == "Projectile"
    end
    return false
end

-- Verifica se `other_id` é um jogador inimigo válido para deter a lâmina
local function is_enemy_player(blade, other_id)
    if other_id == blade.caster_id then
        return false
    end
    -- Sensores não detonam em outros projéteis/NPCs/props
    if is_projectile_entity(other_id) then
        return false
    end
    if Loci.get_entity_type and Loci.get_entity_type(other_id) ~= "Player" then
        return false
    end
    local other_team = Loci.get_entity_property(other_id, "team")
    return other_team ~= nil and tostring(other_team) ~= tostring(blade.team)
end

-- Aplica a explosão de impacto em área (aoe_radius) no ponto de impacto real
local function apply_aoe(blade, impact_x, impact_y)
    local CharacterFactory = require("systems.character_factory")
    local current_tick = CharacterFactory.get_current_tick()

    local hit_ids = Loci.get_entities_in_radius({ x = impact_x, y = impact_y }, blade.aoe_radius)
    local hit_count = 0

    if hit_ids then
        for _, target_id in ipairs(hit_ids) do
            if target_id ~= blade.caster_id and not is_projectile_entity(target_id) then
                local target_team = Loci.get_entity_property(target_id, "team") or "2"
                if target_team ~= blade.team then
                    CombatSystem.process_hit(blade.caster_id, target_id, blade.damage, blade.damage_type)

                    local stun_until = current_tick + blade.stun_duration_ticks
                    Loci.Commands.set_property(target_id, "stunned_until", tostring(stun_until))
                    Loci.Commands.set_velocity(target_id, { x = 0, y = 0 })

                    hit_count = hit_count + 1
                end
            end
        end
    end

    Loci.Log.info(string.format("[Blade Throw] Impacto resolvido por %s em (%.1f, %.1f) — acertou %d alvos",
        tostring(blade.caster_id), impact_x, impact_y, hit_count))
end

-- Resolve o impacto da lâmina uma única vez: aplica a AoE e destrói o projétil
local function resolve_impact(blade_id, blade, impact_x, impact_y, reason)
    if not blade or blade.resolved then
        return
    end
    blade.resolved = true
    blades_by_id[blade_id] = nil

    apply_aoe(blade, impact_x, impact_y)

    if blade.proj_id then
        Loci.Commands.destroy_entity(blade.proj_id)
    end

    for i = #active_blades, 1, -1 do
        if active_blades[i] == blade then
            table.remove(active_blades, i)
            break
        end
    end

    Loci.Log.info(string.format("[Blade Throw] Projétil %s destrutivo (%s)", tostring(blade.proj_id), tostring(reason)))
end

-- Chamado por main.lua a cada tick: resolve o impacto quando a lâmina atinge o alcance máximo
function BladeThrow.process_tick()
    for i = #active_blades, 1, -1 do
        local blade = active_blades[i]
        local proj_id = blade.proj_id
        if proj_id then
            local pos = Loci.get_entity_position(proj_id)
            if not pos then
                -- Projétil sumiu sem resolução (ex.: lifetime estourou): limpa o registro
                blade.resolved = true
                blades_by_id[proj_id] = nil
                table.remove(active_blades, i)
            else
                local px, py = get_coords(pos)
                local traveled = (px - blade.origin_x) * blade.dir_x + (py - blade.origin_y) * blade.dir_y
                if traveled >= blade.max_travel then
                    -- Ponto de impacto exato no alcance máximo (independente do overshoot do último tick)
                    resolve_impact(proj_id, blade, blade.end_x, blade.end_y, "max_range")
                end
            end
        end
    end
end

-- Chamado por main.lua em on_collision(id_a, id_b): retorna true se o par envolvia uma lâmina
function BladeThrow.on_collision(entity_a, entity_b)
    local blade_id, other_id
    if blades_by_id[entity_a] then
        blade_id, other_id = entity_a, entity_b
    elseif blades_by_id[entity_b] then
        blade_id, other_id = entity_b, entity_a
    else
        return false
    end

    local blade = blades_by_id[blade_id]
    if not blade or blade.resolved then
        return true
    end

    if not is_enemy_player(blade, other_id) then
        -- Aliados, projéteis e o próprio conjurador não detêm a lâmina
        return true
    end

    -- Ponto de impacto real: posição autoritativa do projétil no servidor no tick da colisão
    local pos = Loci.get_entity_position(blade_id)
    local impact_x, impact_y = blade.end_x, blade.end_y
    if pos then
        impact_x, impact_y = get_coords(pos)
    end
    resolve_impact(blade_id, blade, impact_x, impact_y, "enemy")
    return true
end

-- Chamado por main.lua em on_static_collision: a lâmina detona na superfície da parede
function BladeThrow.on_static_collision(entity_id, obstacle_id, nx, ny)
    local blade = blades_by_id[entity_id]
    if not blade or blade.resolved then
        return
    end
    local pos = Loci.get_entity_position(entity_id)
    local impact_x, impact_y = get_coords(pos)
    resolve_impact(entity_id, blade, impact_x, impact_y, "wall")
end

-- Chamado por main.lua em on_boundary_collision: a lâmina detona na borda da arena
function BladeThrow.on_boundary_collision(entity_id, nx, ny)
    local blade = blades_by_id[entity_id]
    if not blade or blade.resolved then
        return
    end
    local pos = Loci.get_entity_position(entity_id)
    local impact_x, impact_y = get_coords(pos)
    resolve_impact(entity_id, blade, impact_x, impact_y, "boundary")
end

BladeThrow.on_execute = function(entity_id, aim_x, aim_y, skill_data)
    -- Normaliza direção da mira
    local len = math.sqrt(aim_x * aim_x + aim_y * aim_y)
    if len > 0 then
        aim_x = aim_x / len
        aim_y = aim_y / len
    else
        aim_x, aim_y = 1, 0
    end

    local pos = Loci.get_entity_position(entity_id)
    local caster_x, caster_y = get_coords(pos)

    -- Aplica penalidade temática de Desarme na própria Arya
    local CharacterFactory = require("systems.character_factory")
    local current_tick = CharacterFactory.get_current_tick()
    local disarm_until = current_tick + skill_data.disarm_duration_ticks
    Loci.Commands.set_property(entity_id, "disarmed_until", tostring(disarm_until))

    local caster_team = Loci.get_entity_property(entity_id, "team") or "1"

    -- Ponto de spawn à frente do corpo e ponto de impacto no alcance máximo
    local spawn_x = caster_x + aim_x * SPAWN_OFFSET
    local spawn_y = caster_y + aim_y * SPAWN_OFFSET
    local end_x = caster_x + aim_x * skill_data.range
    local end_y = caster_y + aim_y * skill_data.range
    local max_travel = skill_data.range - SPAWN_OFFSET

    -- Spawna a lâmina como projétil físico real (sensor: colide sem empurrar o alvo)
    local travel_ticks = math.ceil(max_travel / PROJ_SPEED)
    local lifetime_ticks = travel_ticks + LIFETIME_BUFFER
    local proj_id = Loci.Commands.spawn_entity({
        blueprint = "blade_throw",
        position = { x = spawn_x, y = spawn_y },
        velocity = { x = aim_x * PROJ_SPEED, y = aim_y * PROJ_SPEED },
        entity_type = "Projectile",
        radius = PROJ_RADIUS,
        is_sensor = true,
        lifetime_ticks = lifetime_ticks,
        properties = {
            skill = "blade_throw",
            caster_id = tostring(entity_id),
            team = tostring(caster_team),
            dir_x = tostring(aim_x),
            dir_y = tostring(aim_y),
            aoe_radius = tostring(skill_data.aoe_radius),
        },
    })

    local blade = {
        proj_id = proj_id,
        caster_id = entity_id,
        team = caster_team,
        dir_x = aim_x,
        dir_y = aim_y,
        origin_x = spawn_x,
        origin_y = spawn_y,
        end_x = end_x,
        end_y = end_y,
        max_travel = max_travel,
        aoe_radius = skill_data.aoe_radius,
        damage = skill_data.damage,
        damage_type = skill_data.damage_type,
        stun_duration_ticks = skill_data.stun_duration_ticks,
        resolved = false,
    }

    if proj_id then
        active_blades[#active_blades + 1] = blade
        blades_by_id[proj_id] = blade
    else
        -- Fallback sem projétil (engine antiga): resolve imediatamente no alcance máximo
        Loci.Log.warn("[Blade Throw] spawn_entity falhou; resolvendo impacto instantâneo no alcance máximo")
        apply_aoe(blade, end_x, end_y)
    end

    Loci.Log.info(string.format("[Blade Throw] Executado por %s (projétil %s, alcance %.1f, Arya desarmada por %d ticks)",
        tostring(entity_id), tostring(proj_id), skill_data.range, skill_data.disarm_duration_ticks))
    return true
end

return BladeThrow
