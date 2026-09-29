function love.conf(t)
    t.identity = "loci-arena"
    t.window.title = "Loci Arena"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 800
    t.window.minheight = 600
    t.window.vsync = 1
    t.window.backgroundupdates = true
    t.modules.joystick = true
    t.modules.audio = true
end
