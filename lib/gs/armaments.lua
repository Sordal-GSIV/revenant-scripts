--- Weapon/armor/shield lookup tables populated from Lich5 armaments data.
--- Source: lich-5/lib/gemstone/armaments/

local M = {}

---------------------------------------------------------------------------
-- Armor group definitions
---------------------------------------------------------------------------
M.ARMOR_GROUPS = {
    [1] = "Cloth",
    [2] = "Leather",
    [3] = "Scale",
    [4] = "Chain",
    [5] = "Plate",
}

---------------------------------------------------------------------------
-- Armor subgroup definitions (ASG 1-20)
---------------------------------------------------------------------------
M.ARMOR_SUBGROUPS = {
    [1]  = "Normal Clothing",
    [2]  = "Robes",
    [5]  = "Light Leather",
    [6]  = "Full Leather",
    [7]  = "Reinforced Leather",
    [8]  = "Double Leather",
    [9]  = "Leather Breastplate",
    [10] = "Cuirboulli Leather",
    [11] = "Studded Leather",
    [12] = "Brigandine Armor",
    [13] = "Chain Mail",
    [14] = "Double Chain",
    [15] = "Augmented Chain",
    [16] = "Chain Hauberk",
    [17] = "Metal Breastplate",
    [18] = "Augmented Plate",
    [19] = "Half Plate",
    [20] = "Full Plate",
}

---------------------------------------------------------------------------
-- Weapons table
-- Each entry: { category, base_name, damage_types, base_rt, min_rt }
-- damage_types = { slash, crush, puncture }
-- Keyed by lowercase base_name; aliases mapped to the same entry.
---------------------------------------------------------------------------
M.weapons = {}

local function register_weapon(entry)
    M.weapons[entry.base_name:lower()] = entry
    if entry.names then
        for _, alias in ipairs(entry.names) do
            local lc = alias:lower()
            if not M.weapons[lc] then
                M.weapons[lc] = entry
            end
        end
    end
end

