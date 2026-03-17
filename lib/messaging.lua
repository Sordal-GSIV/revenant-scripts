local M = {}

function M.xml_encode(text)
    return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

-- Typed message formatting using XML preset tags
function M.msg(msg_type, text)
    local encoded = M.xml_encode(text)
    local formatted
    if msg_type == "error" then
        formatted = '<preset id="speech">' .. encoded .. '</preset>'
    elseif msg_type == "warn" then
        formatted = '<preset id="thought">' .. encoded .. '</preset>'
    elseif msg_type == "info" then
        formatted = '<preset id="whisper">' .. encoded .. '</preset>'
    elseif msg_type == "bold" or msg_type == "monster" then
        formatted = '<pushBold/>' .. encoded .. '<popBold/>'
    else
        formatted = encoded
    end
    respond(formatted)
end

function M.monsterbold(text)
    M.msg("monster", text)
end

function M.mono(text)
    respond('<output class="mono">' .. M.xml_encode(text) .. '</output>')
end

return M
