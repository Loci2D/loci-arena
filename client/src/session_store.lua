-- SessionStore - Persistencia leve de configuracao de servidor e session_token
-- Utiliza love.filesystem (t.identity = "loci-arena") com fallback seguro em testes headless.

local json = require("src.json")

local SessionStore = {}

local STORE_FILENAME = "session_config.json"
local DEFAULT_GRACE_MAX_AGE_SEC = 30

local function has_fs()
    return love and love.filesystem and love.filesystem.read and love.filesystem.write
end

function SessionStore.load()
    local defaults = {
        last_ip = "127.0.0.1",
        last_port = 8080,
        player_name = nil,
        session_token = nil,
        session_host = nil,
        session_port = nil,
        session_saved_at = nil,
    }

    if not has_fs() then
        return defaults
    end

    local ok_info, info = pcall(love.filesystem.getInfo, STORE_FILENAME)
    if not ok_info or not info then
        return defaults
    end

    local ok_read, raw = pcall(love.filesystem.read, STORE_FILENAME)
    if not ok_read or not raw or raw == "" then
        return defaults
    end

    local ok_dec, data = pcall(json.decode, raw)
    if not ok_dec or type(data) ~= "table" then
        return defaults
    end

    defaults.last_ip = (type(data.last_ip) == "string" and data.last_ip ~= "") and data.last_ip or defaults.last_ip
    defaults.last_port = tonumber(data.last_port) or defaults.last_port
    defaults.player_name = (type(data.player_name) == "string" and data.player_name ~= "") and data.player_name or nil
    defaults.session_token = (type(data.session_token) == "string" and data.session_token ~= "") and data.session_token or nil
    defaults.session_host = (type(data.session_host) == "string" and data.session_host ~= "") and data.session_host or nil
    defaults.session_port = tonumber(data.session_port)
    defaults.session_saved_at = tonumber(data.session_saved_at)

    return defaults
end

local function escape_json_str(s)
    return (tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t'))
end

local function encode_flat_json(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        local val_str = nil
        local tv = type(v)
        if tv == "string" then
            val_str = '"' .. escape_json_str(v) .. '"'
        elseif tv == "number" then
            val_str = tostring(v)
        elseif tv == "boolean" then
            val_str = v and "true" or "false"
        end
        if val_str then
            table.insert(parts, '"' .. escape_json_str(k) .. '":' .. val_str)
        end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

function SessionStore.save(data)
    if not has_fs() or type(data) ~= "table" then
        return false
    end

    local encoded = encode_flat_json(data)
    local ok_write, res = pcall(love.filesystem.write, STORE_FILENAME, encoded)
    return ok_write and res ~= false
end

function SessionStore.save_connection(ip, port, player_name)
    local data = SessionStore.load()
    data.last_ip = ip or data.last_ip
    data.last_port = tonumber(port) or data.last_port
    if player_name and player_name ~= "" then
        data.player_name = player_name
    end
    SessionStore.save(data)
    return data
end

function SessionStore.save_session_token(ip, port, player_name, token, now_sec)
    if not token or token == "" then return false end
    local data = SessionStore.load()
    data.last_ip = ip or data.last_ip
    data.last_port = tonumber(port) or data.last_port
    if player_name and player_name ~= "" then
        data.player_name = player_name
    end
    data.session_token = token
    data.session_host = ip
    data.session_port = tonumber(port)
    data.session_saved_at = tonumber(now_sec) or os.time()
    return SessionStore.save(data)
end

function SessionStore.clear_session_token()
    local data = SessionStore.load()
    data.session_token = nil
    data.session_host = nil
    data.session_port = nil
    data.session_saved_at = nil
    return SessionStore.save(data)
end

function SessionStore.has_valid_token(data, max_age_sec, now_sec)
    if type(data) ~= "table" or not data.session_token or data.session_token == "" then
        return false
    end
    local max_age = tonumber(max_age_sec) or DEFAULT_GRACE_MAX_AGE_SEC
    local saved_at = tonumber(data.session_saved_at)
    if not saved_at then
        return true
    end
    local now = tonumber(now_sec) or os.time()
    return (now - saved_at) <= max_age
end

return SessionStore
