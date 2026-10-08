-- Simple test to verify fireball action is sent
-- This is a minimal script to send action 3 (fireball)

package.path = package.path .. ";./loci2d/?.lua;./loci2d/lib/?.lua;./client/loci2d/?.lua;./client/loci2d/lib/?.lua;./src/?.lua;./client/src/?.lua;./?.lua;./lib/?.lua"
package.cpath = package.cpath .. ";./loci2d/lib/?.so;./loci2d/?.so;./client/loci2d/lib/?.so;./client/loci2d/?.so;./?.so;./lib/?.so"

local ok, loci = pcall(require, "loci_client")
if not ok then
    ok, loci = pcall(require, "loci2d.loci_client")
    if not ok then
        error("Could not load loci_client SDK module. Details: " .. tostring(loci))
    end
end

local SERVER_IP = "127.0.0.1"
local SERVER_PORT = 8080

print("[Test] Connecting to server...")

local connected = loci.connect(SERVER_IP, SERVER_PORT)
if not connected then
    error("Failed to connect to server")
end

print("[Test] Connected! Waiting 2 seconds for entities to spawn...")

-- Wait for entities to spawn
for i = 1, 60 do
    loci.update()
    if i % 20 == 0 then
        print("[Test] Waiting... " .. i .. "/60")
    end
end

print("[Test] Sending fireball action (action 3)...")

local my_entity = loci.get_my_entity()
if my_entity then
    print("[Test] My entity ID: " .. tostring(my_entity.id))
    loci.send_action_direct(3, 0, -1)  -- Fireball aiming up
    print("[Test] Fireball action sent!")
else
    print("[Test] ERROR: No my_entity found!")
end

-- Wait a bit more
for i = 1, 30 do
    loci.update()
end

print("[Test] Test complete. Disconnecting...")
loci.disconnect()
print("[Test] Done.")