-- Edged weapons
register_weapon({ category = "edged", base_name = "arrow", damage_types = { slash = 33.3, crush = 0.0, puncture = 66.7 }, base_rt = 5, min_rt = 4, names = {"arrow", "sitka"} })
register_weapon({ category = "edged", base_name = "backsword", damage_types = { slash = 50.0, crush = 16.7, puncture = 33.3 }, base_rt = 5, min_rt = 4, names = {"backsword", "mortuary sword", "riding sword", "sidesword"} })
register_weapon({ category = "edged", base_name = "bastard sword", damage_types = { slash = 66.7, crush = 33.3, puncture = 0.0 }, base_rt = 6, min_rt = 4, names = {"bastard sword", "cresset sword", "espadon", "war sword"} })
register_weapon({ category = "edged", base_name = "broadsword", damage_types = { slash = 50.0, crush = 16.7, puncture = 33.3 }, base_rt = 5, min_rt = 4, names = {"broadsword", "carp's tongue", "carp's-tongue", "flyssa", "goliah", "katzbalger", "kurzsax", "machera", "palache", "schiavona", "seax", "spadroon", "spatha", "talon sword", "xiphos"} })
register_weapon({ category = "edged", base_name = "dagger", damage_types = { slash = 33.3, crush = 0.0, puncture = 66.7 }, base_rt = 1, min_rt = 2, names = {"alfange", "basilard", "bodice dagger", "bodkin", "boot dagger", "bracelet dagger", "butcher knife", "cinquedea", "crescent dagger", "dagger", "dirk", "fantail dagger", "forked dagger", "gimlet knife", "kaiken", "kidney dagger", "knife", "kozuka", "krizta", "kubikiri", "misericord", "parazonium", "pavade", "poignard", "pugio", "push dagger", "scramasax", "sgian achlais", "sgian dubh", "sidearm-of-Onar", "spike", "stiletto", "tanto", "trail knife", "trailknife", "zirah bouk"} })
register_weapon({ category = "edged", base_name = "estoc", damage_types = { slash = 33.3, crush = 0.0, puncture = 66.7 }, base_rt = 4, min_rt = 4, names = {"estoc", "koncerz"} })
register_weapon({ category = "edged", base_name = "falchion", damage_types = { slash = 66.7, crush = 33.3, puncture = 0.0 }, base_rt = 5, min_rt = 4, names = {"falchion", "badelaire", "craquemarte", "falcata", "kiss-of-ivas", "khopesh", "kopis", "machete", "takouba", "warblade"} })
register_weapon({ category = "edged", base_name = "handaxe", damage_types = { slash = 33.3, crush = 66.7, puncture = 0.0 }, base_rt = 5, min_rt = 4, names = {"handaxe", "balta", "boarding axe", "broad axe", "cleaver", "crescent axe", "double-bit axe", "field-axe", "francisca", "hatchet", "hunting axe", "hunting hatchet", "ice axe", "limb-cleaver", "logging axe", "meat cleaver", "miner's axe", "moon axe", "ono", "raiding axe", "sparte", "splitting axe", "throwing axe", "taper", "tomahawk", "toporok", "waraxe"} })
register_weapon({ category = "edged", base_name = "katana", damage_types = { slash = 100.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 4, names = {"katana"} })
register_weapon({ category = "edged", base_name = "longsword", damage_types = { slash = 50.0, crush = 16.7, puncture = 33.3 }, base_rt = 4, min_rt = 4, names = {"longsword", "arming sword", "kaskara", "langsax", "langseax", "mekya t'rhet", "sheering sword", "tachi"} })
register_weapon({ category = "edged", base_name = "main gauche", damage_types = { slash = 33.3, crush = 0.0, puncture = 66.7 }, base_rt = 2, min_rt = 3, names = {"parrying dagger", "main gauche", "shield-sword", "sword-breaker"} })
register_weapon({ category = "edged", base_name = "rapier", damage_types = { slash = 33.3, crush = 0.0, puncture = 66.7 }, base_rt = 2, min_rt = 3, names = {"bilbo", "colichemarde", "epee", "fleuret", "foil", "rapier", "schlager", "tizona", "tock", "tocke", "tuck", "verdun"} })
register_weapon({ category = "edged", base_name = "scimitar", damage_types = { slash = 50.0, crush = 16.7, puncture = 33.3 }, base_rt = 4, min_rt = 4, names = {"scimitar", "charl's-tail", "cutlass", "disackn", "kilij", "palache", "sabre", "sapara", "shamshir", "yataghan"} })
register_weapon({ category = "edged", base_name = "short sword", damage_types = { slash = 33.3, crush = 33.3, puncture = 33.3 }, base_rt = 3, min_rt = 3, names = {"acinaces", "antler sword", "backslasher", "braquemar", "baselard", "chereb", "coustille", "gladius", "gladius graecus", "kris", "kukri", "Niima's-embrace", "sica", "wakizashi", "short sword", "shortsword", "short-sword"} })
register_weapon({ category = "edged", base_name = "whip-blade", damage_types = { slash = 100.0, crush = 0.0, puncture = 0.0 }, base_rt = 2, min_rt = 3, names = {"whip-blade", "whipblade"} })

-- Blunt weapons
register_weapon({ category = "blunt", base_name = "ball and chain", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 6, min_rt = 4, names = {"ball and chain", "binnol", "goupillon", "mace and chain"} })
register_weapon({ category = "blunt", base_name = "crowbill", damage_types = { slash = 0.0, crush = 50.0, puncture = 50.0 }, base_rt = 3, min_rt = 3, names = {"crowbill", "hakapik", "skull-piercer"} })
register_weapon({ category = "blunt", base_name = "cudgel", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 4, min_rt = 4, names = {"cudgel", "aklys", "baculus", "club", "jo stick", "lisan", "periperiu", "shillelagh", "tambara", "truncheon", "waihaka", "war club"} })
register_weapon({ category = "blunt", base_name = "leather whip", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 2, min_rt = 3, names = {"leather whip", "bullwhip", "cat o' nine tails", "signal whip", "single-tail whip", "training whip", "whip"} })
register_weapon({ category = "blunt", base_name = "mace", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 4, min_rt = 4, names = {"mace", "bulawa", "dhara", "flanged mace", "knee-breaker", "massuelle", "mattina", "nifa otti", "ox mace", "pernat", "quadrelle", "ridgemace", "studded mace"} })
register_weapon({ category = "blunt", base_name = "morning star", damage_types = { slash = 0.0, crush = 66.7, puncture = 33.3 }, base_rt = 5, min_rt = 4, names = {"morning star", "spiked mace", "holy water sprinkler", "spikestar"} })
register_weapon({ category = "blunt", base_name = "war hammer", damage_types = { slash = 0.0, crush = 66.7, puncture = 33.3 }, base_rt = 4, min_rt = 4, names = {"war hammer", "fang", "hammerbeak", "hoolurge", "horseman's hammer", "skull-crusher", "taavish"} })

-- Polearm weapons
register_weapon({ category = "polearm", base_name = "awl-pike", damage_types = { slash = 0.0, crush = 13.0, puncture = 87.0 }, base_rt = 9, min_rt = 4, names = {"awl-pike", "ahlspiess", "breach pike", "chest-ripper", "korseke", "military fork", "ranseur", "runka", "scaling fork", "spetum"} })
register_weapon({ category = "polearm", base_name = "halberd", damage_types = { slash = 33.3, crush = 33.3, puncture = 33.3 }, base_rt = 6, min_rt = 4, names = {"halberd", "atgeir", "bardiche", "bill", "brandestoc", "croc", "falcastra", "fauchard", "glaive", "godendag", "guisarme", "half moon", "half-moon", "hippe", "kerambit", "pole axe", "pole-axe", "scorpion", "scythe"} })
register_weapon({ category = "polearm", base_name = "Hammer of Kai", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 7, min_rt = 4, names = {"Hammer of Kai", "bovai", "longhammer", "polehammer", "spiked-hammer"} })
register_weapon({ category = "polearm", base_name = "jeddart-axe", damage_types = { slash = 50.0, crush = 50.0, puncture = 0.0 }, base_rt = 7, min_rt = 4, names = {"jeddart-axe", "beaked axe", "nagimaki", "poleaxe", "voulge"} })
register_weapon({ category = "polearm", base_name = "javelin", damage_types = { slash = 17.0, crush = 0.0, puncture = 83.0 }, base_rt = 4, min_rt = 5, names = {"javelin", "contus", "jaculum", "knopkierie", "lancea", "nage-yari", "pelta", "shail", "spiculum"} })
register_weapon({ category = "polearm", base_name = "lance", damage_types = { slash = 0.0, crush = 33.0, puncture = 67.0 }, base_rt = 9, min_rt = 4, names = {"lance", "framea", "pike", "sarissa", "sudis", "warlance", "warpike"} })
register_weapon({ category = "polearm", base_name = "naginata", damage_types = { slash = 33.3, crush = 33.3, puncture = 33.3 }, base_rt = 6, min_rt = 4, names = {"naginata", "swordstaff", "bladestaff"} })
register_weapon({ category = "polearm", base_name = "pilum", damage_types = { slash = 17.0, crush = 0.0, puncture = 83.0 }, base_rt = 3, min_rt = 3, names = {"pilum"} })
register_weapon({ category = "polearm", base_name = "spear", damage_types = { slash = 17.0, crush = 0.0, puncture = 83.0 }, base_rt = 5, min_rt = 4, names = {"angon", "atlatl", "boar spear", "cateia", "dory", "falarica", "gaesum", "gaizaz", "harpoon", "hasta", "partisan", "partizan", "pill spear", "spontoon", "verutum", "yari"} })
register_weapon({ category = "polearm", base_name = "trident", damage_types = { slash = 33.0, crush = 0.0, puncture = 67.0 }, base_rt = 5, min_rt = 4, names = {"trident", "fuscina", "magari-yari", "pitch fork", "pitchfork", "zinnor"} })

-- Two-handed weapons
register_weapon({ category = "two_handed", base_name = "battle axe", damage_types = { slash = 66.7, crush = 33.3, puncture = 0.0 }, base_rt = 8, min_rt = 4, names = {"battle axe", "adze", "balestarius", "battle-axe", "bearded axe", "doloire", "executioner's axe", "greataxe", "hektov sket", "kheten", "roa'ter axe", "tabar", "woodsman's axe"} })
register_weapon({ category = "two_handed", base_name = "claidhmore", damage_types = { slash = 50.0, crush = 50.0, puncture = 0.0 }, base_rt = 8, min_rt = 4, names = {"claidhmore"} })
register_weapon({ category = "two_handed", base_name = "flail", damage_types = { slash = 0.0, crush = 66.7, puncture = 33.3 }, base_rt = 7, min_rt = 4, names = {"flail", "military flail", "spiked-staff"} })
register_weapon({ category = "two_handed", base_name = "flamberge", damage_types = { slash = 50.0, crush = 50.0, puncture = 0.0 }, base_rt = 7, min_rt = 4, names = {"flamberge", "reaver", "wave-bladed sword", "sword-of-Phoen"} })
register_weapon({ category = "two_handed", base_name = "maul", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 7, min_rt = 4, names = {"maul", "battle hammer", "footman's hammer", "sledgehammer", "tetsubo"} })
register_weapon({ category = "two_handed", base_name = "military pick", damage_types = { slash = 0.0, crush = 33.3, puncture = 66.7 }, base_rt = 7, min_rt = 4, names = {"military pick", "bisacuta", "mining pick"} })
register_weapon({ category = "two_handed", base_name = "quarterstaff", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 3, min_rt = 3, names = {"quarterstaff", "bo stick", "staff", "toyak", "walking staff", "warstaff", "yoribo"} })
register_weapon({ category = "two_handed", base_name = "two-handed sword", damage_types = { slash = 50.0, crush = 50.0, puncture = 0.0 }, base_rt = 8, min_rt = 4, names = {"two-handed sword", "battlesword", "beheading sword", "bidenhander", "falx", "executioner's sword", "greatsword", "mekya ne'rutka", "no-dachi", "zweihander"} })
register_weapon({ category = "two_handed", base_name = "war mattock", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 7, min_rt = 4, names = {"war mattock", "mattock", "oncin", "pickaxe", "sabar"} })

-- Ranged weapons
register_weapon({ category = "ranged", base_name = "composite bow", damage_types = { slash = 66.6, crush = 0.0, puncture = 33.7 }, base_rt = 6, min_rt = 3, names = {"composite bow", "composite recurve bow", "lutk'azi"} })
register_weapon({ category = "ranged", base_name = "hand crossbow", damage_types = { slash = 66.6, crush = 0.0, puncture = 33.7 }, base_rt = 4, min_rt = 4, names = {"hand crossbow"} })
register_weapon({ category = "ranged", base_name = "heavy crossbow", damage_types = { slash = 66.6, crush = 0.0, puncture = 33.7 }, base_rt = 7, min_rt = 5, names = {"heavy crossbow", "heavy arbalest", "kut'ziko", "repeating crossbow", "siege crossbow"} })
register_weapon({ category = "ranged", base_name = "light crossbow", damage_types = { slash = 66.6, crush = 0.0, puncture = 33.7 }, base_rt = 6, min_rt = 4, names = {"light crossbow", "kut'zikokra", "light arbalest"} })
register_weapon({ category = "ranged", base_name = "long bow", damage_types = { slash = 66.6, crush = 0.0, puncture = 33.7 }, base_rt = 7, min_rt = 3, names = {"long bow", "long recurve bow", "longbow", "lutk'quoab", "yumi"} })
register_weapon({ category = "ranged", base_name = "short bow", damage_types = { slash = 66.6, crush = 0.0, puncture = 33.7 }, base_rt = 5, min_rt = 3, names = {"short bow", "short recurve bow"} })

-- Thrown weapons
register_weapon({ category = "thrown", base_name = "bola", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 5, min_rt = 2, names = {"bola", "bolas", "boleadoras", "kurutai", "weighted-cord"} })
register_weapon({ category = "thrown", base_name = "dart", damage_types = { slash = 0.0, crush = 0.0, puncture = 100.0 }, base_rt = 2, min_rt = 3, names = {"dart", "nagyka"} })
register_weapon({ category = "thrown", base_name = "discus", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 5, min_rt = 2, names = {"discus", "throwing disc", "disc"} })
register_weapon({ category = "thrown", base_name = "throwing net", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 7, min_rt = 3, names = {"throwing net"} })
register_weapon({ category = "thrown", base_name = "quoit", damage_types = { slash = 100.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 3, names = {"quoit", "bladed-ring", "bladed-disc", "bladed wheel", "battle-quoit", "chakram", "war-quoit"} })

-- Brawling weapons
register_weapon({ category = "brawling", base_name = "closed fist", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"closed fist"} })
register_weapon({ category = "brawling", base_name = "blackjack", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"blackjack", "bludgeon", "sap"} })
register_weapon({ category = "brawling", base_name = "cestus", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"cestus"} })
register_weapon({ category = "brawling", base_name = "fist-scythe", damage_types = { slash = 66.7, crush = 16.7, puncture = 16.6 }, base_rt = 3, min_rt = 3, names = {"fist-scythe", "hand-hook", "hook", "hook-claw", "kama", "sickle"} })
register_weapon({ category = "brawling", base_name = "hook-knife", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"hook-knife", "pit-knife", "sabiet"} })
register_weapon({ category = "brawling", base_name = "jackblade", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 2, min_rt = 3, names = {"jackblade", "slash-jack"} })
register_weapon({ category = "brawling", base_name = "paingrip", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"paingrip", "grab-stabber"} })
register_weapon({ category = "brawling", base_name = "sai", damage_types = { slash = 0.0, crush = 0.0, puncture = 100.0 }, base_rt = 2, min_rt = 3, names = {"sai", "jitte"} })
register_weapon({ category = "brawling", base_name = "knuckle-blade", damage_types = { slash = 66.7, crush = 33.3, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"knuckle-blade", "slash-fist"} })
register_weapon({ category = "brawling", base_name = "knuckle-duster", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"knuckle-duster", "knuckle-guard", "knuckles"} })
register_weapon({ category = "brawling", base_name = "razorpaw", damage_types = { slash = 100.0, crush = 0.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"razorpaw", "slap-slasher"} })
register_weapon({ category = "brawling", base_name = "tiger-claw", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"tiger-claw", "thrak-bite", "barbed claw"} })
register_weapon({ category = "brawling", base_name = "troll-claw", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 2, min_rt = 3, names = {"troll-claw", "bladed claw", "kumade", "wight-claw"} })
register_weapon({ category = "brawling", base_name = "yierka-spur", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 1, min_rt = 2, names = {"yierka-spur", "spike-fist"} })

