-- Virtual Joystick System - Sistema de controles virtuais simplificado
local VirtualJoystick = {}
local push = nil

function VirtualJoystick.set_push(push_module)
    push = push_module
end

-- Configurações do botão de habilidade 1 (ataque básico - centro do canto inferior direito)
local SKILL_1_BUTTON_CONFIG = {
    x_ratio = 0.90,        -- Centro em 90% da largura
    y_ratio = 0.85,        -- Centro em 85% da altura
    radius = 75,           -- Raio do botão (maior)
    color_bg = {0.4, 0.2, 0.2, 0.6},
    color_pressed = {0.8, 0.3, 0.3, 0.9},
    skill_id = 1
}

-- Configurações do botão de habilidade 2 (topo do semi-círculo, acima do botão 1)
local SKILL_2_BUTTON_CONFIG = {
    x_ratio = 0.90,        -- Centro em 90% da largura (mesma coluna do botão 1)
    y_ratio = 0.60,        -- Centro em 60% da altura (acima do botão 1)
    radius = 50,           -- Raio do botão
    color_bg = {0.2, 0.4, 0.6, 0.6},
    color_pressed = {0.3, 0.7, 0.9, 0.9},
    skill_id = 2
}

-- Configurações do botão de habilidade 3 (meio do semi-círculo, diagonal acima-esquerda)
local SKILL_3_BUTTON_CONFIG = {
    x_ratio = 0.80,        -- Centro em 80% da largura (à esquerda do botão 1)
    y_ratio = 0.68,        -- Centro em 65% da altura (meio do arco)
    radius = 50,           -- Raio do botão
    color_bg = {0.6, 0.2, 0.6, 0.6},
    color_pressed = {0.9, 0.3, 0.9, 0.9},
    skill_id = 3
}

-- Configurações do botão de habilidade 4 (base do semi-círculo, à esquerda do botão 1)
local SKILL_4_BUTTON_CONFIG = {
    x_ratio = 0.75,        -- Centro em 72% da largura (mais à esquerda)
    y_ratio = 0.85,        -- Centro em 85% da altura (mesma linha do botão 1)
    radius = 50,           -- Raio do botão
    color_bg = {0.6, 0.6, 0.2, 0.6},
    color_pressed = {0.9, 0.9, 0.3, 0.9},
    skill_id = 4
}

-- Configurações do joystick de movimento
local MOVE_JOYSTICK_CONFIG = {
    radius = 75,
    color_bg = {1.0, 1.0, 1.0, 0.5},
    color_handle = {1.0, 1.0, 1.0, 0.8},
    dynamic = true
}

-- Classe base para controles
local Control = {}
Control.__index = Control

function Control.new(config)
    local self = setmetatable({}, Control)
    self.config = config
    self.active = false
    self.touch_id = nil
    self.center_x = 0
    self.center_y = 0
    self.last_action_time = 0
    self.action_cooldown = 0.5
    return self
end

function Control:update_pos(w, h)
    if self.config.x_ratio then
        self.center_x = w * self.config.x_ratio
        self.center_y = h * self.config.y_ratio
    end
end

function Control:hit_test(x, y)
    local dist = math.sqrt((x - self.center_x)^2 + (y - self.center_y)^2)
    return dist <= (self.config.radius or self.config.touch_radius)
end

function Control:can_trigger_action(t)
    return t - self.last_action_time >= self.action_cooldown
end

function Control:trigger_action(t)
    self.last_action_time = t
end

-- Joystick de movimento
local Joystick = {}
setmetatable(Joystick, {__index = Control})
Joystick.__index = Joystick

function Joystick.new(config)
    local self = Control.new(config)
    setmetatable(self, Joystick)
    self.handle_x = 0
    self.handle_y = 0
    self.dx = 0
    self.dy = 0
    self.dynamic = config.dynamic
    return self
end

