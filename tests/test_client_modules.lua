-- Unit tests for client modules: ProceduralAnim and VirtualJoystick (Phase 4 of Issue #59)

package.path = "./client/src/?.lua;./client/?.lua;./?.lua;" .. package.path

local function assert_near(actual, expected, eps, msg)
    eps = eps or 1e-4
    if math.abs((actual or 0) - expected) > eps then
        error(string.format("%s: expected %.6f, got %.6f (eps=%.6f)", msg or "assert_near", expected, actual or 0, eps), 2)
    end
end

local passed = 0
local function run_test(name, fn)
    fn()
    passed = passed + 1
    print("  [PASS] " .. name)
end

print("=== Phase 4: Client Modules Unit Tests ===")

-- ----------------------------------------------------------------------------
-- ProceduralAnim tests
-- ----------------------------------------------------------------------------
run_test("ProceduralAnim computes 8-way directions, facing, legacy mode, and state cleanup", function()
    package.loaded["procedural_anim"] = nil
    local ProceduralAnim = require("procedural_anim")

    local s0 = ProceduralAnim.get_state(1)
    assert(s0.direction == "south" and s0.facing == 1 and s0.is_moving == false)

    -- Cardinal & diagonal directions
    local cases = {
        { vx = 1, vy = 0, dir = "east", facing = 1 },
        { vx = 1, vy = 1, dir = "south-east", facing = 1 },
        { vx = 0, vy = 1, dir = "south", facing = 1 },
        { vx = -1, vy = 1, dir = "south-west", facing = -1 },
        { vx = -1, vy = 0, dir = "west", facing = -1 },
        { vx = -1, vy = -1, dir = "north-west", facing = -1 },
        { vx = 0, vy = -1, dir = "north", facing = -1 }, -- keeps previous facing
        { vx = 1, vy = -1, dir = "north-east", facing = 1 },
    }
    for _, c in ipairs(cases) do
        local st = ProceduralAnim.update_walk(0.016, 1, true, c.vx, c.vy)
        assert(st.direction == c.dir, string.format("expected %s, got %s", c.dir, tostring(st.direction)))
        assert(st.facing == c.facing, string.format("expected facing %d, got %d", c.facing, st.facing))
        assert(st.tilt_angle == 0 and st.bob_offset == 0 and st.squash_x == 1 and st.squash_y == 1)
    end

    -- Stopping preserves last direction
    local stopped = ProceduralAnim.update_walk(0.016, 1, false, 0, 0)
    assert(stopped.is_moving == false and stopped.direction == "north-east")

    -- Legacy facing_dir signature
    local leg_left = ProceduralAnim.update_walk(0.016, 2, true, -1)
    assert(leg_left.direction == "west" and leg_left.facing == -1)
    local leg_right = ProceduralAnim.update_walk(0.016, 2, true, 1)
    assert(leg_right.direction == "east" and leg_right.facing == 1)

    -- clear_state resets entity
    ProceduralAnim.clear_state(1)
    assert(ProceduralAnim.get_state(1).direction == "south")
end)

-- ----------------------------------------------------------------------------
-- VirtualJoystick tests
-- ----------------------------------------------------------------------------
run_test("VirtualJoystick dynamic movement stick activates in bottom-left, clamps radius, and supports multitouch", function()
    package.loaded["virtual_joystick"] = nil
    local VJ = require("virtual_joystick")
    VJ.set_push(nil)
    VJ.update(1280, 720)
    VJ.reset()

    -- Outside bottom-left quadrant must NOT activate movement joystick
    assert(VJ.handle_touchpress("t_bad1", 700, 500) == false) -- right half
    assert(VJ.handle_touchpress("t_bad2", 200, 200) == false) -- top half
    assert(VJ.is_move_active() == false)

    -- Press in bottom-left (200, 500), drag 150px right (clamped to radius=75 -> dx=1.0, dy=0)
    assert(VJ.handle_touchpress("t_move", 200, 500) == true)
    assert(VJ.is_move_active() == true)
    assert(VJ.handle_touchmove("t_move", 350, 500) == true)
    local dx, dy = VJ.get_move_vector()
    assert_near(dx, 1.0, 1e-4, "clamped joystick dx")
    assert_near(dy, 0.0, 1e-4, "clamped joystick dy")

    -- Different touch ID does not affect move joystick
    assert(VJ.handle_touchmove("t_other", 200, 450) == false)
    dx, dy = VJ.get_move_vector()
    assert_near(dx, 1.0, 1e-4)

    -- Partial drag (37.5px up -> dy=-0.5)
    assert(VJ.handle_touchmove("t_move", 200, 462.5) == true)
    dx, dy = VJ.get_move_vector()
    assert_near(dx, 0.0, 1e-4)
    assert_near(dy, -0.5, 1e-4)

    -- Release resets active and vector
    assert(VJ.handle_touchrelease("t_move") == true)
    assert(VJ.is_move_active() == false)
    dx, dy = VJ.get_move_vector()
    assert_near(dx, 0.0, 1e-4)
    assert_near(dy, 0.0, 1e-4)
end)

run_test("VirtualJoystick drag-to-aim, cancellation, quick tap, and non-aiming button release", function()
    package.loaded["virtual_joystick"] = nil
    local VJ = require("virtual_joystick")
    VJ.set_push(nil)
    VJ.update(1280, 720)
    VJ.reset()

    -- Button 3 center: (1280*0.80 = 1024, 720*0.68 = 489.6), radius=50, support_aiming=true
    local b3x, b3y = 1024, 489.6

    -- 1. Drag-to-aim release
    assert(VJ.handle_touchpress("t3", b3x, b3y) == true)
    assert(VJ.is_skill_active(3) == true)
    assert(VJ.is_skill_in_deadzone(3) == true)
    assert(VJ.is_aiming(3) == false)

    -- Drag 60px right (past aim_deadzone=15 and cancel_deadzone=37.5)
    assert(VJ.handle_touchmove("t3", b3x + 60, b3y) == true)
    assert(VJ.is_skill_in_deadzone(3) == false)
    assert(VJ.is_aiming(3) == true)
    assert(VJ.is_skill_cancelled(3) == false)
    local adx, ady = VJ.get_aim_vector(3)
    assert_near(adx, 1.0, 1e-4)
    assert_near(ady, 0.0, 1e-4)

    assert(VJ.handle_touchrelease("t3") == true)
    local events = VJ.pop_release_events()
    assert(#events == 1)
    assert(events[1].skill_id == 3 and events[1].was_aiming == true and events[1].is_cancelled == false)
    assert_near(events[1].aim_dx, 1.0, 1e-4)
    assert(#VJ.pop_release_events() == 0, "pop_release_events must clear queue")

    -- 2. Drag out then drag back to center cancels cast
    assert(VJ.handle_touchpress("t3b", b3x, b3y) == true)
    VJ.handle_touchmove("t3b", b3x, b3y - 60)
    assert(VJ.is_aiming(3) == true)
    VJ.handle_touchmove("t3b", b3x + 5, b3y)
    assert(VJ.is_skill_cancelled(3) == true and VJ.is_aiming(3) == false)
    VJ.handle_touchrelease("t3b")
    events = VJ.pop_release_events()
    assert(#events == 1 and events[1].is_cancelled == true and events[1].was_aiming == false)

    -- 3. Quick tap inside deadzone
    assert(VJ.handle_touchpress("t3c", b3x, b3y) == true)
    VJ.handle_touchrelease("t3c")
    events = VJ.pop_release_events()
    assert(#events == 1 and events[1].was_aiming == false and events[1].is_cancelled == false)

    -- 4. Non-aiming button 1 (1152, 612, r=75) cancels when dragged outside radius
    assert(VJ.handle_mousepressed(1152, 612, 1) == true)
    assert(VJ.is_skill_1_active() == true)
    VJ.handle_mousemoved(1152 + 100, 612)
    assert(VJ.is_skill_1_active() == false, "button without aiming must deactivate when dragged outside radius")
    assert(VJ.handle_mousepressed(1152, 612, 2) == false, "right-click must be ignored")
end)

run_test("VirtualJoystick cooldowns and push coordinate transform", function()
    package.loaded["virtual_joystick"] = nil
    local VJ = require("virtual_joystick")
    VJ.update(1280, 720)
    VJ.reset()

    -- Cooldown (0.5s)
    assert(VJ.can_trigger_skill_2(1.0) == true)
    VJ.trigger_skill_2(1.0)
    assert(VJ.can_trigger_skill_2(1.4) == false)
    assert(VJ.can_trigger_skill_2(1.5) == true)

    -- Push coordinate mapping (e.g., 2x window -> game coords)
    VJ.set_push({
        toGame = function(_, x, y)
            return x * 0.5, y * 0.5
        end
    })
    -- Screen coords (2304, 1224) -> game coords (1152, 612) = Button 1 center
    assert(VJ.handle_touchpress("t_push", 2304, 1224) == true)
    assert(VJ.is_skill_active(1) == true)
    VJ.handle_touchrelease("t_push")
    VJ.set_push(nil)
end)

print(string.format("\n>>> Phase 4: All %d Client Module unit tests passed! <<<", passed))
