-- ConnectScreen - Tela de conexao mobile-friendly (1280x720 virtual)
-- Suporta presets rapidos, teclado virtual (Android/iOS), feedback de erro e Session Resume.

local ConnectScreen = {}

local PRESETS = {
    { label = "IFMS (10.3.17.201)", ip = "10.3.17.201", port = 8080 },
    { label = "LAN (192.168.0.2)", ip = "192.168.0.2", port = 8080 },
    { label = "Localhost (127.0.0.1)", ip = "127.0.0.1", port = 8080 },
}

local state = {
    ip = "127.0.0.1",
    port = "8080",
    player_name = "Player",
    active_field = nil,
    status_msg = "",
    is_error = false,
    is_connecting = false,
    can_resume = false,
    on_connect = nil,
    on_resume = nil,
}

local fonts = {
    title = nil,
    label = nil,
    input = nil,
    small = nil,
}

local function ensure_fonts()
    if not (love and love.graphics and love.graphics.newFont) then return end
    if not fonts.title then
        fonts.title = love.graphics.newFont(28)
        fonts.label = love.graphics.newFont(15)
        fonts.input = love.graphics.newFont(18)
        fonts.small = love.graphics.newFont(13)
    end
end

-- Layout fixo no espaco virtual 1280x720
local CARD_W, CARD_H = 740, 440
local CARD_X, CARD_Y = (1280 - CARD_W) / 2, (720 - CARD_H) / 2

local RECTS = {
    presets = {
        { x = CARD_X + 36,  y = CARD_Y + 86, w = 212, h = 38 },
        { x = CARD_X + 264, y = CARD_Y + 86, w = 212, h = 38 },
        { x = CARD_X + 492, y = CARD_Y + 86, w = 212, h = 38 },
    },
    ip_input   = { x = CARD_X + 36,  y = CARD_Y + 162, w = 470, h = 44 },
    port_input = { x = CARD_X + 524, y = CARD_Y + 162, w = 180, h = 44 },
    name_input = { x = CARD_X + 36,  y = CARD_Y + 242, w = 668, h = 44 },
    btn_connect = { x = CARD_X + 36,  y = CARD_Y + 362, w = 320, h = 50 },
    btn_resume  = { x = CARD_X + 384, y = CARD_Y + 362, w = 320, h = 50 },
}

local function point_in_rect(px, py, r)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

local function set_text_input(enabled)
    if not (love and love.keyboard and love.keyboard.setTextInput) then return end
    pcall(love.keyboard.setTextInput, enabled == true)
end

function ConnectScreen.init(opts)
    opts = opts or {}
    state.ip = tostring(opts.initial_ip or "127.0.0.1")
    state.port = tostring(opts.initial_port or 8080)
    state.player_name = tostring(opts.initial_name or "Player")
    state.active_field = nil
    state.status_msg = tostring(opts.status_msg or "")
    state.is_error = opts.is_error == true
    state.is_connecting = false
    state.can_resume = opts.can_resume == true
    state.on_connect = opts.on_connect
    state.on_resume = opts.on_resume
    set_text_input(false)
end

function ConnectScreen.set_status(msg, is_error, is_connecting)
    state.status_msg = tostring(msg or "")
    state.is_error = is_error == true
    state.is_connecting = is_connecting == true
end

function ConnectScreen.set_can_resume(can_resume)
    state.can_resume = can_resume == true
end

function ConnectScreen.get_values()
    return state.ip, tonumber(state.port) or 8080, state.player_name
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function trigger_connect()
    if state.is_connecting then return end
    local ip = trim(state.ip)
    local port = tonumber(trim(state.port))
    local name = trim(state.player_name)

    if ip == "" then
        ConnectScreen.set_status("Informe um IP ou host valido.", true, false)
        return
    end
    if not port or port < 1 or port > 65535 then
        ConnectScreen.set_status("Porta invalida (use 1 a 65535).", true, false)
        return
    end
    if name == "" then
        name = "Player"
        state.player_name = name
    end

    state.active_field = nil
    set_text_input(false)
    if state.on_connect then
        state.on_connect(ip, math.floor(port), name)
    end
