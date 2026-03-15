local M = {}

function M.detect_format(raw)
    if raw.scripts then return "revenant" end
    if raw.available then return "jinx" end
    return "unknown"
end

local function strip_path(file_path)
    -- "/scripts/go2.lic" -> "go2.lic", "/map_files/town.png" -> "town.png"
    return file_path:match("[^/]+$") or file_path
end

local function classify_type(original_type, filename)
    if original_type == "data" and filename == "mapdb.json" then
        return "map"
    elseif original_type == "map" then
        return "map_image"
    end
    return original_type or "script"
end

local function normalize_jinx_entry(entry)
    local filename = strip_path(entry.file or "")
    local hash = entry.md5
    local hash_type = "sha1_base64"
    if not hash or hash == "" then
        hash = nil
        hash_type = "none"
    end
    return {
        name = filename,
        path = entry.file,
        type = classify_type(entry.type, filename),
        hash = hash,
        hash_type = hash_type,
        last_updated = entry.last_commit,
        tags = entry.tags or {},
        author = nil,
        description = nil,
    }
end

function M.normalize(raw, format)
    format = format or M.detect_format(raw)

    if format == "revenant" or format == "unknown" then
        -- Pass through unchanged
        return raw
    end

    if format == "jinx" then
        local scripts = {}
        for _, entry in ipairs(raw.available or {}) do
            scripts[#scripts + 1] = normalize_jinx_entry(entry)
        end
        return {
            scripts = scripts,
            last_updated = raw.last_updated,
        }
    end

    return raw
end

return M
