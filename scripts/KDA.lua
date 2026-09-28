-- ============================================================================
-- KDA.LUA - Sistema de UI de Estatísticas (Cliente)
-- ============================================================================
-- Gerencia o painel de estatísticas (TAB) estilo LoL/Valorant
-- ============================================================================

local KDA = {}

-- ============================================================================
-- CONFIGURAÇÕES
-- ============================================================================
KDA.config = {
    colors = {
        background = {0, 0, 0, 0.85},
        border = {0.4, 0.6, 0.8, 1},
        text = {1, 1, 1, 1},
        text_dim = {0.7, 0.7, 0.7, 1},
        highlight = {1, 0.84, 0, 1}, -- Dourado para jogador local
        team_red = {0.8, 0.3, 0.3, 1},
        team_blue = {0.3, 0.3, 0.8, 1},
        team_neutral = {0.3, 0.8, 0.4, 1},
    },
    
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
    }
}

-- ============================================================================
-- ESTADO
-- ============================================================================
KDA.state = {
    show_scoreboard = false,
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
        return KDA.config.colors.team_red
    elseif team == "blue" or team == "2" then
        return KDA.config.colors.team_blue
    else
        return KDA.config.colors.team_neutral
    end
end

-- ============================================================================
-- FUNÇÕES PÚBLICAS
-- ============================================================================

-- Desenha o painel de estatísticas (TAB)
function KDA.draw_scoreboard(loci, love)
    if not KDA.state.show_scoreboard then return end
    
    local cfg = KDA.config.scoreboard
    local colors = KDA.config.colors
    
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
        
        if y_offset > start_y + cfg.height - 10 then
            break
        end
    end
end

-- Manipula tecla TAB pressionada
function KDA.handle_keypressed(key)
    if key == "tab" then
        KDA.state.show_scoreboard = true
    end
end

-- Manipula tecla TAB solta
function KDA.handle_keyreleased(key)
    if key == "tab" then
        KDA.state.show_scoreboard = false
    end
end

return KDA