end

local function trigger_resume()
    if state.is_connecting or not state.can_resume then return end
    local ip = trim(state.ip)
    local port = tonumber(trim(state.port)) or 8080
    local name = trim(state.player_name)
    state.active_field = nil
    set_text_input(false)
    if state.on_resume then
        state.on_resume(ip, math.floor(port), name)
    end
end

function ConnectScreen.handle_press(gx, gy)
    if not gx or not gy then return false end

    for i, preset in ipairs(PRESETS) do
        if point_in_rect(gx, gy, RECTS.presets[i]) then
            state.ip = preset.ip
            state.port = tostring(preset.port)
            state.active_field = nil
            set_text_input(false)
            ConnectScreen.set_status("Preset selecionado: " .. preset.label, false, false)
            return true
        end
    end

    if point_in_rect(gx, gy, RECTS.ip_input) then
        state.active_field = "ip"
        set_text_input(true, RECTS.ip_input)
        return true
    elseif point_in_rect(gx, gy, RECTS.port_input) then
        state.active_field = "port"
        set_text_input(true, RECTS.port_input)
        return true
    elseif point_in_rect(gx, gy, RECTS.name_input) then
        state.active_field = "name"
        set_text_input(true, RECTS.name_input)
        return true
    elseif point_in_rect(gx, gy, {
        x = RECTS.btn_connect.x,
        y = RECTS.btn_connect.y,
        w = state.can_resume and RECTS.btn_connect.w or (CARD_W - 72),
        h = RECTS.btn_connect.h
    }) then
        trigger_connect()
        return true
    elseif state.can_resume and point_in_rect(gx, gy, RECTS.btn_resume) then
        trigger_resume()
        return true
    end

    state.active_field = nil
    set_text_input(false)
    return false
end

function ConnectScreen.textinput(text)
    if not state.active_field or not text or text == "" then return false end
    if state.active_field == "ip" then
        if #state.ip < 64 and text:match("^[%w%.%-:]+$") then
            state.ip = state.ip .. text
            return true
        end
    elseif state.active_field == "port" then
        if #state.port < 5 and text:match("^%d+$") then
            state.port = state.port .. text
            return true
        end
    elseif state.active_field == "name" then
        if #state.player_name < 24 and not text:match("[%c]") then
            state.player_name = state.player_name .. text
            return true
        end
    end
    return false
end

local function pop_last_char(str)
    if #str == 0 then return "" end
    -- Remove ultimo byte UTF-8 completo
    local i = #str
    while i > 1 and str:byte(i) >= 128 and str:byte(i) < 192 do
        i = i - 1
    end
    return str:sub(1, i - 1)
end

function ConnectScreen.keypressed(key)
    if key == "backspace" and state.active_field then
        if state.active_field == "ip" then
            state.ip = pop_last_char(state.ip)
        elseif state.active_field == "port" then
            state.port = pop_last_char(state.port)
        elseif state.active_field == "name" then
            state.player_name = pop_last_char(state.player_name)
        end
        return true
    elseif key == "tab" then
        local order = { "ip", "port", "name" }
        local next_idx = 1
        for i, f in ipairs(order) do
            if state.active_field == f then
                next_idx = (i % #order) + 1
                break
            end
        end
        state.active_field = order[next_idx]
        local r = RECTS[state.active_field .. "_input"]
        set_text_input(true, r)
        return true
    elseif key == "return" or key == "kpenter" then
        trigger_connect()
        return true
    end
    return false
end

local function draw_input(rect, label, value, is_active)
    love.graphics.setFont(fonts.label)
    love.graphics.setColor(0.75, 0.8, 0.9, 1)
    love.graphics.print(label, rect.x, rect.y - 22)

    love.graphics.setColor(0.08, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6, 6)

    if is_active then
        love.graphics.setColor(0.35, 0.7, 1.0, 1)
        love.graphics.setLineWidth(2)
    else
        love.graphics.setColor(0.28, 0.34, 0.45, 0.9)
        love.graphics.setLineWidth(1)
    end
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 6, 6)

    love.graphics.setFont(fonts.input)
    love.graphics.setColor(0.95, 0.97, 1.0, 1)
    local display = is_active and (value .. "_") or value
    love.graphics.print(display, rect.x + 12, rect.y + 11)
