-- VfxSystem - Sistema de Efeitos Visuais
-- Gerencia partículas, floating damage text e efeitos procedurais de habilidades
-- Extrai lógica de VFX de client/main.lua para modularização

local VfxSystem = {}

-- Dependências externas (serão injetadas via init)
local VISUAL_SCALE = 8
local SPRITE_BASE_SIZE = 32
local SPRITE_SCALE = 2
local SkillRanges = nil
local font_damage_normal = nil
local font_damage_critical = nil
local clamp_arena_coords = nil

-- Tabelas internas de efeitos
local visual_fx = {}
local floating_damage = {}

-- Inicialização do sistema
function VfxSystem.init(config)
    config = config or {}
    VISUAL_SCALE = config.VISUAL_SCALE or 8
    SPRITE_BASE_SIZE = config.SPRITE_BASE_SIZE or 32
    SPRITE_SCALE = config.SPRITE_SCALE or 2
    SkillRanges = config.SkillRanges
    font_damage_normal = config.font_damage_normal
    font_damage_critical = config.font_damage_critical
    clamp_arena_coords = config.clamp_arena_coords
end

-- Adicionar efeito procedural de habilidade
function VfxSystem.add_procedural_fx(data)
    table.insert(visual_fx, {
        x = data.x or 0,
        y = data.y or 0,
        dir_x = data.dir_x or 0,
        dir_y = data.dir_y or 0,
        ability_id = data.ability_id,
        skill_name = data.skill_name,
        character_name = data.character_name,
        lifetime = data.lifetime or 0.35,
        max_lifetime = data.lifetime or 0.35,
        is_impact = data.is_impact or false
    })
end

-- Adicionar dano flutuante
function VfxSystem.add_floating_damage(data)
    local hud_offset_y = (SPRITE_BASE_SIZE * SPRITE_SCALE) + 32
    table.insert(floating_damage, {
        value = data.value,
        x = data.x,
        y = data.y,
        offset_y = hud_offset_y,
        lifetime = 1.0,
        max_lifetime = 1.0,
        is_critical = data.is_critical or false,
        is_shield = data.is_shield or false
    })
end

-- Atualizar todos os efeitos
function VfxSystem.update(dt)
    -- Update visual effects (skills)
    for i = #visual_fx, 1, -1 do
        visual_fx[i].lifetime = visual_fx[i].lifetime - dt
        if visual_fx[i].lifetime <= 0 then
            table.remove(visual_fx, i)
        end
    end

    -- Update floating damage numbers
    for i = #floating_damage, 1, -1 do
        local fd = floating_damage[i]
        fd.lifetime = fd.lifetime - dt
        fd.offset_y = fd.offset_y + 50 * dt
        if fd.lifetime <= 0 then
            table.remove(floating_damage, i)
        end
    end
end