-- Hybrid weapons
register_weapon({ category = "hybrid", base_name = "katar", damage_types = { slash = 33.3, crush = 0.0, puncture = 66.7 }, base_rt = 3, min_rt = 3, names = {"katar", "gauntlet-sword", "kunai", "manople", "paiscush", "pata", "slasher", "tvekre"} })

-- Natural weapons
register_weapon({ category = "natural", base_name = "bite", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"bite"} })
register_weapon({ category = "natural", base_name = "charge", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"charge"} })
register_weapon({ category = "natural", base_name = "claw", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"claw"} })
register_weapon({ category = "natural", base_name = "ensnare", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"ensnare"} })
register_weapon({ category = "natural", base_name = "impale", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"impale"} })
register_weapon({ category = "natural", base_name = "nip", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"nip"} })
register_weapon({ category = "natural", base_name = "pincer", damage_types = { slash = 0.0, crush = 0.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"pincer"} })
register_weapon({ category = "natural", base_name = "pound", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"pound"} })
register_weapon({ category = "natural", base_name = "stinger", damage_types = { slash = 0.0, crush = 0.0, puncture = 100.0 }, base_rt = 5, min_rt = 5, names = {"stinger"} })
register_weapon({ category = "natural", base_name = "stomp", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"stomp"} })
register_weapon({ category = "natural", base_name = "tail swing", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 5, min_rt = 5, names = {"tail swing"} })

