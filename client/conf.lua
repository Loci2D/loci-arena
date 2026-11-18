function love.conf(t)
    local is_mobile = (love._os == "Android" or love._os == "iOS")

    t.identity = "loci-arena"
    t.window.title = "Loci Arena"
    t.window.fullscreen = is_mobile
    t.window.resizable = true
    t.window.highdpi = true
    if not is_mobile then
        t.window.width = 1280
        t.window.height = 720
        t.window.minwidth = 800
        t.window.minheight = 600
    end
    t.window.vsync = 1
    t.modules.joystick = true
    t.modules.audio = true
end
