--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: gs4tools
--- version: 2.0.0
--- author: gs4tools.com contributors
--- game: gs
--- description: Data collector for gs4tools.com — captures character info, skills,
---   exp, society, resources, ascension, and enhancive data via game commands,
---   saves to JSON, builds base64url-encoded profile URLs for gs4tools.com import.
--- tags: utility,profile,export,gs4tools,data
---
--- Changelog (from Lich5 gs4tools.lic v0.3.2):
---   v2.0.0 (2026-03-19): Full parity rewrite — consent system, open/sync commands
---     with base64url-encoded payload URLs, normalized profile support, Regex-based
---     capture patterns matching Ruby alternation, all commands from original.
---   v1.0.0 (2026-03-18): Initial Revenant rewrite — basic collect/load/show.
---   v0.3.2 (Lich5): Original by gs4tools.com contributors
---
--- Usage:
---   ;gs4tools                       - Show status + help
---   ;gs4tools collect               - Capture all game data to disk
---   ;gs4tools collect voln          - Capture only Voln data (SOCIETY + RESOURCES)
---   ;gs4tools open                  - Open latest snapshot URL (profile page)
---   ;gs4tools open [page]           - Open latest snapshot URL redirected to page
---   ;gs4tools open [page] --sync    - Sync first, then show URL for target page
---   ;gs4tools sync                  - Collect and show profile import URL
---   ;gs4tools sync [page]           - Collect and show URL with redirect
---   ;gs4tools voln baseline N       - Set favor at last Voln step change
---   ;gs4tools load                  - Show local raw capture summary
---   ;gs4tools load --raw            - Print local raw capture JSON
---   ;gs4tools show                  - Print local raw capture path
---   ;gs4tools allow                 - Grant consent for automated collection/open
---   ;gs4tools revoke                - Revoke consent
---   ;gs4tools help                  - Show this help
---
--- Note: Browser auto-open (Process.spawn) is not available in Revenant.
---   URLs are printed for manual copy/paste.

local VERSION = "2.0.0"
local SITE_ROOT_URL = "https://gs4tools.com"
local DEFAULT_PROFILE_URL = SITE_ROOT_URL .. "/profile/profile.html"

local PAGE_URLS = {
    home         = SITE_ROOT_URL .. "/index.html",
    profile      = SITE_ROOT_URL .. "/profile/profile.html",
    encumbrance  = SITE_ROOT_URL .. "/encumbrance.html",
    calculator   = SITE_ROOT_URL .. "/calculator.html",
    spells       = SITE_ROOT_URL .. "/spells.html",
    voln         = SITE_ROOT_URL .. "/voln.html",
    experience   = SITE_ROOT_URL .. "/experience.html",
    badge        = SITE_ROOT_URL .. "/badge.html",
    resources    = SITE_ROOT_URL .. "/profession-services/resources.html",
    ["stat-optimizer"] = SITE_ROOT_URL .. "/stat-optimizer/stat-optimizer.html",
    lumnis       = SITE_ROOT_URL .. "/lumnis.html",
    ["violet-orb"] = SITE_ROOT_URL .. "/violet-orb.html",
}

local PAGE_ALIASES = {
    enc          = "encumbrance",
    encumberance = "encumbrance",
    profiles     = "profile",
    calc         = "calculator",
    spell        = "spells",
    xp           = "experience",
    resource     = "resources",
    service      = "resources",
    services     = "resources",
    optimizer    = "stat-optimizer",
    statoptimizer = "stat-optimizer",
    orb          = "violet-orb",
}