-- Runestave
register_weapon({ category = "runestave", base_name = "runestave", damage_types = { slash = 0.0, crush = 100.0, puncture = 0.0 }, base_rt = 6, min_rt = 4, names = {"runestave", "asaya", "crook", "crosier", "pastoral staff", "rune staff", "runestaff", "scepter", "scepter-of-Lumnis", "staff-of-lumnis", "walking stick"} })

---------------------------------------------------------------------------
-- Armors table
-- Each entry: { armor_group, armor_sub_group, base_weight, action_penalty }
-- Keyed by lowercase base_name; aliases mapped to the same entry.
---------------------------------------------------------------------------
M.armors = {}

local function register_armor(entry)
    M.armors[entry.base_name:lower()] = entry
    if entry.names then
        for _, alias in ipairs(entry.names) do
            local lc = alias:lower()
            if not M.armors[lc] then
                M.armors[lc] = entry
            end
        end
    end
end

-- AG 1: Cloth
register_armor({ armor_group = 1, armor_sub_group = 1, base_name = "normal clothing", base_weight = 0, action_penalty = 0,
    names = {"normal clothing", "clothing", "clothes", "garb", "garments", "outfit", "attire", "ensemble"} })
register_armor({ armor_group = 1, armor_sub_group = 2, base_name = "robes", base_weight = 8, action_penalty = 0,
    names = {"robes", "robe", "vestments", "tunic"} })

