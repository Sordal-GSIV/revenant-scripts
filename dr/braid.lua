--- @revenant-script
--- name: braid
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Forage and braid for mechanical lore training.
--- tags: crafting, mechanical, braiding
--- Converted from braid.lic

local mat = Script.vars[1]
if not mat or (mat:lower() ~= "grass" and mat:lower() ~= "vine") then
    echo("Need a first variable: Grass or Vine") return
end

local function forage()
    waitrt(); fput("forage " .. mat); waitrt()
    fput("braid my " .. mat); pause(0.5); waitrt()
end

local function trash()
    waitrt()
    if checkright() then fput("put my " .. checkright() .. " in " .. (UserVars.waste or "bucket")) end
    if checkleft() then fput("put my " .. checkleft() .. " in " .. (UserVars.waste or "bucket")) end
end

before_dying(trash)

-- Find trash receptacle
UserVars.waste = UserVars.waste or "bucket"

forage()
while DRSkill.getxp("Mechanical Lore") < 34 do
    fput("braid my " .. mat)
    local line = get()
    if line and line:find("mistake") then
        waitrt(); fput("pull my " .. mat); waitrt()
    elseif line and (line:find("need to have") or line:find("Braid what")) then
        forage()
    end
    waitrt()
end
trash()
