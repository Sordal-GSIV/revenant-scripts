--- @revenant-script
--- name: perfume
--- version: 1.0.0
--- author: elanthia-online
--- game: gs
--- description: Auto-reapply perfume/cologne when scent fades
--- tags: cologne,perfume,utility,roleplay
---
--- Usage:
---   ;perfume           start monitoring and reapply when scent fades
---   ;perfume setup     configure item name, container, wearable flag
---   ;perfume help      show help
---
--- Settings stored in CharSettings:
---   perfume.frag_type       name of the perfume/cologne item
---   perfume.frag_cont       container holding the item
---   perfume.frag_wearable   true if item is wearable (pull instead of pour)

local function load_settings()
    return {
        frag_type    = CharSettings["perfume.frag_type"] or "",
        frag_cont    = CharSettings["perfume.frag_cont"] or "",
        frag_wearable = CharSettings["perfume.frag_wearable"] or false,
    }
end

local function save_settings(s)
    CharSettings["perfume.frag_type"] = s.frag_type
    CharSettings["perfume.frag_cont"] = s.frag_cont
    CharSettings["perfume.frag_wearable"] = s.frag_wearable
end

local function setup()
    local s = load_settings()
    echo("Perfume Setup")
    echo("Current item:      " .. (s.frag_type ~= "" and s.frag_type or "(not set)"))
    echo("Current container: " .. (s.frag_cont ~= "" and s.frag_cont or "(not set)"))
    echo("Wearable:          " .. tostring(s.frag_wearable))
    echo("")
    echo("To change settings, use:")
    echo("  ;e CharSettings['perfume.frag_type'] = 'some perfume'")
    echo("  ;e CharSettings['perfume.frag_cont'] = 'my cloak'")
    echo("  ;e CharSettings['perfume.frag_wearable'] = true")
end

local function apply_fragrance()
    local s = load_settings()
    if s.frag_type == "" then
        echo("No perfume configured. Run ;perfume setup")
        return
    end

    -- Check if we smell
    local line = dothistimeout("smell " .. GameState.name, 3,
        "You quietly sniff at yourself")
    if line and line:find("You %*think%* you smell okay") then
        echo("Time to reapply!")
        if s.frag_wearable then
            fput("pull my " .. s.frag_type)
        else
            -- Wait for hands to be free
            wait_until(function()
                return not Script.running("go2") and (not checkleft() or not checkright())
            end)
            fput("open my " .. s.frag_cont)
            fput("get my " .. s.frag_type)
            fput("pour " .. s.frag_type .. " on " .. GameState.name)
            fput("put " .. s.frag_type .. " in my " .. s.frag_cont)
            fput("close my " .. s.frag_cont)
        end
    end

    -- Wait for scent to fade
    waitfor("The subtle scent which had been clinging to you dissipates.")
    -- Recurse to reapply
    apply_fragrance()
end

-- Main
local action = Script.vars[1]

if not action or action == "" then
    apply_fragrance()
elseif action:match("setup") then
    setup()
elseif action:match("help") then
    echo("Usage: ;perfume or ;perfume setup")
else
    echo("Unknown option. Type ;perfume help")
end
