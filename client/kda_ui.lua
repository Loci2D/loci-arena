-- KDA UI para Loci Arena (estilo Valorant - centralizado)
-- Exibe Kills, Deaths e K/D Ratio de TODOS os jogadores
-- Dados sincronizados do servidor

local kda_ui = {}

-- Configurações
local UI_WIDTH = 700
local UI_HEIGHT = 400
local PADDING = 20
local ROW_HEIGHT = 35

-- Estado
local show_kda = false

-- Fontes criadas uma vez (otimização)
local font_title = nil
local font_header = nil
local font_rank = nil
local font_normal = nil
local font_footer = nil

-- Inicializar fontes
local function init_fonts()
    if not font_title then
        font_title = love.graphics.newFont(24)
        font_header = love.graphics.newFont(13)
        font_rank = love.graphics.newFont(16)
        font_normal = love.graphics.newFont(12)
        font_footer = love.graphics.newFont(12)
    end
end

-- Mostrar UI
function kda_ui.show()
    show_kda = true
end

-- Esconder UI
function kda_ui.hide()
    show_kda = false
end

-- Verificar se está visível
function kda_ui.is_visible()
    return show_kda
end

-- Desenhar a UI (estilo Valorant - centralizado)
function kda_ui.draw(entities, my_entity)
    if not show_kda then
        return
    end

    -- Inicializar fontes na primeira chamada
    init_fonts()

    -- Usa a resolução virtual do jogo (1280x720) garantida pelo push:start()
    local sw, sh = 1280, 720
    local x = (sw - UI_WIDTH) / 2
    local y = (sh - UI_HEIGHT) / 2

    -- Fundo escuro translúcido (estilo Valorant)
    love.graphics.setColor(0.02, 0.02, 0.05, 0.98)
    love.graphics.rectangle("fill", x, y, UI_WIDTH, UI_HEIGHT, 12)

    -- Borda sutil
    love.graphics.setColor(0.2, 0.2, 0.25, 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, UI_WIDTH, UI_HEIGHT, 12)

    -- Linha decorativa no topo (estilo Valorant - roxa)
    love.graphics.setColor(0.5, 0.3, 0.7, 0.9)
    love.graphics.setLineWidth(4)
    love.graphics.line(x + 15, y + 18, x + UI_WIDTH - 15, y + 18)

    -- Título "SCOREBOARD"
    love.graphics.setColor(0.95, 0.95, 1, 1)
    love.graphics.setFont(font_title)
    love.graphics.print("SCOREBOARD", x + PADDING, y + PADDING + 8)

    -- Linha separadora
    love.graphics.setColor(0.25, 0.25, 0.3, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.line(x + PADDING, y + PADDING + 55, x + UI_WIDTH - PADDING, y + PADDING + 55)

    -- Cabeçalho da tabela
    love.graphics.setFont(font_header)
    love.graphics.setColor(0.5, 0.5, 0.6, 1)
    love.graphics.print("RANK", x + PADDING, y + PADDING + 70)
    love.graphics.print("TEAM", x + PADDING + 80, y + PADDING + 70)
    love.graphics.print("HERO", x + PADDING + 130, y + PADDING + 70)
    love.graphics.print("KILLS", x + PADDING + 270, y + PADDING + 70)
    love.graphics.print("DEATHS", x + PADDING + 370, y + PADDING + 70)
    love.graphics.print("K/D", x + PADDING + 470, y + PADDING + 70)

    -- Ordenar jogadores por ranking: Kills > Deaths <
    local sorted_entities = {}
    for i, ent in ipairs(entities) do
        table.insert(sorted_entities, ent)
    end

    table.sort(sorted_entities, function(a, b)
        local kills_a = tonumber(a.kills or (a.properties and a.properties["kills"]) or 0) or 0
        local kills_b = tonumber(b.kills or (b.properties and b.properties["kills"]) or 0) or 0
        local deaths_a = tonumber(a.deaths or (a.properties and a.properties["deaths"]) or 0) or 0
        local deaths_b = tonumber(b.deaths or (b.properties and b.properties["deaths"]) or 0) or 0

        -- Primeiro critério: mais kills
        if kills_a ~= kills_b then
            return kills_a > kills_b
        end
        -- Segundo critério: menos deaths
        return deaths_a < deaths_b
    end)

    -- Linhas de dados dos jogadores
    local row_y = y + PADDING + 105

    for rank, ent in ipairs(sorted_entities) do
        if row_y > y + UI_HEIGHT - 40 then
            break
        end

        local is_me = my_entity and ent.id == my_entity.id
        local kills = tonumber(ent.kills or (ent.properties and ent.properties["kills"]) or 0) or 0
        local deaths = tonumber(ent.deaths or (ent.properties and ent.properties["deaths"]) or 0) or 0
        local kd_ratio = deaths > 0 and (kills / deaths) or kills
        local team = ent:get("team", "?")
        local hero = string.upper(ent:get("character_name", "Unknown") or "Unknown")

        -- Highlight para o jogador atual (estilo Valorant)
        if is_me then
            love.graphics.setColor(0.1, 0.2, 0.3, 0.8)
            love.graphics.rectangle("fill", x + PADDING - 8, row_y - 8, UI_WIDTH - PADDING * 2 + 16, ROW_HEIGHT + 16, 6)
        end

        -- Rank
        love.graphics.setColor(0.7, 0.7, 0.8, 1)
        love.graphics.setFont(font_rank)
        love.graphics.print(tostring(rank) .. ".", x + PADDING, row_y)

        -- Time (azul/vermelho)
        if team == "1" then
            love.graphics.setColor(0.4, 0.6, 1.0, 1)
        elseif team == "2" then
            love.graphics.setColor(1.0, 0.4, 0.4, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.print(team, x + PADDING + 80, row_y)

        -- Herói
        love.graphics.setColor(0.9, 0.9, 0.9, 1)
        love.graphics.setFont(font_normal)
        love.graphics.print(hero, x + PADDING + 130, row_y)

        -- Kills (verde neon)
        love.graphics.setColor(0.0, 0.95, 0.5, 1)
        love.graphics.print(tostring(kills), x + PADDING + 270, row_y)

        -- Deaths (vermelho neon)
        love.graphics.setColor(0.95, 0.35, 0.35, 1)
        love.graphics.print(tostring(deaths), x + PADDING + 370, row_y)

        -- K/D Ratio (amarelo/branco)
        love.graphics.setColor(1, 1, 0.7, 1)
        love.graphics.print(string.format("%.2f", kd_ratio), x + PADDING + 470, row_y)

        row_y = row_y + ROW_HEIGHT
    end

    -- Footer com instruções
    love.graphics.setColor(0.4, 0.4, 0.5, 1)
    love.graphics.setFont(font_footer)
    love.graphics.print("Hold TAB for scoreboard", x + PADDING, y + UI_HEIGHT - 25)
end

return kda_ui
