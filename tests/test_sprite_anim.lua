-- Unit tests for json.lua and sprite_anim.lua (8-way animated sprite engine)

package.path = "./client/src/?.lua;./client/?.lua;./?.lua;" .. package.path

local passed = 0
local function run_test(name, fn)
    fn()
    passed = passed + 1
    print("  [PASS] " .. name)
end

-- Mock Love2D environment for SpriteAnim tests
local mock_alpha_rows = nil
local function setup_love_mock(opts)
    opts = opts or {}
    mock_alpha_rows = opts.alpha_rows

    _G.love = {
        filesystem = {
            getInfo = function(path)
                if not path or path == "" then return nil end
                local f = io.open(path, "rb")
                if f then
                    local ok, _, code = f:read(1)
                    f:close()
                    if ok == nil and code == 21 then
                        return { type = "directory" }
                    end
                    return { type = "file" }
                end
                return nil
            end,
            read = function(path)
                local f = io.open(path, "rb")
                if not f then return nil end
                local c = f:read("*a")
                f:close()
                return c
            end,
            load = function(path)
                return loadfile(path)
            end,
            getDirectoryItems = function()
                return {}
            end
        },
        graphics = {
            newImage = function(src)
                local path = type(src) == "table" and src._path or src
                local w = (type(src) == "table" and src._w) or 48
                local h = (type(src) == "table" and src._h) or 48
                return {
                    path = path,
                    _w = w,
                    _h = h,
                    setFilter = function() end,
                    getWidth = function(self) return self._w end,
                    getHeight = function(self) return self._h end,
                }
            end
        },
        image = opts.enable_image_data and {
            newImageData = function(path)
                local w = opts.img_w or 56
                local h = opts.img_h or 56
                return {
                    _path = path,
                    _w = w,
                    _h = h,
                    getDimensions = function(self) return self._w, self._h end,
                    getPixel = function(_, _, y)
                        if mock_alpha_rows and mock_alpha_rows[y] then
                            return 1, 1, 1, 1
                        end
                        return 0, 0, 0, 0
                    end
                }
            end
        } or nil
    }
end

print("=== SpriteAnim & JSON Unit Tests ===")