-- AG 2: Leather
register_armor({ armor_group = 2, armor_sub_group = 5, base_name = "light leather", base_weight = 10, action_penalty = 0,
    names = {"light leather", "light leathers", "buffcoat", "casting leather", "casting leathers", "jack", "leather cyclas", "leather jerkin", "leather shirt", "leather tunic", "leather vest", "leather", "leathers", "hunts"} })
register_armor({ armor_group = 2, armor_sub_group = 6, base_name = "full leather", base_weight = 13, action_penalty = -1,
    names = {"full leather", "full leathers", "arming doublet", "buffcoat", "casting leather", "casting leathers", "leather shirt", "leather pourpoint", "leather", "leathers", "hunts"} })
register_armor({ armor_group = 2, armor_sub_group = 7, base_name = "reinforced leather", base_weight = 15, action_penalty = -5,
    names = {"reinforced leather", "reinforced leathers", "aketon", "arming coat", "arming doublet", "gambeson", "quilted leather", "leather", "leathers", "hunts"} })
register_armor({ armor_group = 2, armor_sub_group = 8, base_name = "double leather", base_weight = 16, action_penalty = -6,
    names = {"double leather", "double leathers", "aketon", "arming coat", "gambeson", "bodysuit", "leather", "leathers", "hunts"} })

