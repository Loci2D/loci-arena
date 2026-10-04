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
    love.graphics.setFont(love.graphics.newFont(24))
    love.graphics.print("SCOREBOARD", x + PADDING, y + PADDING + 8)

    -- Linha separadora
    love.graphics.setColor(0.25, 0.25, 0.3, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.line(x + PADDING, y + PADDING + 55, x + UI_WIDTH - PADDING, y + PADDING + 55)

    -- Cabeçalho da tabela
    love.graphics.setFont(love.graphics.newFont(13))
    love.graphics.setColor(0.5, 0.5, 0.6, 1)
    love.graphics.print("RANK", x + PADDING, y + PADDING + 70)
    love.graphics.print("PLAYER", x + PADDING + 80, y + PADDING + 70)
    love.graphics.print("KILLS", x + PADDING + 220, y + PADDING + 70)
    love.graphics.print("DEATHS", x + PADDING + 320, y + PADDING + 70)
    love.graphics.print("K/D", x + PADDING + 420, y + PADDING + 70)

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

        -- Highlight para o jogador atual (estilo Valorant)
        if is_me then
            love.graphics.setColor(0.1, 0.2, 0.3, 0.8)
            love.graphics.rectangle("fill", x + PADDING - 8, row_y - 8, UI_WIDTH - PADDING * 2 + 16, ROW_HEIGHT + 16, 6)
        end

        -- Rank
        love.graphics.setColor(0.7, 0.7, 0.8, 1)
        love.graphics.setFont(love.graphics.newFont(16))
        love.graphics.print(tostring(rank) .. ".", x + PADDING, row_y)

        -- Nome do jogador
        love.graphics.setColor(1, 1, 1, 1)
        local label = is_me and "YOU" or ("P" .. tostring(ent.id))
        love.graphics.print(label, x + PADDING + 80, row_y)

        -- Kills (verde neon)
        love.graphics.setColor(0.0, 0.95, 0.5, 1)
        love.graphics.print(tostring(kills), x + PADDING + 220, row_y)

        -- Deaths (vermelho neon)
        love.graphics.setColor(0.95, 0.35, 0.35, 1)
        love.graphics.print(tostring(deaths), x + PADDING + 320, row_y)

        -- K/D Ratio (amarelo/branco)
        love.graphics.setColor(1, 1, 0.7, 1)
        love.graphics.print(string.format("%.2f", kd_ratio), x + PADDING + 420, row_y)

        row_y = row_y + ROW_HEIGHT
    end

    -- Footer com instruções
    love.graphics.setColor(0.4, 0.4, 0.5, 1)
    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.print("Hold TAB for scoreboard", x + PADDING, y + UI_HEIGHT - 25)
end

return kda_ui
