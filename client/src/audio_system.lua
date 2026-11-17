-- Sistema de Áudio (SFX + BGM) para Loci Arena
-- Carrega arquivos .wav (SFX) e .ogg/.mp3 (BGM) de client/assets/audio/
-- SFX usa "static" com clone() para sobreposição; BGM usa "stream" para arquivos longos.

local audio_system = {}

local AUDIO_DIR_CANDIDATES = {
    "assets/audio/",
    "client/assets/audio/",
}

-- BGM: Streaming (stream) para arquivos longos, sem placeholder
local BGM_CATALOG = {
    arena = { file = "bgm_arena.ogg", volume = 0.5 },
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

-- BGM state
local bgm_sources = {}
local current_bgm = nil          -- fonte (Source) da faixa atual
local current_bgm_name = nil     -- nome lógico da faixa atual (chave do BGM_CATALOG)
local bgm_user_paused = false    -- true se o usuário chamou pause_bgm() (sobrevive a mute/unmute)
local bgm_saved_position = nil   -- posição (s) guardada ao mutar, restaurada ao desmutar
local bgm_missing_logged = {}    -- evita repetir o log de faixa ausente a cada tentativa

-- Volume independente (0.0 a 1.0)
local sfx_volume = 1.0
local bgm_volume = 1.0

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

local function resolve_audio_path(filename, source_type)
    source_type = source_type or "static"
    for _, dir in ipairs(AUDIO_DIR_CANDIDATES) do
        local path = dir .. filename
        if not love.filesystem or not love.filesystem.getInfo or love.filesystem.getInfo(path) then
            local ok, source = pcall(love.audio.newSource, path, source_type)
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

local function is_source_playing(source)
    if source and type(source.isPlaying) == "function" then
        local ok, playing = pcall(source.isPlaying, source)
        return ok and playing == true
    end
    return false
end

--- Inicia a BGM atual; se havia uma posição guardada (mute), continua dela.
local function start_current_bgm()
    if not current_bgm or type(current_bgm.play) ~= "function" then
        return
    end
    pcall(current_bgm.play, current_bgm)
    if bgm_saved_position and type(current_bgm.seek) == "function" then
        pcall(current_bgm.seek, current_bgm, bgm_saved_position)
    end
    bgm_saved_position = nil
end

--- Carrega todos os efeitos sonoros cadastrados (com fallback procedural caso o .wav falte).
function audio_system.init()
    sounds = {}
    bgm_sources = {}
    current_bgm = nil
    current_bgm_name = nil
    bgm_user_paused = false
    bgm_saved_position = nil
    bgm_missing_logged = {}

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

    -- Carregar BGM (streaming, sem placeholder)
    for key, entry in pairs(BGM_CATALOG) do
        local src = resolve_audio_path(entry.file, "stream")
        if src then
            if src.setLooping then
                pcall(src.setLooping, src, true)
            end
            if entry.volume and src.setVolume then
                pcall(src.setVolume, src, entry.volume * bgm_volume)
            end
            bgm_sources[key] = src
            print(string.format("[Audio] BGM '%s' carregado (streaming)", key))
        else
            print(string.format("[Audio] BGM '%s' não encontrado (%s) - trilha desabilitada silenciosamente", key, entry.file))
        end
    end

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
                pcall(clone.setVolume, clone, entry.volume * sfx_volume)
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

--- Ativa/desativa todo o áudio (tecla M). Ao mutar, SFX e BGM são interrompidos; a BGM
--- guarda a posição e volta do mesmo ponto ao desmutar (se não tiver sido pausada pelo usuário).
function audio_system.set_enabled(enabled)
    local was_enabled = audio_enabled
    audio_enabled = not not enabled

    if audio_enabled == was_enabled or not has_audio_backend() then
        return audio_enabled
    end

    if not audio_enabled then
        -- Mudo: guardar a posição da BGM e cortar TODO o áudio (inclui SFX em andamento).
        -- love.audio.stop() zera a posição das fontes, por isso salvamos antes.
        if current_bgm and type(current_bgm.tell) == "function" then
            local ok, pos = pcall(current_bgm.tell, current_bgm)
            if ok then
                bgm_saved_position = pos
            end
        end
        if type(love.audio.stop) == "function" then
            pcall(love.audio.stop)
        end
    else
        -- Desmutar: retomar a BGM, exceto se o usuário a pausou explicitamente.
        if current_bgm and not bgm_user_paused then
            start_current_bgm()
        end
    end

    return audio_enabled
end

function audio_system.toggle_mute()
    return audio_system.set_enabled(not audio_enabled)
end

-- ========== BGM API ==========

--- Registra (ou substitui) uma faixa no catálogo de BGM. Deve ser chamada antes de init().
--- entry = { file = "arquivo.ogg", volume = 0.0..1.0 }
function audio_system.register_bgm(track_name, entry)
    BGM_CATALOG[track_name] = entry
end

--- Reproduz uma faixa de BGM em loop (para a anterior se for outra faixa).
--- Com o áudio mutado, apenas registra a faixa: ela começa a tocar quando for desmutado.
function audio_system.play_bgm(track_name)
    if not has_audio_backend() then
        return false
    end

    local bgm = bgm_sources[track_name]
    if not bgm then
        if not bgm_missing_logged[track_name] then
            bgm_missing_logged[track_name] = true
            print(string.format("[Audio] BGM '%s' indisponível - nada será tocado", tostring(track_name)))
        end
        return false
    end

    if current_bgm and current_bgm ~= bgm then
        if type(current_bgm.stop) == "function" then
            pcall(current_bgm.stop, current_bgm)
        end
        bgm_saved_position = nil
    end

    current_bgm = bgm
    current_bgm_name = track_name
    bgm_user_paused = false

    if audio_enabled and not is_source_playing(bgm) then
        start_current_bgm()
        print(string.format("[Audio] BGM '%s' iniciado", track_name))
    end
    return true
end

--- Para a BGM atual e esquece a faixa.
function audio_system.stop_bgm()
    if current_bgm then
        if type(current_bgm.stop) == "function" then
            pcall(current_bgm.stop, current_bgm)
        end
        print("[Audio] BGM parado")
    end
    current_bgm = nil
    current_bgm_name = nil
    bgm_user_paused = false
    bgm_saved_position = nil
end

--- Pausa a BGM atual (preserva posição). A pausa explícita sobrevive a mute/unmute.
function audio_system.pause_bgm()
    if not current_bgm then
        return
    end
    bgm_user_paused = true
    if type(current_bgm.pause) == "function" then
        pcall(current_bgm.pause, current_bgm)
    end
    print("[Audio] BGM pausado")
end

--- Retoma a BGM pausada (continua em silêncio se o áudio estiver mutado).
function audio_system.resume_bgm()
    if not current_bgm then
        return
    end
    bgm_user_paused = false
    if audio_enabled then
        start_current_bgm()
        print("[Audio] BGM retomado")
    end
end

--- Retorna a faixa de BGM atual (nome ou nil).
function audio_system.get_current_bgm()
    return current_bgm_name
end

-- ========== Volume Control ==========

--- Define o volume de SFX (0.0 a 1.0). Vale para os próximos SFX tocados.
function audio_system.set_sfx_volume(vol)
    sfx_volume = math.max(0.0, math.min(1.0, vol or 1.0))
end

--- Define o volume de BGM (0.0 a 1.0) e aplica imediatamente à faixa atual.
function audio_system.set_bgm_volume(vol)
    bgm_volume = math.max(0.0, math.min(1.0, vol or 1.0))
    if current_bgm and type(current_bgm.setVolume) == "function" then
        local entry = BGM_CATALOG[current_bgm_name]
        if entry then
            pcall(current_bgm.setVolume, current_bgm, (entry.volume or 1.0) * bgm_volume)
        end
    end
end

--- Retorna o volume de SFX.
function audio_system.get_sfx_volume()
    return sfx_volume
end

--- Retorna o volume de BGM.
function audio_system.get_bgm_volume()
    return bgm_volume
end

function audio_system.get_catalog()
    return SOUND_CATALOG
end

function audio_system.get_loaded_sounds()
    return sounds
end

return audio_system
