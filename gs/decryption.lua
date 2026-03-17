--- @revenant-script
--- name: decryption
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Attempt to decode Tehir and Troll speech from game chat
--- tags: language,tehir,troll,decode,speech

local LEXICON_REVERSE = {
    umi = "one", ruu = "two", zhii = "three", vuad = "four",
    vufi = "five", zun = "six", zifim = "seven", iuhkt = "eight",
    mumi = "nine", rim = "ten", hraz = "plus", riz = "minus",
    imhda = "empty", torv = "half", va = "all", muma = "many",
    huame = "pound", riehkt = "lightweight", tiofa = "heavy",
    krio = "bread", eoriz = "dates", vutz = "figs", rio = "tea",
    gograz = "cactus", qude = "bird", zja = "sky", ["zhi-zja"] = "heavens",
    tou = "hail", zome = "sand/yellow", ["qot-zome"] = "desert",
    vyau = "fluid", ueke = "wood", ["ro-ueke"] = "tree", ruut = "twig",
    ahruut = "up twig", ["zja-ruut"] = "sky twig", deker = "root",
    ["mudah-ruut"] = "not-up-twig", tzaq = "shrub", ["zlo-ueke"] = "small-wood",
    vyuqid = "flower", vruuib = "bloom", hohid = "paper",
    eobj = "dark", tzou = "shadow", muhkt = "night", yuhkt = "light",
    kriehkt = "bright", virid = "finger", vubrium = "fiery",
    tud = "hot", gure = "cold", ["mud-gure"] = "warm", ah = "up",
    mudah = "down", iem = "in", uad = "out", mubzh = "north",
    zuazh = "south", iov = "east", qiv = "west", ufura = "ivory",
    gir = "black", tebriim = "green", bri = "red", krai = "blue",
    zuvid = "sister", qaiteke = "goodbye", teur = "god", tuame = "hound",
    yufi = "love", rufir = "lover", lodduoti = "marriage", zjof = "wind",
}

-- Basic reverse cipher map (Tehir-only)
local REVERSE_CIPHER = {
    o = "a", q = "b", g = "c", e = "d", i = "e",
    v = "f", t = "g", u = "h", j = "k", y = "l",
    l = "m", m = "n", h = "p", k = "q", d = "r",
    z = "s", r = "t", a = "u", f = "v", n = "x", s = "z",
}

local TEHIR_WORD_RE = Regex.new(
    "\\b(?:stidi|oyuoaz|eobj|zja|qaiteke|rim|zuvid|zome|vyuqid|teur|qorit)\\b"
)

local function reverse_tehir(text)
    local words = {}
    for w in text:lower():gmatch("%S+") do
        local clean = w:gsub("[^a-z%-]", "")
        if LEXICON_REVERSE[clean] then
            words[#words + 1] = LEXICON_REVERSE[clean]
        else
            local decoded = {}
            for c in clean:gmatch(".") do
                decoded[#decoded + 1] = REVERSE_CIPHER[c] or c
            end
            words[#words + 1] = table.concat(decoded)
        end
    end
    return table.concat(words, " ")
end

local function reverse_troll(_text)
    return "[trollish gibberish]"
end

while true do
    local line = get()
    if line then
        local speaker, speech = line:match("^(%w+) says, \"(.-)\"$")
        if speaker and speech then
            if TEHIR_WORD_RE:test(speech) then
                local english = reverse_tehir(speech)
                echo("--- " .. speaker .. " (Tehir): " .. english)
            elseif speech:find("[j']+[j']+[j']+") or speech:find("[gk]h") then
                local english = reverse_troll(speech)
                echo("--- " .. speaker .. " (Troll): " .. english)
            end
        end
    end
end
