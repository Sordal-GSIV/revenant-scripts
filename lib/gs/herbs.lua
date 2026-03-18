local M = {}

-- Full herb database extracted from eherbs.lic
-- Each entry: { name, type, short, drinkable, doses, location }
M.database = {
    -- Wehnimer's Landing / Solhaven / Northern Caravansary / Ta'Illistim / River's Rest
    { name = "some acantha leaf", type = "blood", short = "acantha leaf", drinkable = false, doses = 10, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some wolifrew lichen", type = "minor nerve wound", short = "wolifrew lichen", drinkable = false, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "bolmara potion", type = "major nerve wound", short = "bolmara potion", drinkable = true, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some woth flower", type = "major nerve scar", short = "woth flower", drinkable = false, doses = 2, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some torban leaf", type = "minor nerve scar", short = "torban leaf", drinkable = false, doses = 3, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some ambrominas leaf", type = "minor limb wound", short = "ambrominas leaf", drinkable = false, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some ephlox moss", type = "major limb wound", short = "ephlox moss", drinkable = false, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some cactacae spine", type = "minor limb scar", short = "cactacae spine", drinkable = false, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some calamia fruit", type = "major limb scar", short = "calamia fruit", drinkable = false, doses = 2, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "rose-marrow potion", type = "minor head wound", short = "rose-marrow potion", drinkable = true, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some aloeas stem", type = "major head wound", short = "aloeas stem", drinkable = false, doses = 2, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some haphip root", type = "minor head scar", short = "haphip root", drinkable = false, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "brostheras potion", type = "major head scar", short = "brostheras potion", drinkable = true, doses = 2, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some basal moss", type = "minor organ wound", short = "basal moss", drinkable = false, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some pothinir grass", type = "major organ wound", short = "pothinir grass", drinkable = false, doses = 2, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "talneo potion", type = "minor organ scar", short = "talneo potion", drinkable = true, doses = 4, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "wingstem potion", type = "major organ scar", short = "wingstem potion", drinkable = true, doses = 2, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "bur-clover potion", type = "missing eye", short = "bur-clover potion", drinkable = true, doses = 1, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },
    { name = "some sovyn clove", type = "severed limb", short = "sovyn clove", drinkable = false, doses = 1, location = {"Wehnimer's Landing", "Solhaven", "the Northern Caravansary", "Ta'Illistim"} },

    -- Solhaven bulk (Do Not Buy)
    { name = "bunch of acantha leaf", type = "blood", short = "bunch of acantha leaf", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "bunch of wolifrew lichen", type = "minor nerve wound", short = "bunch of wolifrew lichen", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "large bolmara potion", type = "major nerve wound", short = "large bolmara potion", drinkable = true, doses = 7, location = {"Do Not Buy"} },
    { name = "bunch of woth flower", type = "major nerve scar", short = "bunch of woth flower", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "bunch of torban leaf", type = "minor nerve scar", short = "bunch of torban leaf", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "bunch of ambrominas leaf", type = "minor limb wound", short = "bunch of ambrominas leaf", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "bunch of ephlox moss", type = "major limb wound", short = "bunch of ephlox moss", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "bunch of cactacae spine", type = "minor limb scar", short = "bunch of cactacae spine", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "bunch of calamia fruit", type = "major limb scar", short = "bunch of calamia fruit", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "large rose-marrow potion", type = "minor head wound", short = "large rose-marrow potion", drinkable = true, doses = 7, location = {"Do Not Buy"} },
    { name = "bunch of aloeas stem", type = "major head wound", short = "bunch of aloeas stem", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "bunch of haphip root", type = "minor head scar", short = "bunch of haphip root", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "large brostheras potion", type = "major head scar", short = "large brostheras potion", drinkable = true, doses = 7, location = {"Do Not Buy"} },
    { name = "bunch of basal moss", type = "minor organ wound", short = "bunch of basal moss", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "bunch of pothinir grass", type = "major organ wound", short = "bunch of pothinir grass", drinkable = false, doses = 50, location = {"Do Not Buy"} },
    { name = "large talneo potion", type = "minor organ scar", short = "large talneo potion", drinkable = true, doses = 7, location = {"Do Not Buy"} },
    { name = "large wingstem potion", type = "major organ scar", short = "large wingstem potion", drinkable = true, doses = 7, location = {"Do Not Buy"} },
    { name = "large bur-clover potion", type = "missing eye", short = "large bur-clover potion", drinkable = true, doses = 7, location = {"Do Not Buy"} },
    { name = "bunch of sovyn clove", type = "severed limb", short = "bunch of sovyn clove", drinkable = false, doses = 50, location = {"Do Not Buy"} },

    -- Ta'Vaalor
    { name = "tincture of acantha", type = "blood", short = "tincture of acantha", drinkable = true, doses = 10, location = {"Ta'Vaalor"} },
    { name = "tincture of ambrominas", type = "minor limb wound", short = "tincture of ambrominas", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of wolifrew", type = "minor nerve wound", short = "tincture of wolifrew", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of rose-marrow", type = "minor head wound", short = "tincture of rose-marrow", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of basal", type = "minor organ wound", short = "tincture of basal", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of ephlox", type = "major limb wound", short = "tincture of ephlox", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of bolmara", type = "major nerve wound", short = "tincture of bolmara", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of aloeas", type = "major head wound", short = "tincture of aloeas", drinkable = true, doses = 2, location = {"Ta'Vaalor"} },
    { name = "tincture of pothinir", type = "major organ wound", short = "tincture of pothinir", drinkable = true, doses = 2, location = {"Ta'Vaalor"} },
    { name = "tincture of cactacae", type = "minor limb scar", short = "tincture of cactacae", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of torban", type = "minor nerve scar", short = "tincture of torban", drinkable = true, doses = 3, location = {"Ta'Vaalor"} },
    { name = "tincture of haphip", type = "minor head scar", short = "tincture of haphip", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of talneo", type = "minor organ scar", short = "tincture of talneo", drinkable = true, doses = 4, location = {"Ta'Vaalor"} },
    { name = "tincture of calamia", type = "major limb scar", short = "tincture of calamia", drinkable = true, doses = 2, location = {"Ta'Vaalor"} },
    { name = "tincture of woth", type = "major nerve scar", short = "tincture of woth", drinkable = true, doses = 2, location = {"Ta'Vaalor"} },
    { name = "tincture of brostheras", type = "major head scar", short = "tincture of brostheras", drinkable = true, doses = 2, location = {"Ta'Vaalor"} },
    { name = "tincture of wingstem", type = "major organ scar", short = "tincture of wingstem", drinkable = true, doses = 2, location = {"Ta'Vaalor"} },
    { name = "tincture of bur-clover", type = "missing eye", short = "tincture of bur-clover", drinkable = true, doses = 1, location = {"Ta'Vaalor"} },
    { name = "tincture of sovyn", type = "severed limb", short = "tincture of sovyn", drinkable = true, doses = 1, location = {"Ta'Vaalor"} },

    -- Zul Logoth
    { name = "grey mushroom potion", type = "blood", short = "grey mushroom potion", drinkable = true, doses = 7, location = {"Zul Logoth"} },
    { name = "green mushroom potion", type = "blood", short = "green mushroom potion", drinkable = true, doses = 5, location = {"Zul Logoth"} },
    { name = "bubbling brown ale", type = "minor limb wound", short = "bubbling brown ale", drinkable = true, doses = 3, location = {"Zul Logoth"} },
    { name = "thick foggy ale", type = "minor nerve wound", short = "thick foggy ale", drinkable = true, doses = 3, location = {"Zul Logoth"} },
    { name = "rusty red ale", type = "minor head wound", short = "rusty red ale", drinkable = true, doses = 3, location = {"Zul Logoth"} },
    { name = "chunky black ale", type = "minor organ wound", short = "chunky black ale", drinkable = true, doses = 3, location = {"Zul Logoth"} },
    { name = "crushed cavegrass tea", type = "major limb wound", short = "crushed cavegrass tea", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "glowing mold tea", type = "major nerve wound", short = "glowing mold tea", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "sticky lichen tea", type = "major head wound", short = "sticky lichen tea", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "roasted ratweed tea", type = "major organ wound", short = "roasted ratweed tea", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "spotted toadstool ale", type = "minor limb scar", short = "spotted toadstool ale", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "dark frothing ale", type = "minor nerve scar", short = "dark frothing ale", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "dull crimson ale", type = "minor head scar", short = "dull crimson ale", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "brown weedroot ale", type = "minor organ scar", short = "brown weedroot ale", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "stalactite brew", type = "major limb scar", short = "stalactite brew", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "stalagmite brew", type = "major nerve scar", short = "stalagmite brew", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "stone soot brew", type = "major head scar", short = "stone soot brew", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "dirty crevice brew", type = "major organ scar", short = "dirty crevice brew", drinkable = true, doses = 2, location = {"Zul Logoth"} },
    { name = "dirty rat fur potion", type = "missing eye", short = "dirty rat fur potion", drinkable = true, doses = 1, location = {"Zul Logoth"} },
    { name = "grainy black potion", type = "severed limb", short = "grainy black potion", drinkable = true, doses = 1, location = {"Zul Logoth"} },
    { name = "milky white potion", type = "lifekeep", short = "milky white potion", drinkable = true, doses = 3, location = {"Zul Logoth"} },

    -- Cysaegir / Ravelin
    { name = "tincture of acantha", type = "blood", short = "tincture of acantha", drinkable = true, doses = 10, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of ambrominas", type = "minor limb wound", short = "tincture of ambrominas", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of wolifrew", type = "minor nerve wound", short = "tincture of wolifrew", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of rose-marrow", type = "minor head wound", short = "tincture of rose-marrow", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of basal", type = "minor organ wound", short = "tincture of basal", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of ephlox", type = "major limb wound", short = "tincture of ephlox", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of bolmara", type = "major nerve wound", short = "tincture of bolmara", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of aloeas", type = "major head wound", short = "tincture of aloeas", drinkable = true, doses = 2, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of pothinir", type = "major organ wound", short = "tincture of pothinir", drinkable = true, doses = 2, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of cactacae", type = "minor limb scar", short = "tincture of cactacae", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of torban", type = "minor nerve scar", short = "tincture of torban", drinkable = true, doses = 3, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of haphip", type = "minor head scar", short = "tincture of haphip", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of talneo", type = "minor organ scar", short = "tincture of talneo", drinkable = true, doses = 4, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of calamia", type = "major limb scar", short = "tincture of calamia", drinkable = true, doses = 2, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of woth", type = "major nerve scar", short = "tincture of woth", drinkable = true, doses = 2, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of brostheras", type = "major head scar", short = "tincture of brostheras", drinkable = true, doses = 2, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of wingstem", type = "major organ scar", short = "tincture of wingstem", drinkable = true, doses = 2, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of bur-clover", type = "missing eye", short = "tincture of bur-clover", drinkable = true, doses = 1, location = {"Cysaegir", "the hamlet of Ravelin"} },
    { name = "tincture of sovyn", type = "severed limb", short = "tincture of sovyn", drinkable = true, doses = 1, location = {"Cysaegir", "the hamlet of Ravelin"} },

    -- Ta'Illistim (Herbalist 2)
    { name = "tincture of acantha", type = "blood", short = "tincture of acantha", drinkable = true, doses = 20, location = {"Ta'Illistim"} },
    { name = "tincture of wolifrew", type = "minor nerve wound", short = "tincture of wolifrew", drinkable = true, doses = 20, location = {"Ta'Illistim"} },
    { name = "tincture of torban", type = "minor nerve scar", short = "tincture of torban", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of woth", type = "major nerve scar", short = "tincture of woth", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of ambrominas", type = "minor limb wound", short = "tincture of ambrominas", drinkable = true, doses = 20, location = {"Ta'Illistim"} },
    { name = "tincture of basal", type = "minor organ wound", short = "tincture of basal", drinkable = true, doses = 20, location = {"Ta'Illistim"} },
    { name = "tincture of ephlox", type = "major limb wound", short = "tincture of ephlox", drinkable = true, doses = 20, location = {"Ta'Illistim"} },
    { name = "tincture of pothinir", type = "major organ wound", short = "tincture of pothinir", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of aloeas", type = "major head wound", short = "tincture of aloeas", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of rose-marrow", type = "minor head wound", short = "tincture of rose-marrow", drinkable = true, doses = 20, location = {"Ta'Illistim"} },
    { name = "tincture of cactacae", type = "minor limb scar", short = "tincture of cactacae", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of calamia", type = "major limb scar", short = "tincture of calamia", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of haphip", type = "minor head scar", short = "tincture of haphip", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of brostheras", type = "major head scar", short = "tincture of brostheras", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of bolmara", type = "major nerve wound", short = "tincture of bolmara", drinkable = true, doses = 20, location = {"Ta'Illistim"} },
    { name = "tincture of talneo", type = "minor organ scar", short = "tincture of talneo", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of bur-clover", type = "missing eye", short = "tincture of bur-clover", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of wingstem", type = "major organ scar", short = "tincture of wingstem", drinkable = true, doses = 10, location = {"Ta'Illistim"} },
    { name = "tincture of sovyn", type = "severed limb", short = "tincture of sovyn", drinkable = true, doses = 10, location = {"Ta'Illistim"} },

    -- Teras (Kharam-Dzu)
    { name = "flagon of Olak's Ol'style ale", type = "blood", short = "Olak's Ol'style ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Olak's Ol'style ale", type = "blood", short = "Olak's Ol'style ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Lost Dogwater ale", type = "minor limb wound", short = "Lost Dogwater ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Lost Dogwater ale", type = "minor limb wound", short = "Lost Dogwater ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Orc's Head ale", type = "minor nerve wound", short = "Orc's Head ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Orc's Head ale", type = "minor nerve wound", short = "Orc's Head ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Semak's Smooth ale", type = "minor head wound", short = "Semak's Smooth ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Semak's Smooth ale", type = "minor head wound", short = "Semak's Smooth ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Mama Dwarf's ale", type = "minor organ wound", short = "Mama Dwarf's ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Mama Dwarf's ale", type = "minor organ wound", short = "Mama Dwarf's ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Bloody Krolvin ale", type = "blood", short = "Bloody Krolvin ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Bloody Krolvin ale", type = "blood", short = "Bloody Krolvin ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Golden Goose ale", type = "major limb wound", short = "Golden Goose ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Golden Goose ale", type = "major limb wound", short = "Golden Goose ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Kenar's Dropjaw ale", type = "major nerve wound", short = "Kenar's Dropjaw ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Kenar's Dropjaw ale", type = "major nerve wound", short = "Kenar's Dropjaw ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Dark Swampwater ale", type = "major head wound", short = "Dark Swampwater ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Dark Swampwater ale", type = "major head wound", short = "Dark Swampwater ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Aged Schooner ale", type = "major organ wound", short = "Aged Schooner ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Aged Schooner ale", type = "major organ wound", short = "Aged Schooner ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Bearded Ladies' ale", type = "minor limb scar", short = "Bearded Ladies' ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Bearded Ladies' ale", type = "minor limb scar", short = "Bearded Ladies' ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Miner's Muddy ale", type = "minor nerve scar", short = "Miner's Muddy ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Miner's Muddy ale", type = "minor nerve scar", short = "Miner's Muddy ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Agrak's Amber ale", type = "minor head scar", short = "Agrak's Amber ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Agrak's Amber ale", type = "minor head scar", short = "Agrak's Amber ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Gert's Homemade ale", type = "minor organ scar", short = "Gert's Homemade ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Gert's Homemade ale", type = "minor organ scar", short = "Gert's Homemade ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Mad Mutt Frothy ale", type = "major limb scar", short = "Mad Mutt Frothy ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Mad Mutt Frothy ale", type = "major limb scar", short = "Mad Mutt Frothy ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Dacra's Dream ale", type = "major nerve scar", short = "Dacra's Dream ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Dacra's Dream ale", type = "major nerve scar", short = "Dacra's Dream ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Reaper's Red ale", type = "major head scar", short = "Reaper's Red ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Reaper's Red ale", type = "major head scar", short = "Reaper's Red ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Wort's Winter ale", type = "major organ scar", short = "Wort's Winter ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Wort's Winter ale", type = "major organ scar", short = "Wort's Winter ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Volcano Vision ale", type = "missing eye", short = "Volcano Vision ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Volcano Vision ale", type = "missing eye", short = "Volcano Vision ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Captn' Pegleg's ale", type = "severed limb", short = "Captn' Pegleg's ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Captn' Pegleg's ale", type = "severed limb", short = "Captn' Pegleg's ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Dead Man's Pale ale", type = "lifekeep", short = "Dead Man's Pale ale", drinkable = true, doses = 3, location = {"the town of Kharam-Dzu"} },
    { name = "barrel of Dead Man's Pale ale", type = "lifekeep", short = "Dead Man's Pale ale", drinkable = true, doses = 10, location = {"the town of Kharam-Dzu"} },
    { name = "flagon of Dragon's Blood porter", type = "raisedead", short = "Dragon's Blood porter", drinkable = true, doses = 1, location = {"the town of Kharam-Dzu"} },

    -- Icemule Trace / Hinterwilds
    { name = "Dabbings Family special tart", type = "minor limb wound", short = "Family special tart", drinkable = false, doses = 10, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "Leaftoe's lichen tart", type = "minor nerve wound", short = "lichen tart", drinkable = false, doses = 10, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "candied ptarmigan feather", type = "severed limb", short = "ptarmigan feather", drinkable = false, doses = 1, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "earthworm potion", type = "major organ scar", short = "earthworm potion", drinkable = true, doses = 2, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "elk horn potion", type = "minor head wound", short = "elk horn potion", drinkable = true, doses = 4, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "gelatinous elk fat tart", type = "minor limb scar", short = "elk fat tart", drinkable = false, doses = 10, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "iceberry tart", type = "blood", short = "iceberry tart", drinkable = false, doses = 10, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "rock lizard potion", type = "minor organ scar", short = "rock lizard potion", drinkable = true, doses = 4, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "slice of Ma Leaftoe's Special", type = "minor nerve scar", short = "Ma Leaftoe's Special", drinkable = false, doses = 5, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "slice of pickled walrus blubber", type = "major limb scar", short = "pickled walrus blubber", drinkable = false, doses = 2, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "slice of sparrowhawk pie", type = "minor head scar", short = "sparrowhawk pie", drinkable = false, doses = 5, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "small egg and tundra grass tart", type = "minor organ wound", short = "tundra grass tart", drinkable = false, doses = 5, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "snowflake elixir", type = "major nerve wound", short = "snowflake elixir", drinkable = true, doses = 4, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "some frog's bone porridge", type = "major limb wound", short = "frog's bone porridge", drinkable = false, doses = 4, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "starfish potion", type = "missing eye", short = "starfish potion", drinkable = true, doses = 1, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "tiny cup of polar bear fat soup", type = "major head scar", short = "polar bear fat soup", drinkable = true, doses = 2, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "tiny flower-shaped tart", type = "major nerve scar", short = "flower-shaped tart", drinkable = false, doses = 2, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "tiny musk ox tart", type = "major organ wound", short = "musk ox tart", drinkable = false, doses = 2, location = {"Icemule Trace", "the Hinterwilds"} },
    { name = "tiny ram's bladder tart", type = "major head wound", short = "ram's bladder tart", drinkable = false, doses = 2, location = {"Icemule Trace", "the Hinterwilds"} },

    -- Pinefar Trading Post
    { name = "some acantha leaf tea", type = "blood", short = "acantha leaf tea", drinkable = true, doses = 10, location = {"the Pinefar Trading Post"} },
    { name = "some sweetfern tea", type = "minor limb wound", short = "sweetfern tea", drinkable = true, doses = 4, location = {"the Pinefar Trading Post"} },
    { name = "some red lichen tea", type = "minor nerve wound", short = "red lichen tea", drinkable = true, doses = 4, location = {"the Pinefar Trading Post"} },
    { name = "some feverfew tea", type = "minor head wound", short = "feverfew tea", drinkable = true, doses = 4, location = {"the Pinefar Trading Post"} },
    { name = "some ginkgo nut tea", type = "minor organ wound", short = "ginkgo nut tea", drinkable = true, doses = 4, location = {"the Pinefar Trading Post"} },
    { name = "some sassafras tea", type = "blood", short = "sassafras tea", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "sweetfern potion", type = "major limb wound", short = "sweetfern potion", drinkable = true, doses = 4, location = {"the Pinefar Trading Post"} },
    { name = "red lichen potion", type = "major nerve wound", short = "red lichen potion", drinkable = true, doses = 4, location = {"the Pinefar Trading Post"} },
    { name = "feverfew potion", type = "major head wound", short = "feverfew potion", drinkable = true, doses = 4, location = {"the Pinefar Trading Post"} },
    { name = "ginkgo nut potion", type = "major organ wound", short = "ginkgo nut potion", drinkable = true, doses = 4, location = {"the Pinefar Trading Post"} },
    { name = "manroot tea", type = "minor limb scar", short = "manroot tea", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "valerian root tea", type = "minor nerve scar", short = "valerian root tea", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "pennyroyal tea", type = "minor head scar", short = "pennyroyal tea", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "wyrmwood root tea", type = "minor organ scar", short = "wyrmwood root tea", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "manroot potion", type = "major limb scar", short = "manroot potion", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "valerian root potion", type = "major nerve scar", short = "valerian root potion", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "pennyroyal potion", type = "major head scar", short = "pennyroyal potion", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "wyrmwood root potion", type = "major organ scar", short = "wyrmwood root potion", drinkable = true, doses = 2, location = {"the Pinefar Trading Post"} },
    { name = "daggit root potion", type = "missing eye", short = "daggit root potion", drinkable = true, doses = 1, location = {"the Pinefar Trading Post"} },
    { name = "angelica root potion", type = "severed limb", short = "angelica root potion", drinkable = true, doses = 1, location = {"the Pinefar Trading Post"} },
    { name = "earwort potion", type = "disease", short = "earwort potion", drinkable = true, doses = 1, location = {"the Pinefar Trading Post"} },

    -- Kraken's Fall
    { name = "some acantha leaf", type = "blood", short = "acantha leaf", drinkable = false, doses = 10, location = {"Kraken's Fall"} },
    { name = "some wolifrew lichen", type = "minor nerve wound", short = "wolifrew lichen", drinkable = false, doses = 4, location = {"Kraken's Fall"} },
    { name = "some torban leaf", type = "minor nerve scar", short = "torban leaf", drinkable = false, doses = 4, location = {"Kraken's Fall"} },
    { name = "bolmara elixir", type = "major nerve wound", short = "bolmara elixir", drinkable = true, doses = 4, location = {"Kraken's Fall"} },
    { name = "some woth flower", type = "major nerve scar", short = "woth flower", drinkable = false, doses = 3, location = {"Kraken's Fall"} },
    { name = "rose-marrow elixir", type = "minor head wound", short = "rose-marrow elixir", drinkable = true, doses = 4, location = {"Kraken's Fall"} },
    { name = "some haphip root", type = "minor head scar", short = "haphip root", drinkable = false, doses = 4, location = {"Kraken's Fall"} },
    { name = "some aloeas stem", type = "major head wound", short = "aloeas stem", drinkable = false, doses = 2, location = {"Kraken's Fall"} },
    { name = "brostheras elixir", type = "major head scar", short = "brostheras elixir", drinkable = true, doses = 2, location = {"Kraken's Fall"} },
    { name = "ball of basal moss", type = "minor organ wound", short = "basal moss", drinkable = false, doses = 7, location = {"Kraken's Fall"} },
    { name = "talneo elixir", type = "minor organ scar", short = "talneo elixir", drinkable = true, doses = 4, location = {"Kraken's Fall"} },
    { name = "some pothinir grass", type = "major organ wound", short = "pothinir grass", drinkable = false, doses = 2, location = {"Kraken's Fall"} },
    { name = "wingstem elixir", type = "major organ scar", short = "wingstem elixir", drinkable = true, doses = 2, location = {"Kraken's Fall"} },
    { name = "some ambrominas leaf", type = "minor limb wound", short = "ambrominas leaf", drinkable = false, doses = 4, location = {"Kraken's Fall"} },
    { name = "some cactacae spine", type = "minor limb scar", short = "cactacae spine", drinkable = false, doses = 4, location = {"Kraken's Fall"} },
    { name = "ball of ephlox moss", type = "major limb wound", short = "ephlox moss", drinkable = false, doses = 4, location = {"Kraken's Fall"} },
    { name = "some calamia fruit", type = "major limb scar", short = "calamia fruit", drinkable = false, doses = 2, location = {"Kraken's Fall"} },
    { name = "cumin-rubbed sovyn clove", type = "severed limb", short = "sovyn clove", drinkable = false, doses = 1, location = {"Kraken's Fall"} },
    { name = "bur-clover elixir", type = "missing eye", short = "bur-clover elixir", drinkable = true, doses = 1, location = {"Kraken's Fall"} },

    -- Mist Harbor (Isle of Four Winds)
    { name = "some fragrant woth flower", type = "major nerve scar", short = "fragrant woth flower", drinkable = false, doses = 3, location = {"the Isle of Four Winds"} },
    { name = "some dirty haphip root", type = "minor head scar", short = "dirty haphip root", drinkable = false, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "sticky ball of basal moss", type = "minor organ wound", short = "ball of basal moss", drinkable = false, doses = 7, location = {"the Isle of Four Winds"} },
    { name = "gooey ball of ephlox moss", type = "major limb wound", short = "ball of ephlox moss", drinkable = false, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "some sugary ambrominas leaf", type = "minor limb wound", short = "sugary ambrominas leaf", drinkable = false, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "some fresh torban leaf", type = "minor nerve scar", short = "fresh torban leaf", drinkable = false, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "some spicy acantha leaf", type = "blood", short = "spicy acantha leaf", drinkable = false, doses = 10, location = {"the Isle of Four Winds"} },
    { name = "small sovyn clove", type = "severed limb", short = "small sovyn clove", drinkable = false, doses = 1, location = {"the Isle of Four Winds"} },
    { name = "some bright green pothinir grass", type = "major organ wound", short = "some bright pothinir grass", drinkable = false, doses = 2, location = {"the Isle of Four Winds"} },
    { name = "some withered aloeas stem", type = "major head wound", short = "withered aloeas stem", drinkable = false, doses = 2, location = {"the Isle of Four Winds"} },
    { name = "some ripe calamia fruit", type = "major limb scar", short = "ripe calamia fruit", drinkable = false, doses = 2, location = {"the Isle of Four Winds"} },
    { name = "some prickly cactacae spine", type = "minor limb scar", short = "prickly cactacae spine", drinkable = false, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "some dry wolifrew lichen", type = "minor nerve wound", short = "dry wolifrew lichen", drinkable = false, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "crystalline rose-marrow elixir", type = "minor head wound", short = "rose-marrow elixir", drinkable = true, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "crystalline talneo elixir", type = "minor organ scar", short = "talneo elixir", drinkable = true, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "crystalline brostheras elixir", type = "major head scar", short = "brostheras elixir", drinkable = true, doses = 2, location = {"the Isle of Four Winds"} },
    { name = "crystalline bolmara elixir", type = "major nerve wound", short = "bolmara elixir", drinkable = true, doses = 4, location = {"the Isle of Four Winds"} },
    { name = "crystalline wingstem elixir", type = "major organ scar", short = "wingstem elixir", drinkable = true, doses = 2, location = {"the Isle of Four Winds"} },
    { name = "crystalline bur-clover elixir", type = "missing eye", short = "bur-clover elixir", drinkable = true, doses = 1, location = {"the Isle of Four Winds"} },

    -- River's Rest
    { name = "beaker of malted winterberry brew", type = "minor head wound", short = "beaker of winterberry brew", drinkable = true, doses = 4, location = {"River's Rest"} },
    { name = "beaker of winterberry brew", type = "minor head wound", short = "winterberry brew", drinkable = true, doses = 4, location = {"River's Rest"} },

    -- Forageable
    { name = "yabathilium fruit", type = "blood", short = "yabathilium fruit", drinkable = false, doses = 1, location = {"Forageable"} },
    { name = "ochre-colored fungus", type = "poison", short = "ochre-colored fungus", drinkable = false, doses = 1, location = {"Forageable"} },
    { name = "red nettle berry", type = "poison", short = "red nettle berry", drinkable = false, doses = 1, location = {"Forageable"} },

    -- Skinnable
    { name = "pulsating firethorn shoot", type = "poison", short = "pulsating firethorn shoot", drinkable = false, doses = 1, location = {"Skinnable"} },

    -- Alchemical
    { name = "tincture of yabathilium", type = "blood", short = "tincture of yabathilium", drinkable = true, doses = 1, location = {"Alchemical"} },
    { name = "dimly glowing sky-blue potion", type = "disease", short = "sky-blue potion", drinkable = true, doses = 4, location = {"Alchemical"} },
    { name = "dimly glowing sea-green potion", type = "poison", short = "sea-green potion", drinkable = true, doses = 4, location = {"Alchemical"} },
}

function M.find_by_type(wound_type, opts)
    opts = opts or {}
    local location = opts.location

    -- First pass: prefer matching location + drinkable preference
    if location then
        for _, herb in ipairs(M.database) do
            if herb.type == wound_type and herb.location then
                local loc_match = false
                for _, loc in ipairs(herb.location) do
                    if loc == "Do Not Buy" then
                        loc_match = false
                        break
                    end
                    if loc:find(location, 1, true) or location:find(loc, 1, true) then
                        loc_match = true
                    end
                end
                if loc_match then
                    if opts.prefer_drinkable and herb.drinkable then return herb end
                    if opts.prefer_edible and not herb.drinkable then return herb end
                    if not opts.prefer_drinkable and not opts.prefer_edible then return herb end
                end
            end
        end
        -- Fallback: any herb at this location
        for _, herb in ipairs(M.database) do
            if herb.type == wound_type and herb.location then
                for _, loc in ipairs(herb.location) do
                    if loc ~= "Do Not Buy" and (loc:find(location, 1, true) or location:find(loc, 1, true)) then
                        return herb
                    end
                end
            end
        end
    end

    -- No location or no location match: use old behavior
    for _, herb in ipairs(M.database) do
        if herb.type == wound_type then
            local dominated = false
            if herb.location then
                for _, loc in ipairs(herb.location) do
                    if loc == "Do Not Buy" then dominated = true; break end
                end
            end
            if not dominated then
                if opts.prefer_drinkable and herb.drinkable then return herb end
                if opts.prefer_edible and not herb.drinkable then return herb end
                if not opts.prefer_drinkable and not opts.prefer_edible then return herb end
            end
        end
    end
    -- Last resort fallback: any herb of the type (excluding Do Not Buy)
    for _, herb in ipairs(M.database) do
        if herb.type == wound_type then
            local dominated = false
            if herb.location then
                for _, loc in ipairs(herb.location) do
                    if loc == "Do Not Buy" then dominated = true; break end
                end
            end
            if not dominated then return herb end
        end
    end
    return nil
end

--- Find all herbs available at a given location for a given type
function M.find_at_location(wound_type, location, opts)
    opts = opts or {}
    local results = {}
    for _, herb in ipairs(M.database) do
        if herb.type == wound_type and herb.location then
            for _, loc in ipairs(herb.location) do
                if loc ~= "Do Not Buy" and (loc:find(location, 1, true) or location:find(loc, 1, true)) then
                    if opts.drinkable_only and herb.drinkable then
                        results[#results + 1] = herb
                    elseif opts.edible_only and not herb.drinkable then
                        results[#results + 1] = herb
                    elseif not opts.drinkable_only and not opts.edible_only then
                        results[#results + 1] = herb
                    end
                    break
                end
            end
        end
    end
    return results
end

function M.is_drinkable(noun)
    local n = noun:lower()
    return n:find("potion") or n:find("tincture") or n:find("elixir") or n:find("tea")
        or n:find("ale") or n:find("soup") or n:find("brew") or n:find("porter")
        or n:find("flagon") or n:find("barrel")
end

function M.list_types()
    return {
        "blood", "poison", "disease", "lifekeep", "raisedead",
        "major head wound", "minor head wound",
        "major head scar", "minor head scar",
        "major nerve wound", "minor nerve wound",
        "major nerve scar", "minor nerve scar",
        "major organ wound", "minor organ wound",
        "major organ scar", "minor organ scar",
        "major limb wound", "minor limb wound",
        "major limb scar", "minor limb scar",
        "severed limb", "missing eye",
    }
end

return M