-- AG 3: Scale
register_armor({ armor_group = 3, armor_sub_group = 9, base_name = "leather breastplate", base_weight = 16, action_penalty = -7,
    names = {"leather breastplate", "breastplate", "brigandine shirt", "corslet/corselet", "cuirass", "jack", "jerkin", "lamellar shirt", "scale", "scalemail", "tunic", "armor"} })
register_armor({ armor_group = 3, armor_sub_group = 10, base_name = "cuirboulli leather", base_weight = 17, action_penalty = -8,
    names = {"cuirboulli", "cuirboulli leather", "cuirboulli leathers", "brigandine shirt", "cuirass", "jerkin", "lamellar corslet/corselet", "lamellar shirt", "leather corslet/corselet", "scale", "scalemail", "tunic", "armor"} })
register_armor({ armor_group = 3, armor_sub_group = 11, base_name = "studded leather", base_weight = 20, action_penalty = -10,
    names = {"studded leather", "studded leathers", "splint leather", "splinted leather", "lamellar leather", "armor"} })
register_armor({ armor_group = 3, armor_sub_group = 12, base_name = "brigandine armor", base_weight = 25, action_penalty = -12,
    names = {"brigandine", "brigandine armor", "brigandine leather", "banded armor", "coat-of-plates", "jack-of-plates", "kuyak", "laminar armor", "lamellar armor", "scalemail", "splint armor", "splinted armor", "splint mail", "splinted mail", "armor"} })

-- AG 4: Chain
register_armor({ armor_group = 4, armor_sub_group = 13, base_name = "chain mail", base_weight = 25, action_penalty = -13,
    names = {"chain", "chainmail", "chain armor", "mail", "ringmail", "byrnie", "chain corslet/corselet", "chain shirt", "chain tunic"} })
register_armor({ armor_group = 4, armor_sub_group = 14, base_name = "double chain", base_weight = 25, action_penalty = -14,
    names = {"chain", "chainmail", "chain armor", "mail", "ringmail", "double chain", "double chainmail", "chain corslet/corselet", "chain shirt", "chain tunic", "haubergeon", "jazerant"} })
register_armor({ armor_group = 4, armor_sub_group = 15, base_name = "augmented chain", base_weight = 26, action_penalty = -16,
    names = {"chain", "chainmail", "chain armor", "mail", "ringmail", "augmented chain", "augmented chainmail", "haubergeon", "jazerant"} })