function Joystick:handle_press(x, y, touch_id, w, h)
    if self.dynamic then
        if x < w/2 and y > h/2 then
            self.active = true
            self.touch_id = touch_id
            self.center_x, self.center_y = x, y
            self.handle_x, self.handle_y = x, y
            self:update_vector()
            return true
        end
    else
        if self:hit_test(x, y) then
            self.active = true
            self.touch_id = touch_id
            self.handle_x, self.handle_y = x, y
            self:update_vector()
            return true
        end
    end
    return false
end

function Joystick:handle_move(x, y, touch_id)
    if self.active and self.touch_id == touch_id then
        self.handle_x, self.handle_y = x, y
        self:update_vector()
        return true
    end
    return false
end

function Joystick:handle_release(touch_id)
    if self.active and self.touch_id == touch_id then
        self.active = false
        self.touch_id = nil
        self.dx, self.dy = 0, 0
        return true
    end
    return false
end

function Joystick:update_vector()
    local dx, dy = self.handle_x - self.center_x, self.handle_y - self.center_y
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist > self.config.radius then
        local angle = math.atan2(dy, dx)
        self.handle_x = self.center_x + math.cos(angle) * self.config.radius
        self.handle_y = self.center_y + math.sin(angle) * self.config.radius
        dx, dy = self.handle_x - self.center_x, self.handle_y - self.center_y
        dist = self.config.radius
    end
    self.dx, self.dy = dist > 0 and dx/self.config.radius or 0, dist > 0 and dy/self.config.radius or 0
end

function Joystick:get_vector()
    return self.dx, self.dy
end

function Joystick:draw()
    if self.dynamic and not self.active then return end
    love.graphics.setColor(self.config.color_bg)
    love.graphics.circle("fill", self.center_x, self.center_y, self.config.radius)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.circle("line", self.center_x, self.center_y, self.config.radius)
    love.graphics.setColor(self.config.color_handle)
    love.graphics.circle("fill", self.handle_x, self.handle_y, self.config.radius * 0.4)
    if self.active and (math.abs(self.dx) > 0.1 or math.abs(self.dy) > 0.1) then
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.line(self.center_x, self.center_y, self.handle_x, self.handle_y)
    end
end

-- Botão de ação
local ActionButton = {}
setmetatable(ActionButton, {__index = Control})
ActionButton.__index = ActionButton

function ActionButton.new(config)
    local self = Control.new(config)
    setmetatable(self, ActionButton)
    return self
end

function ActionButton:handle_press(x, y, touch_id)
    if self:hit_test(x, y) then
        self.active = true
        self.touch_id = touch_id
        return true
    end
    return false
end

function ActionButton:handle_move(x, y, touch_id)
    if self.active and self.touch_id == touch_id and not self:hit_test(x, y) then
        self.active = false
        self.touch_id = nil
    end
    return self.active
end

function ActionButton:handle_release(touch_id)
    if self.active and self.touch_id == touch_id then
        self.active = false
        self.touch_id = nil
        return true
    end
    return false
end

function ActionButton:draw()
    love.graphics.setColor(self.active and self.config.color_pressed or self.config.color_bg)
    love.graphics.circle("fill", self.center_x, self.center_y, self.config.radius)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.circle("line", self.center_x, self.center_y, self.config.radius)

    -- Desenhar o número da habilidade
    love.graphics.setColor(1, 1, 1, 0.9)
    local font = love.graphics.getFont()
    local label = tostring(self.config.skill_id or 1)
    local tw = font:getWidth(label)
    love.graphics.print(label, self.center_x - tw / 2, self.center_y - font:getHeight() / 2)
end

-- Sistema principal
local move_joystick = Joystick.new(MOVE_JOYSTICK_CONFIG)
local skill_1_button = ActionButton.new(SKILL_1_BUTTON_CONFIG)
local skill_2_button = ActionButton.new(SKILL_2_BUTTON_CONFIG)
local skill_3_button = ActionButton.new(SKILL_3_BUTTON_CONFIG)
local skill_4_button = ActionButton.new(SKILL_4_BUTTON_CONFIG)
local MOUSE_ID = -1

