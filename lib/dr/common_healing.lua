--- DRCH — DR Common Healing utilities.
-- Ported from Lich5 common-healing.rb (module DRCH).
-- Provides health checking, wound parsing, tending, and healing prioritization.
-- @module lib.dr.common_healing
local M = {}

-------------------------------------------------------------------------------
-- Constants: bleed rates, wound severity, lodged severity
-------------------------------------------------------------------------------

--- Maps bleed rate text from HEALTH to severity and tending skill requirements.
-- https://elanthipedia.play.net/Damage#Bleeding_Levels
M.BLEED_RATE_TO_SEVERITY = {
  ["tended"]                   = { severity = 1,  bleeding = false, skill_to_tend = nil, skill_to_tend_internal = nil },
  ["(tended)"]                 = { severity = 1,  bleeding = false, skill_to_tend = nil, skill_to_tend_internal = nil },
  ["clotted"]                  = { severity = 2,  bleeding = false, skill_to_tend = nil, skill_to_tend_internal = nil },
  ["clotted(tended)"]          = { severity = 3,  bleeding = false, skill_to_tend = nil, skill_to_tend_internal = nil },
  ["slight"]                   = { severity = 3,  bleeding = true,  skill_to_tend = 30,  skill_to_tend_internal = 600 },
  ["slight(tended)"]           = { severity = 4,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["light"]                    = { severity = 4,  bleeding = true,  skill_to_tend = 40,  skill_to_tend_internal = 600 },
  ["light(tended)"]            = { severity = 5,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["moderate"]                 = { severity = 5,  bleeding = true,  skill_to_tend = 50,  skill_to_tend_internal = 600 },
  ["moderate(tended)"]         = { severity = 6,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["bad"]                      = { severity = 6,  bleeding = true,  skill_to_tend = 60,  skill_to_tend_internal = 620 },
  ["bad(tended)"]              = { severity = 7,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["very bad"]                 = { severity = 7,  bleeding = true,  skill_to_tend = 75,  skill_to_tend_internal = 620 },
  ["very bad(tended)"]         = { severity = 8,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["heavy"]                    = { severity = 8,  bleeding = true,  skill_to_tend = 90,  skill_to_tend_internal = 640 },
  ["heavy(tended)"]            = { severity = 9,  bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["very heavy"]               = { severity = 9,  bleeding = true,  skill_to_tend = 105, skill_to_tend_internal = 640 },
  ["very heavy(tended)"]       = { severity = 10, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["severe"]                   = { severity = 10, bleeding = true,  skill_to_tend = 120, skill_to_tend_internal = 660 },
  ["severe(tended)"]           = { severity = 11, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["very severe"]              = { severity = 11, bleeding = true,  skill_to_tend = 140, skill_to_tend_internal = 660 },
  ["very severe(tended)"]      = { severity = 12, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["extremely severe"]         = { severity = 12, bleeding = true,  skill_to_tend = 160, skill_to_tend_internal = 700 },
  ["extremely severe(tended)"] = { severity = 13, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["profuse"]                  = { severity = 13, bleeding = true,  skill_to_tend = 180, skill_to_tend_internal = 800 },
  ["profuse(tended)"]          = { severity = 14, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["very profuse"]             = { severity = 14, bleeding = true,  skill_to_tend = 205, skill_to_tend_internal = 800 },
  ["very profuse(tended)"]     = { severity = 15, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["massive"]                  = { severity = 15, bleeding = true,  skill_to_tend = 230, skill_to_tend_internal = 850 },
  ["massive(tended)"]          = { severity = 16, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["gushing"]                  = { severity = 16, bleeding = true,  skill_to_tend = 255, skill_to_tend_internal = 850 },
  ["gushing(tended)"]          = { severity = 17, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["massive stream"]           = { severity = 17, bleeding = true,  skill_to_tend = 285, skill_to_tend_internal = 1000 },
  ["massive stream(tended)"]   = { severity = 18, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["gushing fountain"]         = { severity = 18, bleeding = true,  skill_to_tend = 285, skill_to_tend_internal = 1200 },
  ["gushing fountain(tended)"] = { severity = 19, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["uncontrollable"]           = { severity = 19, bleeding = true,  skill_to_tend = 400, skill_to_tend_internal = 1400 },
  ["uncontrollable(tended)"]   = { severity = 20, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["unbelievable"]             = { severity = 20, bleeding = true,  skill_to_tend = 500, skill_to_tend_internal = 1600 },
  ["unbelievable(tended)"]     = { severity = 21, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["beyond measure"]           = { severity = 21, bleeding = true,  skill_to_tend = 600, skill_to_tend_internal = 1750 },
  ["beyond measure(tended)"]   = { severity = 22, bleeding = true,  skill_to_tend = nil, skill_to_tend_internal = nil },
  ["death awaits"]             = { severity = 22, bleeding = true,  skill_to_tend = 700, skill_to_tend_internal = 1750 },
}

--- Lodged item depth to severity.
M.LODGED_SEVERITY = {
  ["loosely hanging"] = 1,
  ["shallowly"]       = 2,
  ["firmly"]          = 3,
  ["deeply"]          = 4,
  ["savagely"]        = 5,
}

--- Wound severity descriptions from PERCEIVE HEALTH.
M.WOUND_SEVERITY = {
  insignificant    = 1,
  negligible       = 2,
  minor            = 3,
  ["more than minor"]  = 4,
  harmful          = 5,
  ["very harmful"] = 6,
  damaging         = 7,
  ["very damaging"]= 8,
  severe           = 9,
  ["very severe"]  = 10,
  devastating      = 11,
  ["very devastating"] = 12,
  useless          = 13,
}

--- Parasite types (regex patterns).
M.PARASITES = {
  "blood mite", "leech", "blood worm", "retch maggot",
}

--- Wound severity patterns for HEALTH command output parsing.
-- Ordered from most specific to least specific for correct matching.
M.WOUND_SEVERITY_MAP = {
    { pattern = "gone",                 severity = 3 },
    { pattern = "useless",              severity = 3 },
    { pattern = "mangled",              severity = 3 },
    { pattern = "more than .* harmful", severity = 3 },
    { pattern = "severe",               severity = 3 },
    { pattern = "harmful",              severity = 2 },
    { pattern = "more than .* minor",   severity = 2 },
    { pattern = "minor",                severity = 1 },
    { pattern = "bruise",               severity = 1 },
    { pattern = "small",                severity = 1 },
}

--- Bleeder severity for HEALTH command (simple text matching).
M.BLEED_SEVERITY_MAP = {
    { pattern = "very heavy",  severity = 5 },
    { pattern = "heavy",       severity = 4 },
    { pattern = "moderate",    severity = 3 },
    { pattern = "light",       severity = 2 },
    { pattern = "slight",      severity = 1 },
}

--- Tend success patterns
M.TEND_SUCCESS = {
  "You skillfully tend", "You tend", "Roundtime",
}

--- Tend failure patterns
M.TEND_FAILURE = {
  "Tend what", "That area is not bleeding",
  "have nothing to tend", "too injured to tend",
  "You fumble",
}

--- Tend dislodge patterns
M.TEND_DISLODGE = {
  "You .* remove .* from",
}

-------------------------------------------------------------------------------
-- Wound data class
-------------------------------------------------------------------------------

--- Create a new Wound record.
-- @param opts table { body_part, severity, bleeding_rate, is_internal, is_scar, is_parasite, is_lodged_item }
-- @return table Wound object
function M.Wound(opts)
  opts = opts or {}
  return {
    body_part     = opts.body_part and opts.body_part:lower() or nil,
    severity      = opts.severity,
    bleeding_rate = opts.bleeding_rate and opts.bleeding_rate:lower() or nil,
    is_internal   = opts.is_internal or false,
    is_scar       = opts.is_scar or false,
    is_parasite   = opts.is_parasite or false,
    is_lodged_item = opts.is_lodged_item or false,

    bleeding = function(self)
      return self.bleeding_rate ~= nil
        and self.bleeding_rate ~= ""
        and self.bleeding_rate ~= "(tended)"
    end,

    tendable = function(self)
      if self.is_parasite then return true end
      if self.is_lodged_item then return true end
      if self.body_part and self.body_part:find("skin") then return false end
      if not self:bleeding() then return false end
      if self.bleeding_rate and Regex.test("tended|clotted", self.bleeding_rate) then
        return false
      end
      return M.skilled_to_tend_wound(self.bleeding_rate, self.is_internal)
    end,
  }
end

-------------------------------------------------------------------------------
-- HealthResult data class
-------------------------------------------------------------------------------

--- Create a new HealthResult record.
-- @param opts table { wounds, bleeders, parasites, lodged, poisoned, diseased, score, dead }
-- @return table HealthResult
function M.HealthResult(opts)
  opts = opts or {}
  return {
    wounds    = opts.wounds or {},
    bleeders  = opts.bleeders or {},
    parasites = opts.parasites or {},
    lodged    = opts.lodged or {},
    poisoned  = opts.poisoned or false,
    diseased  = opts.diseased or false,
    score     = opts.score or 0,
    dead      = opts.dead or false,
    vitality  = opts.vitality or 100,

    injured = function(self)
      return self.score > 0
    end,

    bleeding = function(self)
      for _, wounds in pairs(self.bleeders) do
        for _, w in ipairs(wounds) do
          if w:bleeding() then return true end
        end
      end
      return false
    end,

    has_tendable_bleeders = function(self)
      for _, wounds in pairs(self.bleeders) do
        for _, w in ipairs(wounds) do
          if w:tendable() then return true end
        end
      end
      return false
    end,
  }
end

-------------------------------------------------------------------------------
-- Health checking
-------------------------------------------------------------------------------

--- Check health using the HEALTH command.
-- @return HealthResult
function M.check_health()
  put("health")
  local lines = {}
  local timeout_at = os.time() + 5
  local collecting = false
  while os.time() < timeout_at do
    local line = get()
    if line then
      if Regex.test("Your body feels|You have|Bleeding", line) then
        collecting = true
      end
      if collecting then
        lines[#lines + 1] = DRC.strip_xml(line)
      end
      -- End on prompt
      if line:find("<prompt") then break end
    else
      pause(0.1)
    end
  end

  return M.parse_health_lines(lines)
end

--- Parse stripped HEALTH command output into a HealthResult.
-- @param health_lines table Array of plain text lines
-- @return HealthResult
function M.parse_health_lines(health_lines)
  local poisoned = false
  local diseased = false
  local wounds = {}    -- keyed by severity
  local bleeders = {}
  local parasites = {}
  local lodged = {}

  for _, line in ipairs(health_lines) do
    -- Disease
    if Regex.test("dormant infection|wounds are infected|open oozing sores", line) then
      diseased = true
    end
    -- Poison
    if Regex.test("poison|trouble breathing", line) then
      poisoned = true
    end
    -- Parasites
    for _, parasite in ipairs(M.PARASITES) do
      if line:find(parasite) then
        local bp = line:match("on your ([%w%s]*)")
        if not parasites[1] then parasites[1] = {} end
        parasites[1][#parasites[1] + 1] = M.Wound({ body_part = bp, severity = 1, is_parasite = true })
      end
    end
    -- Lodged items
    if line:find("lodged .* in") then
      for depth, sev in pairs(M.LODGED_SEVERITY) do
        if line:find(depth) then
          local bp = line:match("into? your ([%w%s]*)")
          if not lodged[sev] then lodged[sev] = {} end
          lodged[sev][#lodged[sev] + 1] = M.Wound({ body_part = bp, severity = sev, is_lodged_item = true })
        end
      end
    end

    -- Wounds (from HEALTH output: "Your body feels ... <part> has a <severity> wound")
    -- DR HEALTH shows each body part on its own line with wound and bleed info
    if line:find("wound") and not line:find("lodged") and not line:find("parasite") then
        -- Try to extract body part and wound severity
        for _, bp_pattern in ipairs({"(%w[%w%s]-)%s+has%s+a%s+", "(%w[%w%s]-)%s+have%s+a%s+"}) do
            local bp = line:match(bp_pattern)
            if bp then
                local severity = 0
                for _, entry in ipairs(M.WOUND_SEVERITY_MAP) do
                    if line:find(entry.pattern) then
                        severity = entry.severity
                        break
                    end
                end
                local is_internal = line:find("internal") ~= nil
                local is_scar = line:find("scar") ~= nil
                local wound = M.Wound({
                    body_part = bp,
                    severity = severity,
                    is_internal = is_internal,
                    is_scar = is_scar,
                })
                if not wounds[severity] then wounds[severity] = {} end
                table.insert(wounds[severity], wound)

                -- Check for bleeding on same line
                local bleed_rate = line:match("bleeding%s+(.-)%s*$") or line:match("bleeding%s+(.-)%s*[,.]")
                if bleed_rate then
                    local bleed_sev = 0
                    for _, entry in ipairs(M.BLEED_SEVERITY_MAP) do
                        if bleed_rate:find(entry.pattern) then
                            bleed_sev = entry.severity
                            break
                        end
                    end
                    -- Also look up in the full BLEED_RATE_TO_SEVERITY for exact text match
                    local exact = M.BLEED_RATE_TO_SEVERITY[bleed_rate]
                    if exact then bleed_sev = exact.severity end
                    local bleeder = M.Wound({
                        body_part = bp,
                        severity = bleed_sev,
                        bleeding_rate = bleed_rate,
                    })
                    if not bleeders[bleed_sev] then bleeders[bleed_sev] = {} end
                    table.insert(bleeders[bleed_sev], bleeder)
                end
                break
            end
        end
    end
  end

  local score = M.calculate_score(wounds)
  return M.HealthResult({
    wounds    = wounds,
    bleeders  = bleeders,
    parasites = parasites,
    lodged    = lodged,
    poisoned  = poisoned,
    diseased  = diseased,
    score     = score,
  })
end

--- Parse PERCEIVE HEALTH / TOUCH output into a HealthResult.
-- Different format from HEALTH — shows perceived wound severity and vitality.
-- @param lines table Array of stripped text lines
-- @return HealthResult
function M.parse_perceived_health_lines(lines)
    local wounds = {}
    local parasites = {}
    local lodged = {}
    local poisoned = false
    local diseased = false
    local dead = false
    local vitality = 100

    for _, line in ipairs(lines) do
        line = line:match("^%s*(.-)%s*$") -- trim

        -- Vitality parsing (upstream 8a65de0)
        local vit = line:match("has (%d+)%% vitality remaining")
        if vit then
            vitality = tonumber(vit)
        end

        -- Dead check
        if line:find("feel only an aching emptiness") then
            dead = true
        end

        -- Poison/disease
        if line:find("affected by .* poison") then poisoned = true end
        if line:find("affected by .* disease") then diseased = true end

        -- Perceived wound parsing
        if line:find("wound") or line:find("scar") then
            local part = line:match("the ([%w%s]+)$")
            if part then
                part = part:match("^(.-)%.?$")  -- strip trailing period
                local severity = 0
                for _, entry in ipairs(M.WOUND_SEVERITY_MAP) do
                    if line:find(entry.pattern) then
                        severity = entry.severity
                        break
                    end
                end
                local wound = M.Wound({
                    body_part = part,
                    severity = severity,
                    is_scar = line:find("scar") ~= nil,
                })
                if not wounds[severity] then wounds[severity] = {} end
                table.insert(wounds[severity], wound)
            end
        end

        -- Parasites in perceived output
        if line:find("parasite") then
            local part = line:match("on the ([%w%s]+)$") or line:match("in the ([%w%s]+)$")
            if part then
                part = part:match("^(.-)%.?$")
                local p = M.Wound({ body_part = part, severity = 1, is_parasite = true })
                if not parasites[1] then parasites[1] = {} end
                table.insert(parasites[1], p)
            end
        end

        -- Lodged items in perceived output
        if line:find("lodged") then
            local part = line:match("in the ([%w%s]+)$") or line:match("the ([%w%s]+)$")
            if part then
                part = part:match("^(.-)%.?$")
                local l = M.Wound({ body_part = part, severity = 1, is_lodged_item = true })
                if not lodged[1] then lodged[1] = {} end
                table.insert(lodged[1], l)
            end
        end
    end

    local score = M.calculate_score(wounds)

    return M.HealthResult({
        wounds = wounds,
        bleeders = {},   -- perceived output doesn't show bleeders
        parasites = parasites,
        lodged = lodged,
        poisoned = poisoned,
        diseased = diseased,
        score = score,
        dead = dead,
        vitality = vitality,
    })
end

--- Perceive own health (empath ability).
-- @return HealthResult|nil
function M.perceive_health()
    local result = DRC.bput("perceive health self",
        "You feel .* vitality remaining",
        "You feel completely fine",
        "You feel only an aching emptiness",
        "You don't have the ability to do that")
    if not result or result:find("don't have the ability") then
        return nil
    end
    local output = reget(20)
    return M.parse_perceived_health_lines(output)
end

--- Perceive another's health via TOUCH (empath ability).
-- @param target string Character name
-- @return HealthResult|nil
function M.perceive_health_other(target)
    local result = DRC.bput("touch " .. target,
        "has %d+%% vitality remaining",
        "in good shape",
        "feel only an aching emptiness",
        "You don't have the ability")
    if not result or result:find("don't have the ability") then
        return nil
    end
    local output = reget(20)
    return M.parse_perceived_health_lines(output)
end

--- Check if character has tendable bleeders.
-- @return boolean
function M.has_tendable_bleeders()
  return M.check_health():has_tendable_bleeders()
end

-------------------------------------------------------------------------------
-- Tending
-------------------------------------------------------------------------------

--- Bind (tend) a wound on a body part.
-- @param body_part string Body part to tend
-- @param person string|nil "my" or a player name (default "my")
-- @return boolean true if successfully tended
function M.bind_wound(body_part, person)
  person = person or "my"
  local all = {}
  for _, p in ipairs(M.TEND_SUCCESS) do all[#all + 1] = p end
  for _, p in ipairs(M.TEND_FAILURE) do all[#all + 1] = p end
  for _, p in ipairs(M.TEND_DISLODGE) do all[#all + 1] = p end

  local result = DRC.bput("tend " .. person .. " " .. body_part, unpack(all))
  if waitrt then waitrt() end

  -- Dislodge: dispose of the item and re-tend
  for _, p in ipairs(M.TEND_DISLODGE) do
    if result:find(p) then
      -- Dispose dislodged item
      local dislodged = result:match("remove .* ([%a]+) from")
      if dislodged and DRCI and DRCI.dispose_trash then
        DRCI.dispose_trash(dislodged)
      end
      return M.bind_wound(body_part, person)
    end
  end

  -- Check failure
  for _, p in ipairs(M.TEND_FAILURE) do
    if result:find(p) then return false end
  end

  return true
end

--- Unwrap bandages from a body part.
-- @param body_part string
-- @param person string|nil "my" or player name
function M.unwrap_wound(body_part, person)
  person = person or "my"
  DRC.bput("unwrap " .. person .. " " .. body_part,
    "You unwrap .* bandages", "That area is not tended",
    "You may undo the affects")
  if waitrt then waitrt() end
end

--- Check if the character has enough First Aid skill to tend a bleed rate.
-- @param bleed_rate string Bleed rate text
-- @param internal boolean Whether it's an internal bleeder
-- @return boolean
function M.skilled_to_tend_wound(bleed_rate, internal)
  if not bleed_rate then return false end
  local info = M.BLEED_RATE_TO_SEVERITY[bleed_rate]
  if not info then return false end

  local skill_key = internal and "skill_to_tend_internal" or "skill_to_tend"
  local min_skill = info[skill_key]
  if not min_skill then return false end

  if DRSkill and DRSkill.getrank then
    return DRSkill.getrank("First Aid") >= min_skill
  end
  return false
end

--- Compute a weighted summary score from wounds by severity.
-- Higher severity wounds contribute quadratically more.
-- @param wounds_by_severity table { severity => { Wound, ... } }
-- @return number Score
function M.calculate_score(wounds_by_severity)
  local score = 0
  for severity, wound_list in pairs(wounds_by_severity) do
    score = score + (severity * severity) * #wound_list
  end
  return score
end

return M
