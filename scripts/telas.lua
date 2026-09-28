-- ============================================================================
-- TELAS.LUA - Sistema de UI para loci2d
-- ============================================================================
-- Contém:
-- - Painel de Estatísticas (TAB) estilo LoL/Valorant
-- - Death Recap (Resumo de Dano/Morte)
-- ============================================================================

local telas = {}

-- ============================================================================
-- CONFIGURAÇÕES GERAIS
-- ============================================================================
telas.config = {
    -- Cores
    colors = {
        background = {0, 0, 0, 0.85},
        border = {0.4, 0.6, 0.8, 1},
        text = {1, 1, 1, 1},
        text_dim = {0.7, 0.7, 0.7, 1},
        highlight = {1, 0.84, 0, 1}, -- Dourado para jogador local
        team_red = {0.8, 0.3, 0.3, 1},
        team_blue = {0.3, 0.3, 0.8, 1},
        team_neutral = {0.3, 0.8, 0.4, 1},
        damage_physical = {0.9, 0.6, 0.3, 1},
        damage_magical = {0.6, 0.3, 0.9, 1},
        damage_true = {1, 0.2, 0.2, 1},
    },
    
    -- Scoreboard
    scoreboard = {
        width = 500,
        height = 300,
        header_height = 60,
        row_height = 25,
        columns = {
            name = {x = 20, width = 150, label = "Jogador"},
            team = {x = 180, width = 80, label = "Time"},
            kills = {x = 280, width = 40, label = "K"},
            deaths = {x = 340, width = 40, label = "D"},
            assists = {x = 400, width = 40, label = "A"},
        }
    },
    
    -- Death Recap
    death_recap = {
        width = 400,
        height = 350,
        entry_height = 30,
        max_entries = 10,
    }
}

-- ============================================================================
-- ESTADO INTERNO
-- ============================================================================
telas.state = {
    show_scoreboard = false,
    show_death_recap = false,
    death_recap_data = nil,
    death_recap_timer = 0,
}

-- ============================================================================
-- FUNÇÕES AUXILIARES
-- ============================================================================
local function safe_get(entity, key, default)
    if not entity then return default end
    local val = entity:get(key, default)
    if val == nil then return default end
    return val
end

local function get_team_color(team)
    if team == "red" or team == "1" then
        return telas.config.colors.team_red
    elseif team == "blue" or team == "2" then
        return telas.config.colors.team_blue
    else
        return telas.config.colors.team_neutral
    end
end

