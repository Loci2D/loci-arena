-- ============================================================================
-- MORTE.LUA - Sistema de UI de Morte (Cliente)
-- ============================================================================
-- Gerencia o Death Recap (resumo de dano recebido)
-- ============================================================================

local Morte = {}

-- ============================================================================
-- CONFIGURAÇÕES
-- ============================================================================
Morte.config = {
    colors = {
        background = {0, 0, 0, 0.85},
        border = {0.8, 0.2, 0.2, 1},
        text = {1, 1, 1, 1},
        text_dim = {0.7, 0.7, 0.7, 1},
        damage_physical = {0.9, 0.6, 0.3, 1},
        damage_magical = {0.6, 0.3, 0.9, 1},
        damage_true = {1, 0.2, 0.2, 1},
    },
    
    death_recap = {
        width = 400,
        height = 350,
        entry_height = 30,
        max_entries = 10,
        display_time = 5.0, -- segundos
    }
}

-- ============================================================================
-- ESTADO
-- ============================================================================
Morte.state = {
    show_death_recap = false,
    death_recap_data = nil,
    death_recap_timer = 0,
}

-- ============================================================================
-- FUNÇÕES AUXILIARES
-- ============================================================================
local function parse_damage_history(history_str)
    if not history_str or history_str == "" then return {} end
    
    local success, data = pcall(function()
        history_str = history_str:gsub("%s+", "")
        local entries = {}
        local pattern = "{([^}]+)}"
        
        for entry_str in history_str:gmatch(pattern) do
            local entry = {}
            for key, val in entry_str:gmatch("([^:,]+):([^,]+)") do
                entry[key] = tonumber(val) or val
            end
            if entry.attacker and entry.damage then
                table.insert(entries, entry)
            end
        end
        
        return entries
    end)
    
    if success then
        return data
    else
        return {}
    end
end

-- ============================================================================
-- FUNÇÕES PÚBLICAS
-- ============================================================================

-- Mostra o Death Recap
function Morte.show_death_recap(damage_history, killer_name)
    Morte.state.show_death_recap = true
    Morte.state.death_recap_data = {
        damage_history = damage_history,
        killer_name = killer_name or "Desconhecido",
    }
    Morte.state.death_recap_timer = Morte.config.death_recap.display_time
end

-- Atualiza o timer do Death Recap
function Morte.update(dt)
    if Morte.state.show_death_recap then
        Morte.state.death_recap_timer = Morte.state.death_recap_timer - dt
        if Morte.state.death_recap_timer <= 0 then
            Morte.state.show_death_recap = false
            Morte.state.death_recap_data = nil
        end
    end
end

-- Desenha o Death Recap
function Morte.draw_death_recap(love)
    if not Morte.state.show_death_recap or not Morte.state.death_recap_data then
        return
    end
    
    local cfg = Morte.config.death_recap
    local colors = Morte.config.colors
    local data = Morte.state.death_recap_data
    
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local start_x = (screen_w - cfg.width) / 2
    local start_y = (screen_h - cfg.height) / 2
    
    -- Fundo
    love.graphics.setColor(colors.background)
    love.graphics.rectangle("fill", start_x, start_y, cfg.width, cfg.height, 8, 8)
    
    -- Borda (vermelha para indicar morte)
    love.graphics.setColor(0.8, 0.2, 0.2, 1)
    love.graphics.rectangle("line", start_x, start_y, cfg.width, cfg.height, 8, 8)
    
    -- Cabeçalho
    love.graphics.setColor(1, 0.3, 0.3, 1)
    love.graphics.print("VOCÊ MORREU!", start_x + 20, start_y + 15)
    
    love.graphics.setColor(colors.text)
    love.graphics.print("Abatido por: " .. data.killer_name, start_x + 20, start_y + 40)
    
    -- Cabeçalho da tabela de dano
    love.graphics.setColor(colors.text_dim)
    love.graphics.print("Histórico de Dano Recente:", start_x + 20, start_y + 70)
    love.graphics.print("Atacante", start_x + 20, start_y + 95)
    love.graphics.print("Habilidade", start_x + 150, start_y + 95)
    love.graphics.print("Dano", start_x + 280, start_y + 95)
    
    -- Linha separadora
    love.graphics.setColor(colors.border)
    love.graphics.line(start_x + 10, start_y + 115, 
                       start_x + cfg.width - 10, start_y + 115)
    
    -- Parse e exibir histórico de dano
    local damage_entries = parse_damage_history(data.damage_history)
    local y_offset = start_y + 125
    
    for i, entry in ipairs(damage_entries) do
        if i > cfg.max_entries then break end
        
        -- Cor baseada no tipo de dano
        local damage_type = entry.type or 0
        if damage_type == 0 then
            love.graphics.setColor(colors.damage_physical)
        elseif damage_type == 1 then
            love.graphics.setColor(colors.damage_magical)
        else
            love.graphics.setColor(colors.damage_true)
        end
        
        -- Atacante
        love.graphics.print("ID: " .. tostring(entry.attacker), start_x + 20, y_offset)
        
        -- Habilidade (0 = ataque básico)
        local ability_name = entry.ability == 0 and "Básico" or "Habilidade " .. tostring(entry.ability)
        love.graphics.print(ability_name, start_x + 150, y_offset)
        
        -- Valor do dano
        love.graphics.print(tostring(entry.damage), start_x + 280, y_offset)
        
        y_offset = y_offset + cfg.entry_height
    end
    
    -- Timer de respawn
    love.graphics.setColor(colors.text_dim)
    love.graphics.print(string.format("Respawn em %.1fs", Morte.state.death_recap_timer), 
                        start_x + 20, start_y + cfg.height - 30)
end

return Morte