-- Pre-compiled regex patterns for capture_block start detection (matches Ruby alternation)
local RE_INFO_START = Regex.new("Level 0 Stats for|Strength \\(STR\\):")
local RE_SKILLS = Regex.new("current skill bonuses and ranks")
local RE_EXP = Regex.new("Level:\\s*[0-9,]+\\s+Fame:")
local RE_SOCIETY = Regex.new("member of any society|Council of Light|Order of Voln|Guardians of Sunfist|currently at (?:Step|Rank)\\s+\\d+\\s+of\\s+\\d+|Current society status:")
local RE_RESOURCES = Regex.new("^\\s*(Health|Mana|Stamina|Spirit|Voln Favor):")
local RE_ASC_LIST = Regex.new("Ascension Abilities are available:")
local RE_ASC_MILESTONES = Regex.new("Ascension Milestones are as follows:")
local RE_ENH_LIST = Regex.new("You are (?:not holding any|holding the following|wearing the following) enhancive items|^\\(Items:\\s*\\d+\\)$")
local RE_ENH_TOTALS = Regex.new("^(Stats|Skills|Resources|Statistics):|enhancive (?:items|properties|amount)|no enhancive")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function say(message)
    respond("--- gs4tools: " .. message)
end

local function character_name()
    return GameState.name or "character"
end

local function character_key()
    local name = string.lower(character_name())
    name = string.gsub(name, "[^a-z0-9]+", "_")
    name = string.gsub(name, "^_+", "")
    name = string.gsub(name, "_+$", "")
    return name
end

local function data_dir()
    return "data/gs4tools/profiles"
end

local function data_path()
    File.mkdir(data_dir())
    return data_dir() .. "/" .. character_key() .. ".json"
end

local function normalized_profile_path()
    File.mkdir(data_dir())
    return data_dir() .. "/" .. character_key() .. ".profile.json"
end

local function consent_path()
    return "data/gs4tools/consent.json"
end

local function strip_xml(text)
    if not text then return "" end
    text = string.gsub(text, "<prompt[^>]*>.-</prompt>", "")
    text = string.gsub(text, "<dialogData[^>]*>.-</dialogData>", "")
    text = string.gsub(text, "<output[^>]*/>", "")
    text = string.gsub(text, "<pushBold/>", "")
    text = string.gsub(text, "<popBold/>", "")
    text = string.gsub(text, "<[^>]+>", "")
    text = string.gsub(text, "&gt;", ">")
    text = string.gsub(text, "&lt;", "<")
    text = string.gsub(text, "&amp;", "&")
    text = string.gsub(text, "&quot;", '"')
    text = string.gsub(text, "&#39;", "'")
    return text
end

local function is_prompt_line(line)
    local stripped = strip_xml(line)
    stripped = stripped:match("^%s*(.-)%s*$") or ""
    return string.find(stripped, "^[a-zA-Z]?[a-zA-Z]?[a-zA-Z]?>$") ~= nil
end

local function sanitize_block(text)
    if not text or text == "" then return nil end
    local cleaned = strip_xml(text)
    local lines = {}
    for line in string.gmatch(cleaned .. "\n", "(.-)\n") do
        local trimmed = line:match("^(.-)%s*$") or ""
        if trimmed ~= "" and not is_prompt_line(trimmed) then
            table.insert(lines, trimmed)
        end
    end
    local result = table.concat(lines, "\n")
    result = result:match("^%s*(.-)%s*$") or ""
    if result == "" then return nil end
    return result
end

local function file_timestamp(path)
    if not File.exists(path) then return "unknown" end
    local mtime = File.mtime(path)
    if not mtime then return "unknown" end
    return os.date("!%Y-%m-%dT%H:%M:%SZ", mtime)
end

--------------------------------------------------------------------------------
-- Consent system
--------------------------------------------------------------------------------

local function load_consent()
    local path = consent_path()
    File.mkdir("data/gs4tools")
    if not File.exists(path) then return {} end
    local content = File.read(path)
    if not content or content == "" then return {} end
    local ok, result = pcall(Json.decode, content)
    if not ok then return {} end
    return result
end

local function save_consent(consent_map)
    File.mkdir("data/gs4tools")
    File.write(consent_path(), Json.encode(consent_map))
end

local function consent_granted()
    local consent = load_consent()
    return consent[character_key()] == true
end

local function grant_consent()
    local consent = load_consent()
    consent[character_key()] = true
    save_consent(consent)
    say("consent granted for " .. character_name())
end

local function revoke_consent()
    local consent = load_consent()
    consent[character_key()] = nil
    save_consent(consent)
    say("consent revoked for " .. character_name())
end

