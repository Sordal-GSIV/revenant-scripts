--- @revenant-script
--- name: spell_id
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Alert when spells activate or fall off - monitors game text for spell messages
--- tags: spells, alerts, monitoring, utility
---
--- Ported from Spell_ID.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;spell_id   - Run in background to show spell on/off alerts

-- Spell detection patterns organized by guild
local spell_alerts = {
    -- General
    { pattern = "Pale yellow sparks begin to flicker", msg = "EASE ON" },
    { pattern = "You feel a weight settle over you", msg = "EASE OFF" },
    { pattern = "coalescing into a translucent field", msg = "MAF ON" },
    { pattern = "shimmers with a weak yellow light", msg = "MAF OFF" },
    -- Cleric
    { pattern = "suddenly feel more limber", msg = "BENE ON" },
    { pattern = "unnatural strength grips your flesh", msg = "BF ON" },
    { pattern = "brilliant silver glow surrounds", msg = "BLESS ON" },
    { pattern = "swirling grey fog surrounds", msg = "COE ON" },
    { pattern = "Fractals of pale light materialize", msg = "HALO ON" },
    { pattern = "ghostly light dissipates", msg = "HALO OFF" },
    { pattern = "calm focus takes hold", msg = "MAPP ON" },
    { pattern = "warm sensation of security", msg = "MF ON" },
    { pattern = "bathed in a soft silver glow", msg = "MPP ON" },
    { pattern = "bathed in a soft white glow", msg = "PFE ON" },
    { pattern = "soft white nimbus .* dissipates", msg = "PFE OFF" },
    { pattern = "lucent sphere glistens around you", msg = "SOS ON" },
    { pattern = "lucent sphere fades", msg = "SOS OFF" },
    { pattern = "shaft of brilliant white light descends", msg = "VIGIL ON" },
    -- Empath
    { pattern = "muscles start to burn", msg = "AD ON" },
    { pattern = "vivacious energies .* focalize", msg = "AWAKEN ON" },
    { pattern = "sudden sensation of warmth", msg = "BS ON" },
    { pattern = "sudden wave of heat", msg = "FP ON" },
    { pattern = "Pride and confidence in your empathic", msg = "GOL ON" },
    { pattern = "Soft waves .* warm peach", msg = "REF ON" },
    { pattern = "Rutilant sparks of light encircle", msg = "REG ON" },
    { pattern = "tingling .* diminishes .* motes .* fade", msg = "REG OFF" },
    { pattern = "translucent sphere forms around you", msg = "SOP ON" },
    { pattern = "translucent sphere .* pops", msg = "SOP OFF" },
    -- Moon Mage
    { pattern = "color vision blossoms with new depth", msg = "AUS ON" },
    { pattern = "color vision returns to normal", msg = "AUS OFF" },
    { pattern = "Tendrils of blue%-white light", msg = "COL ON" },
    { pattern = "feel more aware of your environment", msg = "CV ON" },
    { pattern = "feel less aware of your environment", msg = "CV OFF" },
    { pattern = "Darkness falls over you like a cloak", msg = "DARK ON" },
    { pattern = "world around you brightens considerably", msg = "PG ON" },
    { pattern = "world around you returns to its mundane", msg = "PG OFF" },
    { pattern = "forces gathering .* protect you", msg = "PSY ON" },
    { pattern = "refractive field gathers .* hiding you", msg = "RF ON" },
    { pattern = "oddly in tune with the webs of fate", msg = "SEER ON" },
    { pattern = "no longer feel .* strong .* webs of fate", msg = "SEER OFF" },
    { pattern = "shifting plexus of glistening azure", msg = "SOD ON" },
    { pattern = "glistening azure lines fade", msg = "SOD OFF" },
    -- Paladin
    { pattern = "dull orange glow settles", msg = "AS ON" },
    { pattern = "dull orange glow fades", msg = "AS OFF" },
    { pattern = "glistening net of coiling tendrils", msg = "HES ON" },
    { pattern = "extra strength deserts you", msg = "HES OFF" },
    { pattern = "sudden rush of vibrant energy", msg = "HOW ON" },
    { pattern = "warm glow fades from around you", msg = "HOW OFF" },
    { pattern = "hair%-like threads", msg = "DIG ON" },
    { pattern = "inspiration wanes", msg = "DIG OFF" },
    { pattern = "weave a simple barrier", msg = "SP ON" },
    { pattern = "Soldier's Prayer slips away", msg = "SP OFF" },
    { pattern = "feel your courage bolstered", msg = "COUR ON" },
    { pattern = "extra courage slips away", msg = "COUR OFF" },
    { pattern = "blood begins to boil", msg = "RW ON" },
    { pattern = "feel your rage dissipate", msg = "RW OFF" },
    -- Ranger
    { pattern = "blend smoothly into your surroundings", msg = "BLEND ON" },
    { pattern = "fade into view for all to see", msg = "BLEND OFF" },
    { pattern = "gentle breeze .* faint emerald glow", msg = "BOON ON" },
    { pattern = "Cool waves of force shiver", msg = "CAIS ON" },
    { pattern = "lighter on your feet", msg = "CS ON" },
    { pattern = "agility and reflexes return to normal", msg = "CS OFF" },
    { pattern = "sounds .* grow quiet .* nature's canopy", msg = "NC ON" },
    { pattern = "nature's canopy retreats", msg = "NC OFF" },
    { pattern = "Dark stripes form", msg = "SOTT ON" },
    { pattern = "heightened reflexes .* slip back", msg = "SOTT OFF" },
    -- War Mage
    { pattern = "bubble of fresh air forms", msg = "AB ON" },
    { pattern = "cloak of aether folds", msg = "AC ON" },
    { pattern = "shimmering shield surrounds you", msg = "ES ON" },
    { pattern = "shimmering ethereal shield fades", msg = "ES OFF" },
    { pattern = "mantle of crackling .* flames", msg = "MOF ON" },
    { pattern = "feel steadier", msg = "SUF ON" },
    { pattern = "Sure Footing spell has worn off", msg = "SUF OFF" },
    { pattern = "harness the currents of air", msg = "SW ON" },
    { pattern = "winds surrounding you disperse", msg = "SW OFF" },
    { pattern = "veil of ice forms around you", msg = "VOI ON" },
    { pattern = "stiff breeze surrounds you .* cushioning", msg = "YS ON" },
    { pattern = "cushion of air .* start to deplete", msg = "YS ends in 30 seconds" },
}

echo("Spell ID monitor running. Watching for spell activations/expirations...")

while true do
    local line = get()
    if line then
        for _, alert in ipairs(spell_alerts) do
            if line:find(alert.pattern) then
                echo(" ^^^ " .. alert.msg .. " ^^^")
                break
            end
        end
    end
end
