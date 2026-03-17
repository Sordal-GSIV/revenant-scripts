--- @revenant-script
--- name: signaturewindow
--- version: 1.0.0
--- author: Phocosoen
--- game: gs
--- tags: wrayth, frontend, signature, emotes, window
--- description: Displays signature verbs in a Wrayth window with clickable links
---
--- Original Lich5 authors: Phocosoen, ChatGPT
--- Ported to Revenant Lua from signaturewindow.lic
---
--- Usage: ;signaturewindow

no_kill_all()
set_priority(-1)

local WINDOW_ID = "SignatureWindow"
local HOOK_ID = "signaturewindow_hook"

put("<closeDialog id='SignatureWindow'/><openDialog type='dynamic' id='SignatureWindow' title='Signature Verbs' target='SignatureWindow' scroll='auto' location='main' justify='3' height='300' resident='true'><dialogData id='SignatureWindow'></dialogData></openDialog>")

local signature_verbs = {}
local total_verbs_expected = 0
local needs_update = false

local function render_signature_window()
    local output = "<dialogData id='" .. WINDOW_ID .. "' clear='t'>"
    local top = 0

    output = output .. "<label id='header1' value='Click on verb for preview.' justify='left' left='0' top='" .. top .. "' />"
    top = top + 20
    output = output .. "<label id='header2' value='Click on ( ! ) to activate.' justify='left' left='0' top='" .. top .. "' />"
    top = top + 20

    local sorted_verbs = {}
    for verb, _ in pairs(signature_verbs) do
        sorted_verbs[#sorted_verbs + 1] = verb
    end
    table.sort(sorted_verbs)

    for i, verb in ipairs(sorted_verbs) do
        local info = signature_verbs[verb]
        if info.target == "none" then
            output = output .. "<link id='use_" .. i .. "' value='( ! )' cmd='signature " .. verb .. "' echo='signature " .. verb .. "' justify='left' left='0' top='" .. top .. "' />"
            output = output .. "<link id='verb_" .. i .. "' value='" .. info.label .. "' cmd='signature view " .. verb .. "' echo='signature view " .. verb .. "' justify='left' left='40' top='" .. top .. "' />"
        else
            output = output .. "<link id='verb_" .. i .. "' value='" .. info.label .. "' cmd='signature view " .. verb .. "' echo='signature view " .. verb .. "' justify='left' left='0' top='" .. top .. "' />"
        end
        top = top + 20
    end

    output = output .. "</dialogData>"
    put(output)
end

DownstreamHook.add(HOOK_ID, function(line)
    local verb, label, target_type = line:match('<d cmd="signature view ([^"]+)">([^<]+)</d>%s+(player|none)')
    if verb then
        verb = verb:match("^%s*(.-)%s*$")
        label = label:match("^%s*(.-)%s*$")
        target_type = target_type:lower()
        if target_type == "player" then
            label = label .. " (T)"
        end
        if not signature_verbs[verb] then
            signature_verbs[verb] = { label = label, description = nil, target = target_type }
            total_verbs_expected = total_verbs_expected + 1
            needs_update = true
        end
    end
    return line
end)

echo("Signature Window script active. Parsing signature verbs...")
fput("signature")

while true do
    if needs_update then
        needs_update = false
        render_signature_window()
    end
    local count = 0
    for _ in pairs(signature_verbs) do count = count + 1 end
    if count == total_verbs_expected and total_verbs_expected > 0 then
        break
    end
    wait(0.1)
end

DownstreamHook.remove(HOOK_ID)
echo("Signature Window population complete.")
