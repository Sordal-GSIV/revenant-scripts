--- @revenant-script
--- name: symbiosis_cast
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Symbiosis training loop with spell cycling and cambrinth.
--- tags: moonmage, symbiosis, training
---
--- Converted from symbiosis-cast.lic

local spell_array = {"cv", "cv", "pg", "maf", "maf", "maf", "maf", "shadowling"}
local observations = {"perce mana", "predict weather", "obs yavash", "obs xibar", "obs katamba"}
local predictions = {"utility", "tactics", "defend", "2he", "outdoor"}
local appraisals = {"lorica", "gloves", "greave", "blade", "vamb", "targ", "bala"}

while true do
    for _, symb_spell in ipairs(spell_array) do
        for i = 1, 2 do
            pause(0.5); waitrt()
            fput("prep symbios")
            fput("prep " .. symb_spell .. " 10")
            fput("charge armband 15")
            pause(0.5); waitrt()
            fput("invoke armband")
            pause(0.5); waitrt()
            fput(observations[math.random(#observations)])
            pause(19); waitrt()
            fput("cast")
        end
        pause(0.5); waitrt()
        local pred = predictions[math.random(#predictions)]
        fput("align " .. pred)
        pause(0.5); waitrt()
        fput("predict future saaren " .. pred)
        pause(0.5); waitrt()
        fput("turn textbook")
        fput("study textbook")
        pause(0.5); waitrt()
        fput("app my " .. appraisals[math.random(#appraisals)] .. " careful")
        pause(0.5); waitrt()
    end
end
