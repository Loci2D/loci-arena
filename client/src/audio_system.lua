-- Sistema de Áudio (SFX) para Loci Arena
-- Carrega arquivos .wav de client/assets/audio/ e gera placeholders procedurais se ausentes.

local audio_system = {}

local AUDIO_DIR_CANDIDATES = {
    "assets/audio/",
    "client/assets/audio/",
}

local SOUND_CATALOG = {
    slash          = { file = "slash.wav",          freq = 400, duration = 0.10, volume = 0.8 },
    fury_reward    = { file = "fury_reward.wav",    freq = 600, duration = 0.20, volume = 0.8 },
    whirlwind_dash = { file = "whirlwind_dash.wav", freq = 500, duration = 0.25, volume = 0.8 },
    blade_throw    = { file = "blade_throw.wav",    freq = 300, duration = 0.30, volume = 0.8 },
    fireball       = { file = "fireball.wav",       freq = 220, duration = 0.35, volume = 0.85 },
    hit            = { file = "hit.wav",            freq = 200, duration = 0.08, volume = 0.7 },
    critical       = { file = "critical.wav",       freq = 320, duration = 0.15, volume = 0.9 },
    shield_hit     = { file = "shield_hit.wav",     freq = 260, duration = 0.10, volume = 0.75 },
    death          = { file = "death.wav",          freq = 150, duration = 0.40, volume = 0.9 },
}

local SKILL_SOUND_MAP = {
    slash          = "slash",
    fury_reward    = "fury_reward",
    whirlwind_dash = "whirlwind_dash",
    blade_throw    = "blade_throw",
    fireball       = "fireball",
    shield         = "shield_hit",
}

local ABILITY_FALLBACK_MAP = {
    [1] = "slash",
    [2] = "fury_reward",
    [3] = "whirlwind_dash",
    [4] = "blade_throw",
}

local sounds = {}
local audio_enabled = true

local function has_audio_backend()
    return love ~= nil and love.audio ~= nil and type(love.audio.newSource) == "function"
end

local function generate_placeholder_sound(frequency, duration)
    if not has_audio_backend() or not love.sound or type(love.sound.newSoundData) ~= "function" then
        return nil
    end

    local sample_rate = 44100
    local samples = math.max(1, math.floor(sample_rate * (duration or 0.1) + 0.5))
    local ok_data, sound_data = pcall(love.sound.newSoundData, samples, sample_rate, 16, 1)
    if not ok_data or not sound_data then
        return nil
    end

    local actual_duration = samples / sample_rate
    local fade = math.min(0.01, actual_duration * 0.25)
    for i = 0, samples - 1 do
        local t = i / sample_rate
        local sample = math.sin(2 * math.pi * (frequency or 440) * t)
        local envelope = 1.0
        if fade > 0 then
            if t < fade then
                envelope = t / fade
            elseif t > actual_duration - fade then
                envelope = (actual_duration - t) / fade
            end
        end
        sound_data:setSample(i, sample * envelope * 0.3)
    end

    local ok_src, src = pcall(love.audio.newSource, sound_data, "static")
    if ok_src then
        return src
    end
    return nil
end

local function resolve_audio_path(filename)
    for _, dir in ipairs(AUDIO_DIR_CANDIDATES) do
        local path = dir .. filename
        if not love.filesystem or not love.filesystem.getInfo or love.filesystem.getInfo(path) then
            local ok, source = pcall(love.audio.newSource, path, "static")
            if ok and source then
                return source
            end
        end
    end
    return nil
end

local function load_sound(sound_key, entry)
    local source = resolve_audio_path(entry.file)
    if source then
        return source
    end
    print(string.format("[Audio] Placeholder procedural ativado para '%s' (%s)", sound_key, entry.file))
    return generate_placeholder_sound(entry.freq, entry.duration)
end

--- Carrega todos os efeitos sonoros cadastrados (com fallback procedural caso o .wav falte).
function audio_system.init()
    sounds = {}
    if not has_audio_backend() then
        print("[Audio] Backend de áudio indisponível (modo headless); SFX desabilitado com segurança")
        return 0
    end

    local loaded = 0
    for key, entry in pairs(SOUND_CATALOG) do
        local src = load_sound(key, entry)
        if src then
            if entry.volume and src.setVolume then
                pcall(src.setVolume, src, entry.volume)
            end
            sounds[key] = src
            loaded = loaded + 1
        end
    end

    print(string.format("[Audio] %d efeitos sonoros carregados", loaded))
    return loaded
end

--- Reproduz um SFX por nome lógico usando clone() para permitir sobreposição simultânea.
function audio_system.play(sound_name)
    if not audio_enabled or not sound_name then
        return false
    end

    local sound = sounds[sound_name]
    if not sound then
        return false
    end

    if type(sound.clone) == "function" then
        local ok_clone, clone = pcall(sound.clone, sound)
        if ok_clone and clone then
            local entry = SOUND_CATALOG[sound_name]
            if entry and entry.volume and type(clone.setVolume) == "function" then
                pcall(clone.setVolume, clone, entry.volume)
            end
            local ok_play = pcall(clone.play, clone)
            if ok_play then
                return true
            end
        end
    end

    if type(sound.stop) == "function" then
        pcall(sound.stop, sound)
    end
    if type(sound.play) == "function" then
        return pcall(sound.play, sound)
    end
    return false
end

--- Reproduz o SFX correspondente à habilidade conjurada.
function audio_system.play_skill(skill_name, fallback_ability_id)
    local key = nil
    if type(skill_name) == "string" and skill_name ~= "" then
        key = SKILL_SOUND_MAP[string.lower(skill_name)]
    elseif fallback_ability_id then
        key = ABILITY_FALLBACK_MAP[fallback_ability_id]
    end

    if key then
        return audio_system.play(key)
    end
    return false
end

function audio_system.is_enabled()
    return audio_enabled
end

function audio_system.set_enabled(enabled)
    audio_enabled = not not enabled
    if not audio_enabled and love and love.audio and type(love.audio.stop) == "function" then
        pcall(love.audio.stop)
    end
    return audio_enabled
end

function audio_system.toggle_mute()
    return audio_system.set_enabled(not audio_enabled)
end

function audio_system.get_catalog()
    return SOUND_CATALOG
end

function audio_system.get_loaded_sounds()
    return sounds
end

return audio_system