-- Dimensões virtuais do jogo
local game_w, game_h = 1280, 720

-- Conversão de coordenadas da janela real para coordenadas do jogo virtual
local function to_game(x, y)
    if push then
        return push:toGame(x, y)
    end
    return x, y
end

-- API pública
function VirtualJoystick.update(w, h)
    game_w = w or game_w
    game_h = h or game_h
    move_joystick:update_pos(game_w, game_h)
    skill_1_button:update_pos(game_w, game_h)
    skill_2_button:update_pos(game_w, game_h)
    skill_3_button:update_pos(game_w, game_h)
    skill_4_button:update_pos(game_w, game_h)
end

function VirtualJoystick.update_with_game_dimensions(w, h)
    VirtualJoystick.update(w, h)
end

function VirtualJoystick.handle_touchpress(id, x, y)
    local gx, gy = to_game(x, y)
    if not gx or not gy then return false end
    return move_joystick:handle_press(gx, gy, id, game_w, game_h) or
           skill_1_button:handle_press(gx, gy, id) or
           skill_2_button:handle_press(gx, gy, id) or
           skill_3_button:handle_press(gx, gy, id) or
           skill_4_button:handle_press(gx, gy, id)
end

function VirtualJoystick.handle_touchmove(id, x, y)
    local gx, gy = to_game(x, y)
    if not gx or not gy then return false end
    return move_joystick:handle_move(gx, gy, id) or
           skill_1_button:handle_move(gx, gy, id) or
           skill_2_button:handle_move(gx, gy, id) or
           skill_3_button:handle_move(gx, gy, id) or
           skill_4_button:handle_move(gx, gy, id)
end

function VirtualJoystick.handle_touchrelease(id)
    return move_joystick:handle_release(id) or
           skill_1_button:handle_release(id) or
           skill_2_button:handle_release(id) or
           skill_3_button:handle_release(id) or
           skill_4_button:handle_release(id)
end

function VirtualJoystick.handle_mousepressed(x, y, button)
    if button ~= 1 then return false end
    return VirtualJoystick.handle_touchpress(MOUSE_ID, x, y)
end

function VirtualJoystick.handle_mousemoved(x, y)
    return VirtualJoystick.handle_touchmove(MOUSE_ID, x, y)
end

function VirtualJoystick.handle_mousereleased(x, y, button)
    if button ~= 1 then return false end
    return VirtualJoystick.handle_touchrelease(MOUSE_ID)
end

function VirtualJoystick.get_move_vector()
    return move_joystick:get_vector()
end

function VirtualJoystick.is_move_active()
    return move_joystick.active
end

function VirtualJoystick.is_skill_1_active()
    return skill_1_button.active
end

function VirtualJoystick.can_trigger_skill_1(t)
    return skill_1_button:can_trigger_action(t)
end

function VirtualJoystick.trigger_skill_1(t)
    skill_1_button:trigger_action(t)
end

function VirtualJoystick.is_skill_2_active()
    return skill_2_button.active
end

function VirtualJoystick.can_trigger_skill_2(t)
    return skill_2_button:can_trigger_action(t)
end

function VirtualJoystick.trigger_skill_2(t)
    skill_2_button:trigger_action(t)
end

function VirtualJoystick.is_skill_3_active()
    return skill_3_button.active
end

function VirtualJoystick.can_trigger_skill_3(t)
    return skill_3_button:can_trigger_action(t)
end

function VirtualJoystick.trigger_skill_3(t)
    skill_3_button:trigger_action(t)
end

function VirtualJoystick.is_skill_4_active()
    return skill_4_button.active
end

function VirtualJoystick.can_trigger_skill_4(t)
    return skill_4_button:can_trigger_action(t)
end

function VirtualJoystick.trigger_skill_4(t)
    skill_4_button:trigger_action(t)
end

function VirtualJoystick.draw()
    move_joystick:draw()
    skill_1_button:draw()
    skill_2_button:draw()
    skill_3_button:draw()
    skill_4_button:draw()
end

return VirtualJoystick
