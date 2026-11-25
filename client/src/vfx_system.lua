-- ============================================================================
-- Loci Arena - Client VFX System (client/src/vfx_system.lua)
-- Gerencia efeitos procedurais de habilidades, renderização de projéteis ativos,
-- partículas/efeitos de impacto sincronizados via on_entity_despawned (Card #100/#105),
-- números de dano flutuante (floating damage) e screen shake.
-- ============================================================================

local SkillRanges = require("src.skill_ranges")

local VfxSystem = {}

-- Configurações visuais padrão (podem ser ajustadas via VfxSystem.configure)
local config = {
    visual_scale = 8.0,
    sprite_base_size = 32,
    sprite_scale = 2,
    clamp_fn = nil,
    font_damage_normal = nil,
    font_damage_critical = nil,
}

-- Estados internos de efeitos visuais
local visual_fx = {}
local floating_damage = {}
local particles = {}
local tracked_projectiles = {} -- [entity_id] = { id, x, y, vx, vy, dir_x, dir_y, skill_name, blueprint, aoe_radius, start_x, start_y }

-- Estado de Screen Shake
local shake_duration = 0
local shake_total_duration = 0.2
local shake_intensity = 0

local function clamp_coords(wx, wy)
    if type(config.clamp_fn) == "function" then
        return config.clamp_fn(wx, wy)
    end
    local c_min, c_max = -498.0, 498.0
    local cx = math.max(c_min, math.min(c_max, wx or 0))
    local cy = math.max(c_min, math.min(c_max, wy or 0))
    return cx, cy
end

local function get_body_offset_y()
    return (config.sprite_base_size * config.sprite_scale) / 2
end

local function ensure_fonts()
    if not (love and love.graphics and love.graphics.newFont) then
        return
    end
    if not config.font_damage_normal then
        config.font_damage_normal = love.graphics.newFont(18)
    end
    if not config.font_damage_critical then
        config.font_damage_critical = love.graphics.newFont(24)
    end
end

--- Configura parâmetros de escala, fontes e função de clamp da arena.
function VfxSystem.configure(opts)
    if type(opts) ~= "table" then return end
    if opts.visual_scale then config.visual_scale = opts.visual_scale end
    if opts.sprite_base_size then config.sprite_base_size = opts.sprite_base_size end
    if opts.sprite_scale then config.sprite_scale = opts.sprite_scale end
    if opts.clamp_fn then config.clamp_fn = opts.clamp_fn end
    if opts.font_damage_normal then config.font_damage_normal = opts.font_damage_normal end
    if opts.font_damage_critical then config.font_damage_critical = opts.font_damage_critical end
end

--- Limpa todos os efeitos ativos (útil ao trocar de cena ou em testes).
function VfxSystem.reset()
    for i = #visual_fx, 1, -1 do visual_fx[i] = nil end
    for i = #floating_damage, 1, -1 do floating_damage[i] = nil end
    for i = #particles, 1, -1 do particles[i] = nil end
    tracked_projectiles = {}
    shake_duration = 0
    shake_total_duration = 0.2
    shake_intensity = 0
end

--- Retorna as listas internas para inspeção em testes automatizados.
function VfxSystem.get_visual_fx()
    return visual_fx
end

function VfxSystem.get_floating_damage()
    return floating_damage
end

function VfxSystem.get_particles()
    return particles
end

function VfxSystem.get_tracked_projectiles()
    return tracked_projectiles
end

-- ============================================================================
-- Identificação e Rastreamento de Projéteis (SDK v0.6.7)
-- ============================================================================

local function get_ent_prop(ent, key)
    if not ent then return nil end
    if type(ent.get) == "function" then
        local v = ent:get(key)
        if v ~= nil then return v end
    end
    if ent.properties and ent.properties[key] ~= nil then
        return ent.properties[key]
    end
    return ent[key]
end

--- Resolve o nome da habilidade associada a uma entidade de projétil.
function VfxSystem.resolve_projectile_skill(ent)
    if not ent then return nil end
    local skill = get_ent_prop(ent, "skill_name") or get_ent_prop(ent, "skill_id")
    if type(skill) == "string" and skill ~= "" then
        return string.lower(skill)
    end
    local bp = string.lower(tostring(ent.blueprint or ent.name or ""))
    if bp:find("blade", 1, true) then
        return "blade_throw"
    elseif bp:find("fireball", 1, true) then
        return "fireball"
    end
    return bp ~= "" and bp or nil
end

--- Verifica se uma entidade replicada pelo SDK é um projétil.
function VfxSystem.is_projectile_entity(ent)
    if not ent then return false end
    if type(ent.is_projectile) == "function" and ent:is_projectile() then
        return true
    end
    local et = string.lower(tostring(ent.entity_type or get_ent_prop(ent, "entity_type") or ""))
    if et == "projectile" then
        return true
    end
    local bp = string.lower(tostring(ent.blueprint or ent.name or ""))
    if bp == "blade_throw" or bp == "fireball" or bp == "thrownblade"
        or bp:find("projectile", 1, true) or bp:find("bullet", 1, true) then
        return true
    end
    return false
end

--- Registra o spawn de um projétil para rastrear sua trajetória e metadados até o despawn.
function VfxSystem.on_entity_spawned(entity)
    if not VfxSystem.is_projectile_entity(entity) then
        return false
    end

    local skill_name = VfxSystem.resolve_projectile_skill(entity)
    local dir_x = tonumber(get_ent_prop(entity, "dir_x")) or 0
    local dir_y = tonumber(get_ent_prop(entity, "dir_y")) or 0
    if dir_x == 0 and dir_y == 0 then
        local vx = tonumber(entity.vx) or 0
        local vy = tonumber(entity.vy) or 0
        local len = math.sqrt(vx * vx + vy * vy)
        if len > 0 then
            dir_x, dir_y = vx / len, vy / len
        else
            dir_x, dir_y = 1, 0
        end
    end

    tracked_projectiles[entity.id] = {
        id = entity.id,
        x = tonumber(entity.x) or 0,
        y = tonumber(entity.y) or 0,
        start_x = tonumber(entity.x) or 0,
        start_y = tonumber(entity.y) or 0,
        vx = tonumber(entity.vx) or 0,
        vy = tonumber(entity.vy) or 0,
        dir_x = dir_x,
        dir_y = dir_y,
        skill_name = skill_name,
        blueprint = entity.blueprint or entity.name,
        owner_id = tonumber(get_ent_prop(entity, "owner_id")),
        aoe_radius = tonumber(get_ent_prop(entity, "aoe_radius")),
    }

    -- Vincula qualquer efeito procedural de voo da mesma habilidade ao projétil real
    for i = #visual_fx, 1, -1 do
        local fx = visual_fx[i]
        if not fx.is_impact and fx.skill_name == skill_name and not fx.projectile_id then
            fx.projectile_id = entity.id
            break
        end
    end

    return true
end

local function spawn_impact_particles(wx, wy, skill_name)
    local count = (skill_name == "blade_throw") and 10 or 12
    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        local speed = (skill_name == "blade_throw") and (14.0 + (i % 3) * 4.0) or (12.0 + (i % 4) * 3.5)
        table.insert(particles, {
            x = wx,
            y = wy,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            radius = (skill_name == "blade_throw") and 3.5 or 4.5,
            skill_name = skill_name,
            lifetime = 0.28,
            max_lifetime = 0.28,
        })
    end
end

--- Encerra efeitos de voo de um projétil e dispara o VFX de impacto nas coordenadas reais do despawn (Card #100/#105).
function VfxSystem.on_entity_despawned(entity_id, last_entity)
    local tracked = entity_id and tracked_projectiles[entity_id] or nil
    local is_proj = (tracked ~= nil) or VfxSystem.is_projectile_entity(last_entity)
    if not is_proj then
        return false
    end

    local source = last_entity or tracked
    local impact_x = tonumber(last_entity and last_entity.x) or tonumber(tracked and tracked.x) or 0
    local impact_y = tonumber(last_entity and last_entity.y) or tonumber(tracked and tracked.y) or 0
    local skill_name = VfxSystem.resolve_projectile_skill(last_entity) or (tracked and tracked.skill_name) or "blade_throw"
    local aoe_world = tonumber(get_ent_prop(source, "aoe_radius"))
        or (tracked and tracked.aoe_radius)
        or SkillRanges.aoe(skill_name, 8.0)

    tracked_projectiles[entity_id] = nil

    -- 1. Encerra imediatamente qualquer renderização procedural de voo da lâmina/projétil
    for i = #visual_fx, 1, -1 do
        local fx = visual_fx[i]
        if not fx.is_impact then
            local resolved_fx_skill = fx.skill_name
            if not resolved_fx_skill then
                if fx.ability_id == 4 then resolved_fx_skill = "blade_throw"
                elseif fx.ability_id == 1 and string.lower(tostring(fx.character_name or "")) == "mage" then
                    resolved_fx_skill = "fireball"
                end
            end
            if fx.projectile_id == entity_id or resolved_fx_skill == skill_name then
                table.remove(visual_fx, i)
                break
            end
        end
    end

    -- 2. Spawna o VFX de impacto/Stun exatamente na coordenada real do despawn do servidor
    local impact_lifetime = (skill_name == "blade_throw") and 0.35 or 0.35
    table.insert(visual_fx, {
        x = impact_x,
        y = impact_y,
        dir_x = (tracked and tracked.dir_x) or tonumber(get_ent_prop(source, "dir_x")) or 1,
        dir_y = (tracked and tracked.dir_y) or tonumber(get_ent_prop(source, "dir_y")) or 0,
        skill_name = skill_name,
        aoe_world = aoe_world,
        is_impact = true,
        projectile_id = entity_id,
        lifetime = impact_lifetime,
        max_lifetime = impact_lifetime,
    })

    spawn_impact_particles(impact_x, impact_y, skill_name)
    return true
end

-- ============================================================================
-- Screen Shake, Floating Damage & Skill Cast VFX
-- ============================================================================

function VfxSystem.trigger_shake(damage, duration)
    local dmg = tonumber(damage) or 0
    if dmg <= 50 then return end
    local dur = tonumber(duration) or 0.2
    shake_total_duration = dur
    shake_duration = dur
    local intensity = math.min(8, 2.5 + (dmg / 120))
    shake_intensity = math.max(shake_intensity, intensity)
end

function VfxSystem.get_shake_offset()
    if shake_duration > 0 and shake_intensity > 0 and shake_total_duration > 0 then
        local current_intensity = shake_intensity * (shake_duration / shake_total_duration)
        local rng = (love and love.math and love.math.random) or math.random
        local ox = (rng() - 0.5) * 2 * current_intensity
        local oy = (rng() - 0.5) * 2 * current_intensity
        return ox, oy
    end
    return 0, 0
end

function VfxSystem.add_floating_damage(entity_or_pos, damage, opts)
    local val = tonumber(damage) or 0
    if val <= 0 then return end
    opts = opts or {}
    local hud_offset_y = opts.offset_y or ((config.sprite_base_size * config.sprite_scale) + 32)
    table.insert(floating_damage, {
        value = val,
        x = (entity_or_pos and entity_or_pos.x) or 0,
        y = (entity_or_pos and entity_or_pos.y) or 0,
        offset_y = hud_offset_y,
        lifetime = opts.lifetime or 1.0,
        max_lifetime = opts.max_lifetime or opts.lifetime or 1.0,
        is_critical = opts.is_critical == true,
        is_shield = opts.is_shield == true,
    })
end

function VfxSystem.spawn_skill_fx(params)
    if type(params) ~= "table" then return end
    local skill_name = params.skill_name
    local ability_id = params.ability_id
    local character_name = string.lower(tostring(params.character_name or "default"))

    local lifetime = params.lifetime
    if not lifetime then
        lifetime = 0.35
        if skill_name == "fireball" or (not skill_name and ability_id == 1 and character_name == "mage") then
            lifetime = 0.40
        elseif skill_name == "whirlwind_dash" or (not skill_name and ability_id == 3) then
            lifetime = 0.45
        elseif skill_name == "blade_throw" or (not skill_name and ability_id == 4) then
            lifetime = 0.60
        end
    end

    table.insert(visual_fx, {
        x = tonumber(params.x) or 0,
        y = tonumber(params.y) or 0,
        dir_x = tonumber(params.dir_x) or 1,
        dir_y = tonumber(params.dir_y) or 0,
        ability_id = ability_id,
        skill_name = skill_name,
        character_name = character_name,
        caster_id = params.caster_id,
        is_impact = params.is_impact == true,
        aoe_world = params.aoe_world,
        lifetime = lifetime,
        max_lifetime = params.max_lifetime or lifetime,
    })
end

-- ============================================================================
-- Ciclo de Atualização (love.update)
-- ============================================================================

function VfxSystem.update(dt)
    for i = #visual_fx, 1, -1 do
        visual_fx[i].lifetime = visual_fx[i].lifetime - dt
        if visual_fx[i].lifetime <= 0 then
            table.remove(visual_fx, i)
        end
    end

    for i = #floating_damage, 1, -1 do
        local fd = floating_damage[i]
        fd.lifetime = fd.lifetime - dt
        fd.offset_y = fd.offset_y + 50 * dt
        if fd.lifetime <= 0 then
            table.remove(floating_damage, i)
        end
    end

    for i = #particles, 1, -1 do
        local p = particles[i]
        p.lifetime = p.lifetime - dt
        if p.lifetime <= 0 then
            table.remove(particles, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
        end
    end

    if shake_duration > 0 then
        shake_duration = shake_duration - dt
        if shake_duration <= 0 then
            shake_duration = 0
            shake_intensity = 0
        end
    end
end

-- ============================================================================
-- Renderização de Efeitos Procedurais, Impactos no Despawn e Projéteis Ativos
-- ============================================================================

local function draw_impact_fx(fx, progress, inv_prog, skill_name, aoe_px)
    local scale = config.visual_scale
    local body_offset_y = get_body_offset_y()
    local px = (fx.x or 0) * scale
    local py = ((fx.y or 0) * scale) - body_offset_y

    if skill_name == "blade_throw" then
        -- Shockwave de Stun em área centrado exatamente no ponto real de despawn (Card #100)
        local shock_r = aoe_px * math.max(0.15, inv_prog)
        love.graphics.setColor(0.3, 0.75, 1.0, progress * 0.30)
        love.graphics.circle("fill", px, py, shock_r * 0.65)
        love.graphics.setColor(1.0, 0.9, 0.2, progress * 0.95)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", px, py, shock_r)
    elseif skill_name == "fireball" then
        local blast_r = aoe_px * (1 / 3 + 2 / 3 * inv_prog)
        love.graphics.setColor(1.0, 0.45, 0.05, progress * 0.35)
        love.graphics.circle("fill", px, py, blast_r)
        love.graphics.setColor(1.0, 0.75, 0.2, progress * 0.55)
        love.graphics.circle("fill", px, py, blast_r * 0.55)
        love.graphics.setColor(1.0, 0.35, 0.05, progress * 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", px, py, blast_r)
    else
        local r = math.max(12, aoe_px) * inv_prog
        love.graphics.setColor(1.0, 0.85, 0.2, progress * 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", px, py, r)
    end
end

function VfxSystem.draw_procedural_skill_fx(fx)
    local scale = config.visual_scale
    local body_offset_y = get_body_offset_y()
    local progress = fx.lifetime / fx.max_lifetime
    local inv_prog = 1.0 - progress
    local fx_start_x = (fx.x or 0) * scale
    local fx_start_y = ((fx.y or 0) * scale) - body_offset_y

    local char_name = string.lower(tostring(fx.character_name or "default"))
    local skill_name = fx.skill_name
    if not skill_name then
        if fx.ability_id == 1 then
            skill_name = (char_name == "mage") and "fireball" or "slash"
        elseif fx.ability_id == 2 then
            skill_name = "fury_reward"
        elseif fx.ability_id == 3 then
            skill_name = "whirlwind_dash"
        elseif fx.ability_id == 4 then
            skill_name = "blade_throw"
        end
    end

    local range_px = SkillRanges.range(skill_name, 0) * scale
    local aoe_world = tonumber(fx.aoe_world) or SkillRanges.aoe(skill_name, 0)
    local aoe_px = aoe_world * scale

    -- Se for um efeito de impacto engatilhado por on_entity_despawned, desenha na coordenada real
    if fx.is_impact then
        draw_impact_fx(fx, progress, inv_prog, skill_name, aoe_px)
        return
    end

    -- Se o efeito procedural estiver vinculado a uma entidade Projectile ativa, a entidade real desenha o projétil
    if fx.projectile_id and tracked_projectiles[fx.projectile_id] then
        return
    end

    if skill_name == "fireball" then
        local max_dist = range_px * 0.7
        local travel_t = math.min(1.0, inv_prog / 0.5)
        local travel_dist = max_dist * travel_t
        local fireball_x = fx_start_x + fx.dir_x * travel_dist
        local fireball_y = fx_start_y + fx.dir_y * travel_dist

        if inv_prog <= 0.5 then
            local radius = 18 + 8 * travel_t
            love.graphics.setColor(1.0, 0.4, 0.0, progress * 0.4)
            love.graphics.setLineWidth(3)
            love.graphics.line(fx_start_x, fx_start_y, fireball_x, fireball_y)

            love.graphics.setColor(1.0, 0.55, 0.1, progress * 0.9)
            love.graphics.circle("fill", fireball_x, fireball_y, radius)
            love.graphics.setColor(1.0, 0.9, 0.3, progress * 0.75)
            love.graphics.circle("fill", fireball_x, fireball_y, radius * 0.6)
            love.graphics.setColor(1.0, 1.0, 0.85, progress * 0.6)
            love.graphics.circle("fill", fireball_x, fireball_y, radius * 0.3)
        else
            local blast_t = (inv_prog - 0.5) / 0.5
            local blast_alpha = 1.0 - blast_t
            local blast_r = aoe_px * (1 / 3 + 2 / 3 * blast_t)

            love.graphics.setColor(1.0, 0.45, 0.05, blast_alpha * 0.35)
            love.graphics.circle("fill", fireball_x, fireball_y, blast_r)
            love.graphics.setColor(1.0, 0.75, 0.2, blast_alpha * 0.55)
            love.graphics.circle("fill", fireball_x, fireball_y, blast_r * 0.55)
            love.graphics.setColor(1.0, 0.35, 0.05, blast_alpha * 0.9)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", fireball_x, fireball_y, blast_r)
        end
    elseif skill_name == "slash" then
        local angle = math.atan2(fx.dir_y, fx.dir_x)
        local radius = range_px * (0.6 + 0.4 * inv_prog)
        love.graphics.setColor(0.9, 0.95, 1.0, progress * 0.9)
        love.graphics.setLineWidth(4)
        love.graphics.arc("line", "open", fx_start_x, fx_start_y, radius, angle - 0.8, angle + 0.8)
        love.graphics.setColor(0.3, 0.7, 1.0, progress * 0.5)
        love.graphics.setLineWidth(8)
        love.graphics.arc("line", "open", fx_start_x, fx_start_y, radius * 0.85, angle - 0.6, angle + 0.6)
    elseif skill_name == "fury_reward" then
        local hit_dist = range_px * 0.5
        local hit_x = fx_start_x + fx.dir_x * hit_dist
        local hit_y = fx_start_y + fx.dir_y * hit_dist
        local r = aoe_px * (0.5 + 0.5 * inv_prog)
        love.graphics.setColor(1.0, 0.2, 0.2, progress * 0.85)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", hit_x, hit_y, r)
        love.graphics.setColor(1.0, 0.5, 0.1, progress * 0.4)
        love.graphics.circle("fill", hit_x, hit_y, r * 0.6)
    elseif skill_name == "whirlwind_dash" then
        local dash_world_dist = SkillRanges.range("whirlwind_dash", 0) * inv_prog
        local raw_wx = (fx.x or 0) + (fx.dir_x or 0) * dash_world_dist
        local raw_wy = (fx.y or 0) + (fx.dir_y or 0) * dash_world_dist
        local clamped_wx, clamped_wy = clamp_coords(raw_wx, raw_wy)
        local curr_x = clamped_wx * scale
        local curr_y = (clamped_wy * scale) - body_offset_y
        local r = aoe_px * (0.7 + 0.3 * inv_prog)
        local spin_angle = inv_prog * math.pi * 5
        love.graphics.setColor(1.0, 0.85, 0.3, progress * 0.85)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", curr_x, curr_y, r)
        love.graphics.setColor(1.0, 0.9, 0.5, progress * 0.6)
        for i = 0, 3 do
            local a = spin_angle + (i * math.pi / 2)
            love.graphics.line(
                curr_x, curr_y,
                curr_x + math.cos(a) * r,
                curr_y + math.sin(a) * r
            )
        end
    elseif skill_name == "blade_throw" then
        local max_dist = range_px
        local travel_dist = max_dist * math.min(1.0, inv_prog * 2.2)
        local blade_x = fx_start_x + fx.dir_x * travel_dist
        local blade_y = fx_start_y + fx.dir_y * travel_dist

        love.graphics.setColor(0.4, 0.8, 1.0, progress * 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.line(fx_start_x, fx_start_y, blade_x, blade_y)

        love.graphics.setColor(1.0, 1.0, 1.0, progress)
        love.graphics.circle("fill", blade_x, blade_y, 7)
        love.graphics.setColor(0.2, 0.6, 1.0, progress)
        love.graphics.circle("line", blade_x, blade_y, 7)

        if inv_prog > 0.45 then
            local shock_r = aoe_px * ((inv_prog - 0.45) / 0.55)
            love.graphics.setColor(1.0, 0.9, 0.2, progress * 0.9)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", blade_x, blade_y, shock_r)
        end
    else
        local fx_end_x = fx_start_x + fx.dir_x * 50 * scale
        local fx_end_y = fx_start_y + fx.dir_y * 50 * scale
        love.graphics.setColor(1, 0.85, 0.2, progress)
        love.graphics.line(fx_start_x, fx_start_y, fx_end_x, fx_end_y)
        love.graphics.circle("fill", fx_end_x, fx_end_y, 5 * progress)
    end
end

--- Renderiza uma entidade Projectile replicada pelo SDK enquanto estiver ativa no mundo.
function VfxSystem.draw_projectile(ent)
    if not ent then return end

    local tracked = tracked_projectiles[ent.id]
    if not tracked then
        VfxSystem.on_entity_spawned(ent)
        tracked = tracked_projectiles[ent.id]
    else
        tracked.x = tonumber(ent.x) or tracked.x
        tracked.y = tonumber(ent.y) or tracked.y
        tracked.vx = tonumber(ent.vx) or tracked.vx
        tracked.vy = tonumber(ent.vy) or tracked.vy
    end

    local scale = config.visual_scale
    local body_offset_y = get_body_offset_y()
    local px = (ent.x or 0) * scale
    local py = ((ent.y or 0) * scale) - body_offset_y
    local skill_name = VfxSystem.resolve_projectile_skill(ent) or (tracked and tracked.skill_name) or "projectile"

    local dir_x = (tracked and tracked.dir_x) or tonumber(get_ent_prop(ent, "dir_x")) or 1
    local dir_y = (tracked and tracked.dir_y) or tonumber(get_ent_prop(ent, "dir_y")) or 0

    if skill_name == "blade_throw" then
        local start_px = ((tracked and tracked.start_x) or (ent.x - dir_x * 3.0)) * scale
        local start_py = (((tracked and tracked.start_y) or (ent.y - dir_y * 3.0)) * scale) - body_offset_y

        -- Rastro da lâmina arremessada
        love.graphics.setColor(0.4, 0.8, 1.0, 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.line(start_px, start_py, px, py)

        -- Núcleo e anel metálico da lâmina
        love.graphics.setColor(1.0, 1.0, 1.0, 0.95)
        love.graphics.circle("fill", px, py, 7)
        love.graphics.setColor(0.2, 0.6, 1.0, 0.95)
        love.graphics.circle("line", px, py, 7)
    elseif skill_name == "fireball" then
        local tail_x = px - dir_x * 20
        local tail_y = py - dir_y * 20
        love.graphics.setColor(1.0, 0.4, 0.0, 0.45)
        love.graphics.setLineWidth(3)
        love.graphics.line(tail_x, tail_y, px, py)

        local radius = 16
        love.graphics.setColor(1.0, 0.55, 0.1, 0.9)
        love.graphics.circle("fill", px, py, radius)
        love.graphics.setColor(1.0, 0.9, 0.3, 0.8)
        love.graphics.circle("fill", px, py, radius * 0.6)
        love.graphics.setColor(1.0, 1.0, 0.85, 0.7)
        love.graphics.circle("fill", px, py, radius * 0.3)
    else
        love.graphics.setColor(1.0, 0.85, 0.25, 0.95)
        love.graphics.circle("fill", px, py, 6)
        love.graphics.setColor(1.0, 1.0, 1.0, 0.9)
        love.graphics.circle("line", px, py, 6)
    end
end

--- Desenha todos os efeitos procedurais e partículas de impacto no espaço do mundo.
function VfxSystem.draw_world_effects()
    for _, fx in ipairs(visual_fx) do
        VfxSystem.draw_procedural_skill_fx(fx)
    end

    if #particles > 0 then
        local scale = config.visual_scale
        local body_offset_y = get_body_offset_y()
        for _, p in ipairs(particles) do
            local alpha = math.max(0, p.lifetime / p.max_lifetime)
            local px = p.x * scale
            local py = (p.y * scale) - body_offset_y
            if p.skill_name == "blade_throw" then
                love.graphics.setColor(1.0, 0.9, 0.25, alpha * 0.9)
            elseif p.skill_name == "fireball" then
                love.graphics.setColor(1.0, 0.5, 0.1, alpha * 0.9)
            else
                love.graphics.setColor(1.0, 1.0, 1.0, alpha * 0.85)
            end
            love.graphics.circle("fill", px, py, p.radius * alpha)
        end
    end
end

--- Desenha os números de dano flutuante sobre os personagens.
function VfxSystem.draw_floating_damage()
    if #floating_damage == 0 then
        return
    end

    ensure_fonts()
    local scale = config.visual_scale
    local original_font = love.graphics.getFont and love.graphics.getFont() or nil

    for _, fd in ipairs(floating_damage) do
        local progress = fd.lifetime / fd.max_lifetime
        local alpha = progress
        local text_scale = 1.0 + (1.0 - progress) * 0.3

        local text_x = fd.x * scale
        local text_y = (fd.y * scale) - fd.offset_y

        love.graphics.push()
        love.graphics.translate(text_x, text_y)
        love.graphics.scale(text_scale, text_scale)

        if fd.is_shield then
            love.graphics.setColor(0.3, 0.75, 1.0, alpha)
            if config.font_damage_normal then love.graphics.setFont(config.font_damage_normal) end
        elseif fd.is_critical then
            love.graphics.setColor(1.0, 0.15, 0.15, alpha)
            if config.font_damage_critical then love.graphics.setFont(config.font_damage_critical) end
        else
            love.graphics.setColor(1.0, 1.0, 1.0, alpha)
            if config.font_damage_normal then love.graphics.setFont(config.font_damage_normal) end
        end

        local damage_text = string.format("%d", fd.value)
        local cur_font = love.graphics.getFont and love.graphics.getFont() or nil
        local tw = (cur_font and cur_font.getWidth) and cur_font:getWidth(damage_text) or (#damage_text * 10)
        love.graphics.print(damage_text, -tw / 2, 0)

        love.graphics.pop()
    end

    if original_font then
        love.graphics.setFont(original_font)
    end
    love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
end

return VfxSystem
