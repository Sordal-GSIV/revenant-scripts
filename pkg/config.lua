local M = {}

local CONFIG_DIR = "_pkg"
local CONFIG_FILE = CONFIG_DIR .. "/config.lua"
local INSTALLED_FILE = CONFIG_DIR .. "/installed.lua"
local CACHE_DIR = CONFIG_DIR .. "/cache"

local DEFAULT_CONFIG = {
    channel = "stable",
    overrides = {},
    registries = {
        {
            name = "revenant-official",
            url = "https://sordal-gsiv.github.io/revenant-scripts/manifest.json",
        },
    },
}

local function serialize_value(val, indent)
    indent = indent or ""
    local next_indent = indent .. "  "
    local t = type(val)
    if t == "string" then
        return string.format("%q", val)
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "nil" then
        return "nil"
    elseif t == "table" then
        -- Check if array (sequential integer keys starting at 1)
        local is_array = true
        local max_i = 0
        for k, _ in pairs(val) do
            if type(k) == "number" and k == math.floor(k) and k >= 1 then
                if k > max_i then max_i = k end
            else
                is_array = false
                break
            end
        end
        if is_array and max_i > 0 then
            local parts = {}
            for i = 1, max_i do
                parts[#parts + 1] = next_indent .. serialize_value(val[i], next_indent)
            end
            return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
        end
        -- Object
        local parts = {}
        for k, v in pairs(val) do
            local key
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                key = k
            else
                key = "[" .. serialize_value(k) .. "]"
            end
            parts[#parts + 1] = next_indent .. key .. " = " .. serialize_value(v, next_indent)
        end
        table.sort(parts)
        return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
    end
    return "nil"
end

local function serialize_table(tbl)
    return "return " .. serialize_value(tbl) .. "\n"
end

local function load_lua_file(path)
    if not File.exists(path) then
        return nil
    end
    local content, err = File.read(path)
    if not content then return nil, err end
    local fn, load_err = load(content, path)
    if not fn then return nil, load_err end
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    return result
end

function M.ensure_dirs()
    if not File.exists(CONFIG_DIR) then
        File.mkdir(CONFIG_DIR)
    end
    if not File.exists(CACHE_DIR) then
        File.mkdir(CACHE_DIR)
    end
end

function M.load_config()
    M.ensure_dirs()
    local cfg = load_lua_file(CONFIG_FILE)
    if not cfg then
        cfg = DEFAULT_CONFIG
        M.save_config(cfg)
    end
    return cfg
end

function M.save_config(cfg)
    M.ensure_dirs()
    File.write(CONFIG_FILE, serialize_table(cfg))
end

function M.load_installed()
    M.ensure_dirs()
    local inst = load_lua_file(INSTALLED_FILE)
    return inst or {}
end

function M.save_installed(inst)
    M.ensure_dirs()
    File.write(INSTALLED_FILE, serialize_table(inst))
end

function M.get_channel(cfg, script_name)
    if script_name and cfg.overrides and cfg.overrides[script_name] then
        return cfg.overrides[script_name]
    end
    return cfg.channel or "stable"
end

function M.channel_to_branch(channel)
    if channel == "stable" then return "main"
    elseif channel == "beta" then return "beta"
    elseif channel == "dev" then return "dev"
    else return "main"
    end
end

M.CACHE_DIR = CACHE_DIR
M.CACHE_TTL = 3600 -- 1 hour in seconds
M.serialize_table = serialize_table
M.load_lua_file = load_lua_file

return M