local function parse_damage_history(history_str)
    if not history_str or history_str == "" then return {} end
    
    local success, data = pcall(function()
        -- Remove espaços extras e normaliza
        history_str = history_str:gsub("%s+", "")
        
        -- Parse formato: [{attacker:1,damage:50,ability:2,type:0,time:1.2},...]
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
        print("[Telas] Erro ao parsear damage_history:", data)
        return {}
    end
end

-- ============================================================================
-- PAINEL DE ESTATÍSTICAS (TAB)
-- ============================================================================
function telas.draw_scoreboard(loci, love)
    if not telas.state.show_scoreboard then return end
    
    local cfg = telas.config.scoreboard
    local colors = telas.config.colors
    
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local start_x = (screen_w - cfg.width) / 2
    local start_y = (screen_h - cfg.height) / 2
    
    -- Fundo
    love.graphics.setColor(colors.background)
    love.graphics.rectangle("fill", start_x, start_y, cfg.width, cfg.height, 8, 8)
    
    -- Borda
    love.graphics.setColor(colors.border)
    love.graphics.rectangle("line", start_x, start_y, cfg.width, cfg.height, 8, 8)
    
    -- Cabeçalho
    love.graphics.setColor(colors.text)
    love.graphics.print("PLACAR DA PARTIDA (TAB)", start_x + 20, start_y + 15)
    
    -- Cabeçalho das colunas
    love.graphics.setColor(colors.text_dim)
    for col_name, col in pairs(cfg.columns) do
        love.graphics.print(col.label, start_x + col.x, start_y + 45)
    end
    
    -- Linha separadora
    love.graphics.setColor(colors.border)
    love.graphics.line(start_x + 10, start_y + cfg.header_height - 5, 
                       start_x + cfg.width - 10, start_y + cfg.header_height - 5)
    
    -- Linhas de jogadores
    local entities = loci.get_entities()
    local y_offset = start_y + cfg.header_height
    
    -- Ordenar por kills (decrescente)
    table.sort(entities, function(a, b)
        local kills_a = safe_get(a, "kills", 0)
        local kills_b = safe_get(b, "kills", 0)
        return kills_a > kills_b
    end)
    
    for _, ent in ipairs(entities) do
        -- Apenas mostrar entidades que têm estatísticas de jogador
        local kills = safe_get(ent, "kills", 0)
        local deaths = safe_get(ent, "deaths", 0)
        local assists = safe_get(ent, "assists", 0)
        local team = safe_get(ent, "team", "neutro")
        local name = ent.blueprint or ("Player #" .. tostring(ent.id))
        
        -- Cor do nome baseada no time
        love.graphics.setColor(get_team_color(team))
        
        -- Destaque para jogador local
        if ent:is_local_player() then
            love.graphics.setColor(colors.highlight)
        end
        
        -- Nome
        love.graphics.print(name, start_x + cfg.columns.name.x, y_offset)
        
        -- Time
        love.graphics.setColor(get_team_color(team))
        love.graphics.print(team, start_x + cfg.columns.team.x, y_offset)
        
        -- Estatísticas
        love.graphics.setColor(colors.text)
        love.graphics.print(tostring(kills), start_x + cfg.columns.kills.x, y_offset)
        love.graphics.print(tostring(deaths), start_x + cfg.columns.deaths.x, y_offset)
        love.graphics.print(tostring(assists), start_x + cfg.columns.assists.x, y_offset)
        
        y_offset = y_offset + cfg.row_height
        
        -- Limitar número de linhas visíveis
        if y_offset > start_y + cfg.height - 10 then
            break
        end
    end
end

function telas.handle_keypressed(key, loci)
    if key == "tab" then
        telas.state.show_scoreboard = true
    end
end

function telas.handle_keyreleased(key, loci)
    if key == "tab" then
        telas.state.show_scoreboard = false
    end
end

-- ============================================================================
-- DEATH RECAP (RESUMO DE MORTE)
-- ============================================================================
function telas.show_death_recap(damage_history, killer_name)
    telas.state.show_death_recap = true
    telas.state.death_recap_data = {
        damage_history = damage_history,
        killer_name = killer_name or "Desconhecido",
    }
    telas.state.death_recap_timer = 5.0 -- Mostrar por 5 segundos
end

function telas.update_death_recap(dt)
    if telas.state.show_death_recap then
        telas.state.death_recap_timer = telas.state.death_recap_timer - dt
        if telas.state.death_recap_timer <= 0 then
            telas.state.show_death_recap = false
            telas.state.death_recap_data = nil
        end
    end
end

function telas.draw_death_recap(love)
    if not telas.state.show_death_recap or not telas.state.death_recap_data then
        return
    end
    
    local cfg = telas.config.death_recap
    local colors = telas.config.colors
    local data = telas.state.death_recap_data
    
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
    love.graphics.print(string.format("Respawn em %.1fs", telas.state.death_recap_timer), 
                        start_x + 20, start_y + cfg.height - 30)
end

-- ============================================================================
-- INTEGRAÇÃO COM CLIENTE LOVE2D
-- ============================================================================
function telas.update(dt)
    telas.update_death_recap(dt)
end

function telas.draw(loci, love)
    telas.draw_scoreboard(loci, love)
    telas.draw_death_recap(love)
end

-- ============================================================================
-- EXPORTAR
-- ============================================================================
return telas