-- Renderizar efeito procedural de habilidade
local function draw_procedural_skill_fx(fx)
    local progress = fx.lifetime / fx.max_lifetime
    local inv_prog = 1.0 - progress
    local fx_start_x = fx.x * VISUAL_SCALE
    local fx_start_y = (fx.y * VISUAL_SCALE) - (SPRITE_BASE_SIZE * SPRITE_SCALE) / 2

    -- Mapeamento de VFX desacoplado por skill_name (com fallback por ability_id / character_name)
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

    -- Alcance e raio da AoE da habilidade em pixels (unidades do mundo * VISUAL_SCALE)
    local range_px = SkillRanges.range(skill_name, 0) * VISUAL_SCALE
    local aoe_px = SkillRanges.aoe(skill_name, 0) * VISUAL_SCALE

    if skill_name == "fireball" then
        -- Fireball: projétil até range * 0.7 seguido de explosão na área real (aoe_radius)
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
        local body_offset_y = (SPRITE_BASE_SIZE * SPRITE_SCALE) / 2
        local dash_world_dist = SkillRanges.range("whirlwind_dash", 0) * inv_prog
        local raw_wx = (fx.x or 0) + (fx.dir_x or 0) * dash_world_dist
        local raw_wy = (fx.y or 0) + (fx.dir_y or 0) * dash_world_dist
        local clamped_wx, clamped_wy = raw_wx, raw_wy
        if clamp_arena_coords then
            clamped_wx, clamped_wy = clamp_arena_coords(raw_wx, raw_wy)
        end
        local curr_x = clamped_wx * VISUAL_SCALE
        local curr_y = (clamped_wy * VISUAL_SCALE) - body_offset_y
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
    elseif skill_name == "blade_throw_impact" then
        -- VFX de impacto sincronizado com servidor
        local r = aoe_px * (1.0 - progress)
        love.graphics.setColor(1.0, 0.9, 0.2, progress * 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", fx_start_x, fx_start_y, r)
        love.graphics.setColor(1.0, 0.5, 0.1, progress * 0.4)
        love.graphics.circle("fill", fx_start_x, fx_start_y, r * 0.6)
    else
        local fx_end_x = fx_start_x + fx.dir_x * 50 * VISUAL_SCALE
        local fx_end_y = fx_start_y + fx.dir_y * 50 * VISUAL_SCALE
        love.graphics.setColor(1, 0.85, 0.2, progress)
        love.graphics.line(fx_start_x, fx_start_y, fx_end_x, fx_end_y)
        love.graphics.circle("fill", fx_end_x, fx_end_y, 5 * progress)
    end
end

-- Renderizar todos os efeitos
function VfxSystem.draw()
    -- Draw transient procedural fallback effects
    for _, fx in ipairs(visual_fx) do
        draw_procedural_skill_fx(fx)
    end

    -- Draw floating damage numbers
    if #floating_damage > 0 then
        local original_font = love.graphics.getFont()
        for _, fd in ipairs(floating_damage) do
            local progress = fd.lifetime / fd.max_lifetime
            local alpha = progress
            local scale = 1.0 + (1.0 - progress) * 0.3

            local text_x = fd.x * VISUAL_SCALE
            local text_y = (fd.y * VISUAL_SCALE) - fd.offset_y

            love.graphics.push()
            love.graphics.translate(text_x, text_y)
            love.graphics.scale(scale, scale)

            if fd.is_shield then
                love.graphics.setColor(0.3, 0.75, 1.0, alpha)
                love.graphics.setFont(font_damage_normal)
            elseif fd.is_critical then
                love.graphics.setColor(1.0, 0.15, 0.15, alpha)
                love.graphics.setFont(font_damage_critical)
            else
                love.graphics.setColor(1.0, 1.0, 1.0, alpha)
                love.graphics.setFont(font_damage_normal)
            end

            local damage_text = string.format("%d", fd.value)
            local tw = love.graphics.getFont():getWidth(damage_text)
            love.graphics.print(damage_text, -tw / 2, 0)

            love.graphics.pop()
        end
        love.graphics.setFont(original_font)
        love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
    end
end

-- Verificar se entidade é projétil
function VfxSystem.is_projectile(entity)
    if not entity then return false end

    -- Verificar blueprint
    local blueprint = entity.blueprint or (entity.properties and entity.properties.blueprint)
    if blueprint and (blueprint:find("projectile") or blueprint:find("blade")) then
        return true
    end

    -- Verificar propriedade customizada
    local is_proj = entity.is_projectile or (entity.properties and entity.properties.is_projectile)
    if is_proj == "true" or is_proj == true or is_proj == 1 then
        return true
    end

    return false
end

-- Sincronizar VFX de impacto no despawn de projétil
function VfxSystem.on_projectile_impact(entity_id, last_entity)
    local impact_x = last_entity.x
    local impact_y = last_entity.y

    -- Detectar tipo de projétil pelo blueprint
    local blueprint = last_entity.blueprint or (last_entity.properties and last_entity.properties.blueprint)

    if blueprint and (blueprint:find("blade") or blueprint:find("projectile")) then
        -- Encerrar renderização da lâmina e desenhar shockwave de Stun na coordenada real
        VfxSystem.add_procedural_fx({
            x = impact_x,
            y = impact_y,
            skill_name = "blade_throw_impact",
            lifetime = 0.5,
            max_lifetime = 0.5,
            is_impact = true
        })
    end
end

-- Renderizar projétil físico
function VfxSystem.draw_projectile(ent)
    local px = ent.x * VISUAL_SCALE
    local py = ent.y * VISUAL_SCALE

    -- Renderizar sprite de projétil baseado no blueprint
    local blueprint = ent.blueprint or (ent.properties and ent.properties.blueprint)

    if blueprint and (blueprint:find("blade") or blueprint:find("projectile")) then
        -- Desenhar lâmina girando
        love.graphics.setColor(0.4, 0.8, 1.0, 1.0)
        love.graphics.circle("fill", px, py, 8)
        love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
        love.graphics.circle("line", px, py, 8)
    else
        -- Sprite genérico de projétil
        love.graphics.setColor(1.0, 0.5, 0.2, 1.0)
        love.graphics.circle("fill", px, py, 6)
    end
end

return VfxSystem