local function print_consent_prompt()
    say("before running, this script will:")
    say("1) send INFO START / SKILLS / EXP / SOCIETY / RESOURCES / ASC LIST / ASC MILESTONES / INV ENH ...")
    say("2) save raw capture data locally under scripts/data/gs4tools")
    say("3) build a URL with encoded data for gs4tools.com import")
    say("privacy: gs4tools.com is a static site and does not store submitted data")
    say("privacy: the site automatically saves imported data to your browser localStorage")
    say("if you agree, run: ;gs4tools allow")
    say("to cancel, do nothing. you can revoke later with: ;gs4tools revoke")
end

--------------------------------------------------------------------------------
-- Capture block: send a command, capture output via downstream hook
--------------------------------------------------------------------------------

local function capture_block(command, start_regex, opts)
    opts = opts or {}
    local timeout_seconds = opts.timeout or 20
    local idle_timeout = opts.idle_timeout or 0.35
    local require_prompt = opts.require_prompt or false

    local hook_name = "gs4tools_capture_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000))
    local output = {}
    local started = false
    local saw_prompt = false
    local last_activity = nil

    DownstreamHook.add(hook_name, function(line)
        local text = strip_xml(line or "")
        text = text:match("^(.-)%s*$") or ""
        if text == "" then return line end

        if started then
            if is_prompt_line(text) then
                saw_prompt = true
            else
                table.insert(output, text)
            end
            last_activity = os.time()
            return line
        end

        -- Use Regex object for pattern matching (supports alternation like Ruby)
        if start_regex:test(text) then
            started = true
            table.insert(output, text)
            last_activity = os.time()
        end
        return line
    end)

    put(command)

    local deadline = os.time() + timeout_seconds
    while os.time() < deadline do
        pause(0.05)
        if started and saw_prompt then break end
        if started and not require_prompt and last_activity then
            if (os.time() - last_activity) >= idle_timeout then break end
        end
    end

    DownstreamHook.remove(hook_name)

    if not started then return nil end

    while #output > 0 and is_prompt_line(output[#output]) do
        table.remove(output)
    end
    while #output > 0 and (output[#output]:match("^%s*$")) do
        table.remove(output)
    end

    local text = table.concat(output, "\n")
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil end
    return text
end

--------------------------------------------------------------------------------
-- Voln tracking logic
--------------------------------------------------------------------------------

