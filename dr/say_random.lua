--- @revenant-script
--- name: say_random
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Periodically say random motivational quotes.
--- tags: roleplay, random, chat
--- Converted from say_random.lic

local phrases = {
    "The center holds. The falcon hears the falconer.",
    "Anyone who has never made a mistake has never tried anything new.",
    "All our dreams can come true if we have the courage to pursue them.",
    "It always seems impossible until its done.",
    "Live as if you were to die tomorrow. Learn as if you were to live forever.",
    "Simplicity is the ultimate sophistication.",
    "Do not fear going forward slowly, fear only to stand still.",
}

local adverbs = {"calmly", "thoughtfully", "wisely", "warmly", "earnestly", "brightly"}
local targets = {"Xinphinity", "Saaren", "Gherynn"}
local delays = {45, 60, 10, 120, 33, 41, 27, 15, 80, 70}

while true do
    local phrase = phrases[math.random(#phrases)]
    local adverb = adverbs[math.random(#adverbs)]
    local target = targets[math.random(#targets)]
    fput("'@" .. target .. " /" .. adverb .. " " .. phrase)
    pause(delays[math.random(#delays)])
end
