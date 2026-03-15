local M = {}

local translations = nil
local translations_game = nil

-- Detection: is this wayto value a StringProc (Ruby code) vs a simple command?
function M.is_stringproc(wayto_value)
    if not wayto_value or type(wayto_value) ~= "string" then return false end
    if wayto_value:find(";") then return true end
    if wayto_value:find("%(") then return true end
    if wayto_value:find("{") then return true end
    if wayto_value:find("fput") then return true end
    if wayto_value:find("dothistimeout") then return true end
    if wayto_value:find("start_script") then return true end
    if wayto_value:find("waitfor") then return true end
    if wayto_value:find("wait_until") then return true end
    if wayto_value:find("move ") and wayto_value:find("'") then return true end
    return false
end

-- Load translations from disk
function M.load_translations(game)
    local path = "data/" .. game .. "/stringproc_translations.json"
    if not File.exists(path) then
        translations = { version = 1, translations = {} }
        translations_game = game
        return translations
    end
    local content, err = File.read(path)
    if not content then
        translations = { version = 1, translations = {} }
        translations_game = game
        return translations
    end
    local ok, data = pcall(Json.decode, content)
    if ok and data then
        translations = data
    else
        translations = { version = 1, translations = {} }
    end
    translations_game = game
    return translations
end

-- Save translations to disk
function M.save_translations(game, data)
    local dir = "data/" .. game
    if not File.exists("data") then File.mkdir("data") end
    if not File.exists(dir) then File.mkdir(dir) end
    local path = dir .. "/stringproc_translations.json"
    File.write(path, Json.encode(data or translations))
end

-- Get a translation for an edge
function M.get_translation(from_id, to_id)
    if not translations then return nil end
    local key = tostring(from_id) .. ":" .. tostring(to_id)
    return translations.translations[key]
end

-- Build sandboxed environment for translation execution
local function make_sandbox()
    return {
        move = move,
        put = put,
        fput = fput,
        waitrt = waitrt,
        waitfor = waitfor,
        waitforre = waitforre,
        matchwait = matchwait,
        dothistimeout = dothistimeout,
        pause = pause,
        standing = standing,
        dead = dead,
        muckled = muckled,
        stunned = stunned,
        GameState = GameState,
        Room = Room,
        Map = Map,
        UserVars = UserVars,
        Script = { run = Script.run },
        respond = respond,
        echo = echo,
        tostring = tostring,
        tonumber = tonumber,
        type = type,
        pairs = pairs,
        ipairs = ipairs,
        string = string,
        table = table,
        math = math,
        os = { time = os.time },
    }
end

-- Execute a translation in a sandbox
function M.execute(from_id, to_id)
    local t = M.get_translation(from_id, to_id)
    if not t then return false, "manual" end
    if t.stale then return false, "manual" end

    local chunk_name = "stringproc:" .. from_id .. ":" .. to_id
    local fn, err = load(t.lua, chunk_name, "t", make_sandbox())
    if not fn then
        return false, "syntax error: " .. tostring(err)
    end

    local ok, exec_err = pcall(fn)
    if not ok then
        return false, "execution error: " .. tostring(exec_err)
    end
    return true, nil
end

-- Verify all translations against current map DB
-- Returns { stale = {{from=N, to=N}, ...}, verified = N, total = N }
function M.verify_all(game)
    if not translations then M.load_translations(game) end

    local result = { stale = {}, verified = 0, total = 0 }
    local changed = false

    for key, t in pairs(translations.translations) do
        result.total = result.total + 1
        local from_str, to_str = key:match("^(%d+):(%d+)$")
        if from_str and to_str then
            local from_id = tonumber(from_str)
            local to_id = tonumber(to_str)
            local room = Map.find_room(from_id)
            if room and room.wayto then
                local current_ruby = room.wayto[to_str]
                if current_ruby and current_ruby ~= t.ruby then
                    t.stale = true
                    changed = true
                    result.stale[#result.stale + 1] = { from = from_id, to = to_id }
                elseif current_ruby == t.ruby then
                    if t.stale then
                        t.stale = false
                        changed = true
                    end
                    t.last_verified = os.time()
                    result.verified = result.verified + 1
                end
            end
        end
    end

    if changed then
        M.save_translations(game, translations)
    end

    return result
end

return M