end

function ConnectScreen.draw(sw, sh)
    ensure_fonts()
    local prev_font = love.graphics.getFont()
    local prev_lw = love.graphics.getLineWidth and love.graphics.getLineWidth() or 1

    -- Fundo escuro da arena
    love.graphics.setColor(0.05, 0.06, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Card central
    love.graphics.setColor(0.11, 0.13, 0.19, 0.98)
    love.graphics.rectangle("fill", CARD_X, CARD_Y, CARD_W, CARD_H, 12, 12)
    love.graphics.setColor(0.25, 0.35, 0.55, 0.85)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", CARD_X, CARD_Y, CARD_W, CARD_H, 12, 12)

    -- Titulo
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(0.95, 0.95, 1, 1)
    love.graphics.printf("LOCI ARENA", CARD_X, CARD_Y + 22, CARD_W, "center")

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.65, 0.72, 0.85, 1)
    love.graphics.print("Presets rapidos de servidor:", CARD_X + 36, CARD_Y + 64)

    -- Presets
    for i, preset in ipairs(PRESETS) do
        local r = RECTS.presets[i]
        local selected = (state.ip == preset.ip and tonumber(state.port) == preset.port)
        love.graphics.setColor(selected and {0.2, 0.38, 0.65, 0.95} or {0.16, 0.2, 0.28, 0.95})
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setColor(selected and {0.45, 0.75, 1.0, 1} or {0.3, 0.36, 0.48, 0.9})
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setColor(0.95, 0.97, 1, 1)
        love.graphics.printf(preset.label, r.x, r.y + 11, r.w, "center")
    end

    -- Inputs
    draw_input(RECTS.ip_input, "IP / Host do Servidor", state.ip, state.active_field == "ip")
    draw_input(RECTS.port_input, "Porta", state.port, state.active_field == "port")
    draw_input(RECTS.name_input, "Nome do Jogador", state.player_name, state.active_field == "name")

    -- Status / erro
    if state.status_msg ~= "" then
        love.graphics.setFont(fonts.small)
        if state.is_error then
            love.graphics.setColor(0.98, 0.35, 0.35, 1)
        elseif state.is_connecting then
            love.graphics.setColor(0.95, 0.85, 0.35, 1)
        else
            love.graphics.setColor(0.55, 0.85, 0.95, 1)
        end
        love.graphics.printf(state.status_msg, CARD_X + 36, CARD_Y + 312, CARD_W - 72, "center")
    end

    -- Botao Conectar
    local bc = RECTS.btn_connect
    local connect_w = state.can_resume and bc.w or (CARD_W - 72)
    love.graphics.setColor(state.is_connecting and {0.2, 0.3, 0.45, 0.8} or {0.18, 0.58, 0.35, 1})
    love.graphics.rectangle("fill", bc.x, bc.y, connect_w, bc.h, 8, 8)
    love.graphics.setFont(fonts.input)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(state.is_connecting and "CONECTANDO..." or "CONECTAR", bc.x, bc.y + 14, connect_w, "center")

    -- Botao Retomar Sessao (quando ha token valido)
    if state.can_resume then
        local br = RECTS.btn_resume
        love.graphics.setColor(state.is_connecting and {0.2, 0.25, 0.35, 0.7} or {0.22, 0.45, 0.78, 1})
        love.graphics.rectangle("fill", br.x, br.y, br.w, br.h, 8, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("RETOMAR SESSAO", br.x, br.y + 14, br.w, "center")
    end

    if prev_font then love.graphics.setFont(prev_font) end
    love.graphics.setLineWidth(prev_lw)
    love.graphics.setColor(1, 1, 1, 1)
end

return ConnectScreen
