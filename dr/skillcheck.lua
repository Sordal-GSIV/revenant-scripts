--- @revenant-script
--- name: skillcheck
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Check skill rank ranges and route to training.
--- tags: skills, training, routing
--- Converted from skillcheck.lic
local abbrevs = {se="small edged",le="large edged",["2he"]="twohanded edged",
    sb="small blunt",lb="large blunt",["2hb"]="twohanded blunt",
    lt="light thrown",ht="heavy thrown",braw="brawling",pole="polearms",
    stav="staves",offh="offhand weapon",tact="tactics",slin="slings",
    bow="bow",cros="crossbow",targ="targeted magic",debi="debilitation"}
local skill = Script.vars[1]
if not skill then echo("Usage: ;skillcheck <skill_abbrev>") return end
local exp_name = abbrevs[skill:lower()] or skill
echo("Checking skill level for: " .. exp_name)
echo("Requires locationfinder integration for routing.")