run_test("json.decode parses objects, arrays, escapes, and validates surrogate pairs", function()
    package.loaded["src.json"] = nil
    local json = require("src.json")

    local obj = json.decode('{"a": 1, "b": [true, false, null, "hi\\n"], "u": "\\u0041"}')
    assert(obj.a == 1)
    assert(obj.b[1] == true and obj.b[2] == false and obj.b[3] == nil and obj.b[4] == "hi\n")
    assert(obj.u == "A")

    -- Valid UTF-16 surrogate pair -> U+1F600 (4-byte UTF-8)
    local emoji = json.decode('"\\uD83D\\uDE00"')
    assert(#emoji == 4)

    -- High surrogate NOT followed by \u must NOT consume arbitrary trailing chars
    local broken = json.decode('"\\uD800ab1234"')
    assert(broken:sub(-6) == "ab1234", "must preserve 'ab1234' when no \\u low surrogate follows")

    -- Real Arya metadata.json decodes cleanly
    local f = assert(io.open("client/assets/sprites/arya/metadata.json", "r"))
    local meta = json.decode(f:read("*a"))
    f:close()
    assert(type(meta.states) == "table" and #meta.states == 9)
end)

run_test("SpriteAnim.load_character validates names, loads Arya, and falls back to placeholder", function()
    setup_love_mock()
    package.loaded["src.sprite_anim"] = nil
    local SpriteAnim = require("src.sprite_anim")
    SpriteAnim.clear_cache()

    -- Reject path traversal / shell metacharacters
    assert(SpriteAnim.load_character("../arya") == nil)
    assert(SpriteAnim.load_character("arya;ls") == nil)
    assert(SpriteAnim.load_character("arya/Rotacao") == nil)

    -- Unknown character returns placeholder metrics
    assert(SpriteAnim.load_character("nonexistent_hero") == nil)
    local img, ox, oy, has_8way, vh = SpriteAnim.get_frame({
        entity_id = 999,
        character_name = "nonexistent_hero",
        direction = "south"
    })
    assert(img == nil and ox == 16 and oy == 32 and has_8way == false and vh == 32)

    -- Load Arya (case-insensitive)
    local set = SpriteAnim.load_character("Arya")
    assert(set ~= nil and set.has_animations == true and set.has_rotations == true)
    assert(set.anim_map.skills.slash == "Habilidade_1")
    assert(set.anim_map.state_durations.aliado_morre == 3.0)
end)

run_test("SpriteAnim 8-way idle, walk (< 2.5), and run (>= 2.5) state transitions", function()
    setup_love_mock()
    package.loaded["src.sprite_anim"] = nil
    local SpriteAnim = require("src.sprite_anim")
    SpriteAnim.clear_cache()

    local dirs = { "east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east" }
    for _, d in ipairs(dirs) do
        SpriteAnim.update(0.016, 1, {
            character_name = "arya",
            direction = d,
            is_moving = false,
            speed = 0,
            is_dead = false
        })
        local img, _, _, has_8way = SpriteAnim.get_frame({ entity_id = 1, character_name = "arya", direction = d })
        assert(img and has_8way == true)
        local expected_suffix = "Rotacao/rotations/" .. d .. ".png"
        assert(img.path:sub(-#expected_suffix) == expected_suffix,
            "expected idle rotation for " .. d .. ", got " .. tostring(img.path))
    end

    -- Walk (speed < 2.5)
    SpriteAnim.update(0.10, 1, { character_name = "arya", direction = "west", is_moving = true, speed = 1.8 })
    local walk_img = SpriteAnim.get_frame({ entity_id = 1, character_name = "arya" })
    assert(walk_img.path:find("andando/animations/west/frame_001%.png$"), "expected walk frame_001, got " .. walk_img.path)

    -- Run (speed >= 2.5)
    SpriteAnim.update(0.016, 1, { character_name = "arya", direction = "east", is_moving = true, speed = 3.2 })
    local run_img = SpriteAnim.get_frame({ entity_id = 1, character_name = "arya" })
    assert(run_img.path:find("correndo/animations/east/frame_000%.png$"), "expected run frame_000, got " .. run_img.path)
end)

run_test("SpriteAnim.trigger_action initializes before update and preserves aim direction while locked", function()
    setup_love_mock()
    package.loaded["src.sprite_anim"] = nil
    local SpriteAnim = require("src.sprite_anim")
    SpriteAnim.clear_cache()

    -- Cast before any SpriteAnim.update call for entity 10, aiming north while moving south
    assert(SpriteAnim.trigger_action(10, "slash", 1, 0, -1, "arya") == true,
        "trigger_action must return true when sprite animation starts")
    assert(SpriteAnim.trigger_action(12, "fireball", 1, 1, 0, "mage") == false,
        "trigger_action must return false when character has no sprite animation")
    assert(SpriteAnim.has_state("arya", "death") == true)
    assert(SpriteAnim.has_state("mage", "death") == false)
    -- Slash é cancelável por movimento: para manter a animação bloqueada no teste,
    -- a entidade deve estar parada (is_moving = false) durante o golpe.
    SpriteAnim.update(0.05, 10, {
        character_name = "arya",
        direction = "south",
        is_moving = false,
        speed = 0,
        is_dead = false
    })

    -- Even if get_frame caller passes movement direction "south", locked attack keeps aim "north"
    local atk_img = SpriteAnim.get_frame({
        entity_id = 10,
        character_name = "arya",
        direction = "south",
        is_moving = true
    })
    assert(atk_img.path:find("Habilidade_1/animations/north/frame_000%.png$"),
        "expected north attack frame, got " .. tostring(atk_img and atk_img.path))

    -- Advance past 9 frames at 11 FPS (~0.85s) -> unlocks and resumes run south
    SpriteAnim.update(0.90, 10, {
        character_name = "arya",
        direction = "south",
        is_moving = true,
        speed = 3.2,
        is_dead = false
    })
    local post_img = SpriteAnim.get_frame({ entity_id = 10, character_name = "arya", direction = "south" })
    assert(post_img.path:find("correndo/animations/south/"), "expected resumed run after attack, got " .. post_img.path)

    -- Verify all 4 skills map correctly
    local expected_folders = {
        { skill = "slash", slot = 1, folder = "Habilidade_1" },
        { skill = "fury_reward", slot = 2, folder = "Habilidade_2" },
        { skill = "whirlwind_dash", slot = 3, folder = "Habilidade_3" },
        { skill = "blade_throw", slot = 4, folder = "Habilidade_4" },
    }
    for _, tc in ipairs(expected_folders) do
        SpriteAnim.clear_entity_state(11)
        SpriteAnim.trigger_action(11, tc.skill, tc.slot, 1, 0, "arya")
        local f_img = SpriteAnim.get_frame({ entity_id = 11, character_name = "arya" })
        assert(f_img.path:find(tc.folder .. "/animations/east/frame_000%.png$"),
            "expected " .. tc.folder .. " for " .. tc.skill .. ", got " .. tostring(f_img and f_img.path))
    end
end)

run_test("SpriteAnim slash cancels into locomotion on movement while whirlwind_dash stays locked", function()
    setup_love_mock()
    package.loaded["src.sprite_anim"] = nil
    local SpriteAnim = require("src.sprite_anim")
    SpriteAnim.clear_cache()

    -- Slash (cancelable): input de movimento interrompe o recovery do golpe,
    -- mas só após os frames de impacto (frame_index >= 3)
    SpriteAnim.trigger_action(50, "slash", 1, 1, 0, "arya")
    -- Movimento imediato após o cast (gap de sync do casting_until) NÃO cancela
    SpriteAnim.update(0.05, 50, {
        character_name = "arya",
        direction = "east",
        is_moving = true,
        speed = 3.2,
        is_dead = false
    })
    local early_img = SpriteAnim.get_frame({ entity_id = 50, character_name = "arya" })
    assert(early_img.path:find("Habilidade_1/animations/east/"),
        "slash must not cancel during the impact-frame window, got " .. tostring(early_img and early_img.path))
    -- Avança ~0.30s parado para passar da janela mínima de cancelamento
    SpriteAnim.update(0.30, 50, {
        character_name = "arya",
        direction = "east",
        is_moving = false,
        speed = 0,
        is_dead = false
    })
    SpriteAnim.update(0.05, 50, {
        character_name = "arya",
        direction = "east",
        is_moving = true,
        speed = 3.2,
        is_dead = false
    })
    local cancel_img = SpriteAnim.get_frame({ entity_id = 50, character_name = "arya" })
    assert(cancel_img.path:find("correndo/animations/east/") or cancel_img.path:find("andando/animations/east/"),
        "slash must cancel into locomotion when moving, got " .. tostring(cancel_img and cancel_img.path))

    -- Whirlwind dash (não cancelável): continua bloqueado mesmo em movimento
    SpriteAnim.trigger_action(51, "whirlwind_dash", 3, 1, 0, "arya")
    SpriteAnim.update(0.05, 51, {
        character_name = "arya",
        direction = "east",
        is_moving = true,
        speed = 3.2,
        is_dead = false
    })
    local locked_img = SpriteAnim.get_frame({ entity_id = 51, character_name = "arya" })
    assert(locked_img.path:find("Habilidade_3/animations/east/"),
        "whirlwind_dash must remain locked while moving, got " .. tostring(locked_img and locked_img.path))
end)

run_test("SpriteAnim.trigger_ally_death plays 18-frame sequence over 3.0s accurately", function()
    setup_love_mock()
    package.loaded["src.sprite_anim"] = nil
    local SpriteAnim = require("src.sprite_anim")
    SpriteAnim.clear_cache()

    SpriteAnim.trigger_ally_death(20, "arya")
    local f1 = SpriteAnim.get_frame({ entity_id = 20, character_name = "arya" })
    assert(f1.path:find("ela_caindo_no_chao_chorando/south/frame_000%.png$"), "frame 1 must be crying part, got " .. f1.path)

    -- Advance 1.6s (past 9 * 3/18 = 1.5s) -> enters part 2 (sword pickup / fury)
    SpriteAnim.update(1.6, 20, { character_name = "arya", direction = "south", is_moving = false, speed = 0 })
    local f10 = SpriteAnim.get_frame({ entity_id = 20, character_name = "arya" })
    assert(f10.path:find("apos_isso_ela_pega_sua_espada_devolta_e_acende_uma/south/frame_"),
        "at 1.6s must play second part of aliado_morre, got " .. f10.path)

    -- Advance remaining 1.5s (total 3.1s > 3.0s) -> unlocks back to idle
    SpriteAnim.update(1.5, 20, { character_name = "arya", direction = "south", is_moving = false, speed = 0 })
    local f_done = SpriteAnim.get_frame({ entity_id = 20, character_name = "arya" })
    assert(f_done.path:find("Rotacao/rotations/south%.png$"), "after 3.0s must return to idle, got " .. f_done.path)
end)

run_test("SpriteAnim death holds last frame and respawn resets to idle", function()
    setup_love_mock()
    package.loaded["src.sprite_anim"] = nil
    local SpriteAnim = require("src.sprite_anim")
    SpriteAnim.clear_cache()

    SpriteAnim.update(0.016, 30, { character_name = "arya", direction = "east", is_dead = true })
    SpriteAnim.update(2.0, 30, { character_name = "arya", direction = "east", is_dead = true })
    local dead_img = SpriteAnim.get_frame({ entity_id = 30, character_name = "arya", is_dead = true })
    assert(dead_img.path:find("morte/east/frame_008%.png$"), "death must hold final frame_008, got " .. dead_img.path)

    -- Respawn
    SpriteAnim.update(0.016, 30, { character_name = "arya", direction = "east", is_dead = false, is_moving = false })
    local alive_img = SpriteAnim.get_frame({ entity_id = 30, character_name = "arya", is_dead = false })
    assert(alive_img.path:find("Rotacao/rotations/east%.png$"), "respawn must return to idle, got " .. alive_img.path)
end)

run_test("SpriteAnim computes foot anchor oy and stable visual_h from ImageData alpha bounds", function()
    local rows = {}
    for y = 8, 40 do rows[y] = true end -- 15px bottom padding inside 56x56 canvas
    setup_love_mock({ enable_image_data = true, img_w = 56, img_h = 56, alpha_rows = rows })
    package.loaded["src.sprite_anim"] = nil
    local SpriteAnim = require("src.sprite_anim")
    SpriteAnim.clear_cache()

    local img, ox, oy, has_8way, vh = SpriteAnim.get_frame({ entity_id = 40, character_name = "arya", direction = "south" })
    assert(img ~= nil and has_8way == true)
    assert(ox == 28, "ox must be w/2 (28), got " .. tostring(ox))
    assert(oy == 41, "oy must anchor at bottom opaque row + 1 (41), got " .. tostring(oy))
    assert(vh == 33, "visual_h must be character height (33), got " .. tostring(vh))
end)

run_test("SpriteAnim LRU cache enforces MAX_IMAGE_CACHE (512)", function()
    setup_love_mock()
    package.loaded["src.sprite_anim"] = nil
    local SpriteAnim = require("src.sprite_anim")
    SpriteAnim.clear_cache()

    local dirs = { "east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east" }
    local states = { "andando", "correndo", "Habilidade_1", "Habilidade_2", "Habilidade_3", "Habilidade_4", "morte", "aliado_morre" }
    for _, st in ipairs(states) do
        for _, d in ipairs(dirs) do
            for f = 1, 9 do
                SpriteAnim.get_frame("arya", st, d, f)
            end
        end
    end

    local stats = SpriteAnim.get_cache_stats()
    assert(stats.image_count == stats.max_images and stats.image_count == 512,
        string.format("expected cache capped at 512, got %d", stats.image_count))
end)

print(string.format("\n>>> SpriteAnim & JSON: All %d unit tests passed! <<<", passed))