register_armor({ armor_group = 4, armor_sub_group = 16, base_name = "chain hauberk", base_weight = 27, action_penalty = -18,
    names = {"chain", "chainmail", "chain armor", "mail", "ringmail", "chain hauberk", "body armor", "hauberk", "jazerant hauberk"} })

-- AG 5: Plate
register_armor({ armor_group = 5, armor_sub_group = 17, base_name = "metal breastplate", base_weight = 23, action_penalty = -20,
    names = {"plate armor", "plate-and-mail", "metal breastplate", "breastplate", "cuirass", "disc armor", "mirror armor", "plate corslet", "plate corselet"} })
register_armor({ armor_group = 5, armor_sub_group = 18, base_name = "augmented plate", base_weight = 25, action_penalty = -25,
    names = {"plate armor", "plate-and-mail", "augmented breastplate", "breastplate", "coracia", "cuirass", "platemail", "plate corslet", "plate corselet"} })
register_armor({ armor_group = 5, armor_sub_group = 19, base_name = "half plate", base_weight = 50, action_penalty = -30,
    names = {"plate armor", "plate-and-mail", "half plate", "half-plate", "plate", "platemail"} })
register_armor({ armor_group = 5, armor_sub_group = 20, base_name = "full plate", base_weight = 75, action_penalty = -35,
    names = {"plate armor", "plate-and-mail", "full plate", "full platemail", "body armor", "field plate", "field platemail", "lasktol'zko", "plate", "platemail"} })

---------------------------------------------------------------------------
-- Shields table
-- Each entry: { category, base_weight, size_modifier, evade_modifier, names }
-- Keyed by lowercase base_name; aliases mapped to the same entry.
---------------------------------------------------------------------------
M.shields = {}

local function register_shield(entry)
    M.shields[entry.base_name:lower()] = entry
    if entry.names then
        for _, alias in ipairs(entry.names) do
            local lc = alias:lower()
            if not M.shields[lc] then
                M.shields[lc] = entry
            end
        end
    end
end

register_shield({ category = "small_shield", base_name = "small shield", base_weight = 6, size_modifier = -0.15, evade_modifier = -0.22,
    names = {"buckler", "kidney shield", "small shield", "targe"} })
register_shield({ category = "medium_shield", base_name = "medium shield", base_weight = 8, size_modifier = 0.0, evade_modifier = -0.30,
    names = {"battle shield", "heater", "heater shield", "knight's shield", "krytze", "lantern shield", "medium shield", "parma", "target shield"} })
register_shield({ category = "large_shield", base_name = "large shield", base_weight = 9, size_modifier = 0.15, evade_modifier = -0.38,
    names = {"aegis", "kite shield", "large shield", "pageant shield", "round shield", "scutum"} })
register_shield({ category = "tower_shield", base_name = "tower shield", base_weight = 12, size_modifier = 0.30, evade_modifier = -0.50,
    names = {"greatshield", "mantlet", "pavis", "tower shield", "wall shield"} })

---------------------------------------------------------------------------
-- Lookup API
---------------------------------------------------------------------------

--- Case-insensitive find across weapons, armors, and shields.
function M.find(name)
    if not name then return nil end
    local lower = name:lower()
    for _, store in ipairs({ M.weapons, M.armors, M.shields }) do
        local item = store[lower]
        if item then return item end
    end
    return nil
end

--- Return the type string for a named item.
function M.type_for(name)
    if not name then return nil end
    local lower = name:lower()
    if M.weapons[lower] then return "weapon" end
    if M.armors[lower]  then return "armor"  end
    if M.shields[lower] then return "shield" end
    return nil
end

--- Return the category for a named item, or nil.
function M.category_for(name)
    local item = M.find(name)
    if item then return item.category end
    return nil
end

--- List names, optionally filtered by type ("weapon", "armor", "shield").
function M.names(filter_type)
    local result = {}
    local seen = {}
    local stores = {
        weapon = M.weapons,
        armor  = M.armors,
        shield = M.shields,
    }
    local function collect(store)
        for key, _ in pairs(store) do
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = key
            end
        end
    end
    if filter_type then
        local store = stores[filter_type]
        if store then collect(store) end
    else
        for _, store in pairs(stores) do
            collect(store)
        end
    end
    table.sort(result)
    return result
end

return M