local function parse_society_tracking(text)
    if not text or text == "" then return { society = nil, step = 0 } end
    if string.find(text, "not currently a member of any society") then
        return { society = nil, step = 0 }
    end

    -- Check the specific status line first (matches Ruby's lines.find approach)
    local society = nil
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        if string.find(line, "You are a member in the") then
            if string.find(line, "Order of Voln") then
                society = "voln"
            elseif string.find(line, "Council of Light") then
                society = "col"
            elseif string.find(line, "Guardians of Sunfist") then
                society = "sunfist"
            end
            break
        end
    end

    -- Fall back to scanning the entire text
    if not society then
        if string.find(text, "Order of Voln") then
            society = "voln"
        elseif string.find(text, "Council of Light") then
            society = "col"
        elseif string.find(text, "Guardians of Sunfist") then
            society = "sunfist"
        end
    end
    if not society then return { society = nil, step = 0 } end

    local step = 0
    local patterns = {
        "at step%s+(%d+)",
        "at rank%s+(%d+)",
        "current[l]?[y]? at step%s+(%d+)",
        "current[l]?[y]? at rank%s+(%d+)",
        "step%s+(%d+)%s+of%s+%d+",
        "rank%s+(%d+)%s+of%s+%d+",
    }
    for _, pat in ipairs(patterns) do
        local m = string.match(text, pat)
        if m then step = tonumber(m) or 0; break end
    end

    local max_step = (society == "voln") and 26 or 20
    step = math.max(0, math.min(step, max_step))
    return { society = society, step = step }
end

local function parse_resources_tracking(text)
    if not text or text == "" then return nil end
    local favor = string.match(text, "Voln Favor:%s*([%d,]+)")
        or string.match(text, "Favor:%s*([%d,]+)")
    if not favor then return nil end
    return { favor = tonumber((string.gsub(favor, ",", ""))) or 0 }
end

local function build_voln_tracking(society_text, resources_text, previous_payload, collected_at)
    local society_state = parse_society_tracking(society_text)
    local resources_state = parse_resources_tracking(resources_text)
    if society_state.society ~= "voln" then return nil end

    local current_step = society_state.step
    local current_favor = resources_state and resources_state.favor or nil

    local previous_voln = nil
    if type(previous_payload) == "table" and type(previous_payload.voln) == "table" then
        previous_voln = previous_payload.voln
    end

    local previous_step = previous_voln and tonumber(previous_voln.step) or 0
    local previous_baseline = nil
    if previous_voln and previous_voln.atLastStepChange ~= nil then
        previous_baseline = tonumber(previous_voln.atLastStepChange)
    end

    local history = {}
    if previous_voln and type(previous_voln.history) == "table" then
        for _, entry in ipairs(previous_voln.history) do
            if type(entry) == "table" then
                table.insert(history, {
                    step = tonumber(entry.step) or 0,
                    favor = entry.favor and tonumber(entry.favor) or nil,
                    previousStep = entry.previousStep and tonumber(entry.previousStep) or nil,
                    timestamp = tostring(entry.timestamp or ""),
                })
            end
        end
    end

    if #history == 0 and current_favor then
        table.insert(history, {
            step = current_step,
            favor = current_favor,
            previousStep = nil,
            timestamp = collected_at,
        })
    elseif current_step ~= previous_step and current_favor then
        table.insert(history, {
            step = current_step,
            favor = current_favor,
            previousStep = previous_step,
            timestamp = collected_at,
        })
    end

    local at_last_step_change
    if current_step ~= previous_step and current_favor then
        at_last_step_change = current_favor
    elseif previous_baseline then
        at_last_step_change = previous_baseline
    else
        for i = #history, 1, -1 do
            if history[i].step == current_step and history[i].favor then
                at_last_step_change = history[i].favor
                break
            end
        end
        if not at_last_step_change then
            at_last_step_change = current_favor
        end
    end

    return {
        society = "voln",
        step = current_step,
        favor = current_favor,
        atLastStepChange = at_last_step_change,
        history = history,
        lastUpdated = collected_at,
    }
end

--------------------------------------------------------------------------------
-- Load/Save payload
--------------------------------------------------------------------------------

local function load_payload()
    local path = data_path()
    if not File.exists(path) then return nil end
    local content = File.read(path)
    if not content or content == "" then return nil end
    local ok2, result = pcall(Json.decode, content)
    if not ok2 then
        say("could not parse " .. path)
        return nil
    end
    return result
end

local function save_payload(payload)
    local path = data_path()
    File.mkdir(data_dir())
    local json_str = Json.encode(payload)
    File.write(path, json_str)
    say("saved " .. path)
end

--------------------------------------------------------------------------------
-- Normalized profile (legacy compatibility)
--------------------------------------------------------------------------------

local function load_normalized_profile()
    local path = normalized_profile_path()
    if not File.exists(path) then return nil end
    local content = File.read(path)
    if not content or content == "" then return nil end
    local ok2, result = pcall(Json.decode, content)
    if not ok2 then
        say("could not load " .. path)
        return nil
    end
    return result
end

local function count_nonzero_skill_entries(skills)
    if type(skills) ~= "table" then return 0 end
    local count = 0
    for _, entry in ipairs(skills) do
        if type(entry) == "table" then
            if (tonumber(entry.finalRanks) or 0) > 0 or (tonumber(entry.ranks) or 0) > 0 then
                count = count + 1
            end
        end
    end
    return count
end

local function count_nonzero_ascension_abilities(abilities)
    if type(abilities) ~= "table" then return 0 end
    local count = 0
    for _, entry in ipairs(abilities) do
        if type(entry) == "table" then
            if (tonumber(entry.ranks) or 0) > 0 then
                count = count + 1
            end
        end
    end
    return count
end

local function summarize_normalized_profile(profile)
    say("legacy normalized profile:")
    say("  path: " .. normalized_profile_path())
    say("  last synced: " .. file_timestamp(normalized_profile_path()))
    say("  name: " .. (profile.name or "unknown"))
    say("  race/profession: " .. (profile.race or "unknown") .. " / " .. (profile.profession or "unknown"))
    say("  level: " .. tostring(profile.level or 0))
    say("  experience: " .. tostring(profile.experience or 0))
    say("  ascension exp: " .. tostring(profile.ascensionExperience or 0))
    say("  ascension milestones: " .. tostring(profile.ascensionMilestones or 0))
    say("  trained skills: " .. tostring(count_nonzero_skill_entries(profile.skills)))
    say("  ascension abilities trained: " .. tostring(count_nonzero_ascension_abilities(profile.ascensionAbilities)))
    local enh_state = profile.equipment and profile.equipment.enhancives or {}
    local imported = enh_state.importedSnapshot or {}
    local manual = enh_state.manualResolutions or {}
    say("  enhancive imported items: " .. tostring(type(imported.items) == "table" and #imported.items or 0))
    say("  enhancive unresolved: " .. tostring(type(imported.unresolved) == "table" and #imported.unresolved or 0))
    say("  enhancive manual resolutions: " .. tostring(type(manual.items) == "table" and #manual.items or 0))
end

--------------------------------------------------------------------------------
-- Collect blocks
--------------------------------------------------------------------------------

local function collect_all_blocks()
    say("collecting INFO START...")
    local info_start = capture_block("info start", RE_INFO_START, { timeout = 25 })

    say("collecting SKILLS...")
    local skills = capture_block("skills", RE_SKILLS, { timeout = 25 })

    say("collecting EXP...")
    local exp = capture_block("exp", RE_EXP, { timeout = 20 })

    say("collecting SOCIETY...")
    local society = capture_block("society", RE_SOCIETY, { timeout = 15, require_prompt = true })

    say("collecting RESOURCES...")
    local resources = capture_block("resources", RE_RESOURCES, { timeout = 10, require_prompt = true })

    say("collecting ASC LIST...")
    local asc_list = capture_block("asc list", RE_ASC_LIST, { timeout = 30 })

    say("collecting ASC MILESTONES...")
    local asc_milestones = capture_block("asc milestones", RE_ASC_MILESTONES, { timeout = 20 })

    say("collecting INV ENH LIST...")
    local enhancive_list = capture_block("inv enh list", RE_ENH_LIST, { timeout = 8, require_prompt = true })

    say("collecting INV ENH TOTALS...")
    local enhancive_totals = capture_block("inv enh totals", RE_ENH_TOTALS, { timeout = 8, require_prompt = true })

    say("collecting INV ENH TOTALS DETAILS...")
    local enhancive_totals_details = capture_block("inv enh totals details", RE_ENH_TOTALS, { timeout = 8, require_prompt = true })

    local previous_payload = load_payload()
    local collected_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

    local payload = {
        version = 2,
        character = character_name(),
        collectedAt = collected_at,
        blocks = {
            infoStart = info_start,
            skills = skills,
            exp = exp,
            society = society,
            resources = resources,
            ascList = asc_list,
            ascMilestones = asc_milestones,
            enhanciveList = enhancive_list,
            enhanciveTotals = enhancive_totals,
            enhanciveTotalsDetails = enhancive_totals_details,
        },
        voln = build_voln_tracking(society, resources, previous_payload, collected_at),
    }

    save_payload(payload)
    return payload
end

local function collect_voln_blocks()
    local existing_payload = load_payload() or {}
    local blocks = type(existing_payload.blocks) == "table" and existing_payload.blocks or {}

    say("collecting SOCIETY...")
    local society = capture_block("society", RE_SOCIETY, { timeout = 15, require_prompt = true })

    say("collecting RESOURCES...")
    local resources = capture_block("resources", RE_RESOURCES, { timeout = 10, require_prompt = true })

    blocks.society = society
    blocks.resources = resources

    local collected_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

    local payload = {
        version = math.max(tonumber(existing_payload.version) or 0, 2),
        character = existing_payload.character or character_name(),
        collectedAt = existing_payload.collectedAt,
        blocks = blocks,
        voln = build_voln_tracking(society, resources, existing_payload, collected_at),
    }

    save_payload(payload)
    say("updated Voln data")
    return payload
end

--------------------------------------------------------------------------------
-- Summarize
--------------------------------------------------------------------------------

local function present_block(payload, key)
    if not payload or not payload.blocks then return false end
    local value = payload.blocks[key]
    return type(value) == "string" and value ~= ""
end

local function summarize_payload(payload)
    say("character: " .. (payload.character or "unknown"))
    say("collectedAt: " .. (payload.collectedAt or "unknown"))
    say("infoStart: " .. (present_block(payload, "infoStart") and "yes" or "no"))
    say("skills: " .. (present_block(payload, "skills") and "yes" or "no"))
    say("exp: " .. (present_block(payload, "exp") and "yes" or "no"))
    say("society: " .. (present_block(payload, "society") and "yes" or "no"))
    say("resources: " .. (present_block(payload, "resources") and "yes" or "no"))
    say("ascList: " .. (present_block(payload, "ascList") and "yes" or "no"))
    say("ascMilestones: " .. (present_block(payload, "ascMilestones") and "yes" or "no"))
    say("enhanciveList: " .. (present_block(payload, "enhanciveList") and "yes" or "no"))
    say("enhanciveTotals: " .. (present_block(payload, "enhanciveTotals") and "yes" or "no"))
    say("enhanciveTotalsDetails: " .. (present_block(payload, "enhanciveTotalsDetails") and "yes" or "no"))
end

local function say_json_object(object)
    local json_str = Json.encode(object)
    for line in string.gmatch(json_str .. "\n", "(.-)\n") do
        say(line)
    end
end

--------------------------------------------------------------------------------
-- Set Voln baseline
--------------------------------------------------------------------------------

local function set_voln_baseline(raw_value)
    local payload = load_payload()
    if not payload then
        say("no saved raw capture found; run ;gs4tools collect voln first")
        return false
    end
    if not payload.voln or type(payload.voln) ~= "table" or payload.voln.society ~= "voln" then
        say("no Voln tracking found in the saved raw capture; run ;gs4tools collect voln first")
        return false
    end
    local text = (raw_value or ""):match("^%s*(.-)%s*$") or ""
    if text == "" or not string.find(text, "^%d+$") then
        say("usage: ;gs4tools voln baseline N")
        return false
    end
    local baseline = tonumber(text)
    payload.voln.atLastStepChange = baseline
    save_payload(payload)
    say("updated Voln changeover favor to " .. tostring(baseline))
    return true
end

--------------------------------------------------------------------------------
-- Compact payload + URL building
--------------------------------------------------------------------------------

local function compact_payload(payload)
    local blocks = payload.blocks or {}
    return {
        version = payload.version,
        character = payload.character,
        collectedAt = payload.collectedAt,
        voln = payload.voln,
        blocks = {
            infoStart = sanitize_block(blocks.infoStart),
            skills = sanitize_block(blocks.skills),
            exp = sanitize_block(blocks.exp),
            society = sanitize_block(blocks.society),
            ascList = sanitize_block(blocks.ascList),
            ascMilestones = sanitize_block(blocks.ascMilestones),
            enhanciveList = sanitize_block(blocks.enhanciveList),
            enhanciveTotals = sanitize_block(blocks.enhanciveTotals),
            enhanciveTotalsDetails = sanitize_block(blocks.enhanciveTotalsDetails),
        },
    }
end

local function build_open_url(base_url, payload, next_page_key)
    local encoded = Crypto.base64url_encode(Json.encode(payload))
    local params = "gstools=" .. encoded
    if next_page_key and next_page_key ~= "" then
        params = params .. "&next=" .. next_page_key
    end
    return base_url .. "#" .. params
end

local function open_payload_snapshot(payload, page_key)
    page_key = page_key or "profile"
    local compact = compact_payload(payload)
    local next_key = (page_key == "profile") and nil or page_key
    local url = build_open_url(DEFAULT_PROFILE_URL, compact, next_key)
    say("open this URL to import your data:")
    say(url)
    return url
end

local function open_page(page_key)
    local url = PAGE_URLS[page_key]
    if not url then
        say("unknown page '" .. page_key .. "'. valid pages: " .. table.concat((function()
            local keys = {}
            for k, _ in pairs(PAGE_URLS) do table.insert(keys, k) end
            table.sort(keys)
            return keys
        end)(), ", "))
        return false
    end
    say("open this URL: " .. url)
    return true
end

local function resolve_page_key(raw)
    if not raw or raw == "" then return "home" end
    local key = string.lower(raw)
    if PAGE_ALIASES[key] then return PAGE_ALIASES[key] end
    if PAGE_URLS[key] then return key end
    return key
end

--------------------------------------------------------------------------------
-- Status / Help
--------------------------------------------------------------------------------

local function show_status()
    say("version " .. VERSION)
    say("character: " .. character_name())
    say("consent: " .. (consent_granted() and "granted" or "not granted"))
    local path = data_path()
    if File.exists(path) then
        local payload = load_payload()
        if payload then
            say("saved data: " .. path)
            say("last collected: " .. (payload.collectedAt or "unknown"))
            if payload.voln and type(payload.voln) == "table" then
                say("voln tracking: step " .. (payload.voln.step or 0) ..
                    ", favor " .. tostring(payload.voln.favor or "unknown"))
            end
        end
    else
        say("saved data: none (" .. path .. ")")
    end
    if File.exists(normalized_profile_path()) then
        say("legacy normalized profile: " .. normalized_profile_path())
    end
end

local function show_usage()
    say("")
    say("usage:")
    say("  ;gs4tools                       # show status + help")
    say("  ;gs4tools collect               # capture all game data to disk")
    say("  ;gs4tools collect voln          # capture only Voln data (SOCIETY + RESOURCES)")
    say("  ;gs4tools open                  # show import URL for latest snapshot")
    say("  ;gs4tools open [page]           # show import URL redirected to page")
    say("  ;gs4tools open [page] --sync    # sync first, then show URL for target page")
    say("  ;gs4tools sync                  # collect and show profile import URL")
    say("  ;gs4tools sync [page]           # collect and show URL with redirect")
    say("  ;gs4tools voln baseline N       # set favor at last Voln step change")
    say("  ;gs4tools load                  # show local raw capture summary")
    say("  ;gs4tools load --raw            # print local raw capture JSON")
    say("  ;gs4tools show                  # print local raw capture path")
    say("  ;gs4tools allow                 # grant consent for automated collection/open")
    say("  ;gs4tools revoke                # revoke consent")
    say("  ;gs4tools help                  # this help")
    say("")
    say("pages: " .. table.concat((function()
        local keys = {}
        for k, _ in pairs(PAGE_URLS) do table.insert(keys, k) end
        table.sort(keys)
        return keys
    end)(), ", "))
    say("")
    say("privacy:")
    say("  gs4tools.com is a static page and does not store your data server-side")
    say("  this script stores data only locally under scripts/data/gs4tools")
    say("")
    say("note: first run requires explicit consent via ;gs4tools allow")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local raw_args = Script.vars[0] or ""
local args = {}
for word in string.gmatch(raw_args, "%S+") do
    table.insert(args, string.lower(word))
end

local action = (args[1] or "help")
local action_args = {}
for i = 2, #args do
    table.insert(action_args, args[i])
end

-- Check for --sync flag
local wants_sync = false
for _, a in ipairs(action_args) do
    if a == "--sync" then wants_sync = true end
end

-- Filter --sync out of action_args for page key resolution
local filtered_action_args = {}
for _, a in ipairs(action_args) do
    if a ~= "--sync" then
        table.insert(filtered_action_args, a)
    end
end

-- Consent check for commands that send game commands
local needs_consent = (action == "sync" or action == "collect" or (action == "open" and wants_sync))
if needs_consent and not consent_granted() then
    say("version " .. VERSION)
    print_consent_prompt()
    return
end

say("version " .. VERSION)

if action == "allow" or action == "consent" then
    grant_consent()

elseif action == "revoke" then
    revoke_consent()

elseif action == "collect" then
    local target = filtered_action_args[1] or ""
    if target == "voln" then
        collect_voln_blocks()
    elseif target == "" then
        local payload = collect_all_blocks()
        if payload then
            say("collection complete. Data saved to: " .. data_path())
        end
    else
        say("unknown collect target '" .. target .. "'. valid: voln (or blank for all)")
    end

elseif action == "open" then
    local page_key = filtered_action_args[1] and resolve_page_key(filtered_action_args[1]) or "profile"
    if wants_sync then
        local payload = collect_all_blocks()
        if payload then
            open_payload_snapshot(payload, page_key)
        end
    else
        local payload = load_payload()
        if payload then
            open_payload_snapshot(payload, page_key)
            if page_key ~= "profile" then
                say("redirected to " .. page_key)
            end
        else
            say("no saved data found; run ;gs4tools collect first")
        end
    end

elseif action == "sync" then
    local page_key = filtered_action_args[1] and resolve_page_key(filtered_action_args[1]) or "profile"
    local payload = collect_all_blocks()
    if payload then
        open_payload_snapshot(payload, page_key)
    end

elseif action == "load" then
    local show_raw = false
    for _, a in ipairs(action_args) do
        if a == "--raw" then show_raw = true end
    end

    if show_raw then
        local payload = load_payload()
        if payload then
            say_json_object(payload)
        else
            say("no saved raw capture found; run ;gs4tools sync first")
        end
    end

    local normalized = load_normalized_profile()
    if normalized then
        summarize_normalized_profile(normalized)
    end

    local payload = load_payload()
    if payload then
        say("raw capture:")
        say("  path: " .. data_path())
        say("  last collected: " .. (payload.collectedAt or file_timestamp(data_path())))
        local block_parts = {
            "infoStart=" .. (present_block(payload, "infoStart") and "yes" or "no"),
            "skills=" .. (present_block(payload, "skills") and "yes" or "no"),
            "exp=" .. (present_block(payload, "exp") and "yes" or "no"),
            "society=" .. (present_block(payload, "society") and "yes" or "no"),
            "resources=" .. (present_block(payload, "resources") and "yes" or "no"),
            "ascList=" .. (present_block(payload, "ascList") and "yes" or "no"),
            "ascMilestones=" .. (present_block(payload, "ascMilestones") and "yes" or "no"),
            "enhList=" .. (present_block(payload, "enhanciveList") and "yes" or "no"),
            "enhTotals=" .. (present_block(payload, "enhanciveTotals") and "yes" or "no"),
            "enhDetails=" .. (present_block(payload, "enhanciveTotalsDetails") and "yes" or "no"),
        }
        say("  blocks: " .. table.concat(block_parts, ", "))
        if payload.voln and type(payload.voln) == "table" then
            say("  voln: step=" .. tostring(payload.voln.step or 0) ..
                ", favor=" .. tostring(payload.voln.favor or "unknown") ..
                ", history=" .. tostring(payload.voln.history and #payload.voln.history or 0))
            say("        atLastStepChange=" .. tostring(payload.voln.atLastStepChange or "unknown"))
        end
    end

elseif action == "show" then
    say("raw capture: " .. data_path())
    if File.exists(normalized_profile_path()) then
        say("legacy normalized profile: " .. normalized_profile_path())
    end

elseif action == "voln" then
    local subcommand = filtered_action_args[1] or ""
    if subcommand == "baseline" then
        set_voln_baseline(filtered_action_args[2])
    elseif subcommand == "" then
        open_page("voln")
    else
        say("unknown voln subcommand '" .. subcommand .. "'. valid: baseline")
    end

elseif action == "status" then
    show_status()

elseif action == "help" or action == "--help" or action == "-h" then
    show_status()
    show_usage()

else
    local direct_page_key = resolve_page_key(action)
    if PAGE_URLS[direct_page_key] then
        open_page(direct_page_key)
    else
        show_status()
        show_usage()
    end
end
