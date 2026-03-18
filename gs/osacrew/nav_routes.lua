-- osacrew/nav_routes.lua
-- All sailing routes between the 9 origin cities.
-- Each entry is {{count, direction}, ...} pairs representing wheel turns.
-- The final pair is always {1, "port"} to dock.
-- Source: osacrew.lic lines 1482-1723 (sailing_from_* methods).

local routes = {}

-- ---------------------------------------------------------------------------
-- From Icemule Trace
-- ---------------------------------------------------------------------------
routes["Icemule Trace"] = {}
routes["Icemule Trace"]["Wehnimer's Landing"] = {
    {1,"southwest"},{4,"south"},{4,"southwest"},{1,"south"},
    {3,"southeast"},{3,"east"},{4,"southeast"},{1,"port"},
}
routes["Icemule Trace"]["Kharam Dzu"] = {
    {1,"southwest"},{4,"south"},{4,"southwest"},{1,"south"},
    {1,"southeast"},{20,"south"},{1,"southeast"},{6,"south"},
    {4,"southwest"},{3,"northwest"},{5,"west"},{4,"northwest"},
    {8,"west"},{1,"port"},
}
routes["Icemule Trace"]["Solhaven"] = {
    {1,"southwest"},{4,"south"},{4,"southwest"},{1,"south"},
    {1,"southeast"},{20,"south"},{5,"southeast"},{1,"port"},
}
routes["Icemule Trace"]["Brisker's Cove"] = {
    {1,"southwest"},{4,"south"},{4,"southwest"},{1,"south"},
    {1,"southeast"},{20,"south"},{1,"southeast"},{18,"south"},
    {8,"southeast"},{2,"east"},{1,"port"},
}
routes["Icemule Trace"]["Kraken's Fall"] = {
    {1,"southwest"},{4,"south"},{4,"southwest"},{1,"south"},
    {1,"southeast"},{20,"south"},{1,"southeast"},{7,"south"},
    {17,"southwest"},{4,"southeast"},{1,"east"},{1,"port"},
}
routes["Icemule Trace"]["River's Rest"] = {
    {1,"southwest"},{4,"south"},{4,"southwest"},{1,"south"},
    {1,"southeast"},{19,"south"},{14,"southeast"},{1,"port"},
}
routes["Icemule Trace"]["Nielira Harbor"] = {
    {1,"southwest"},{4,"south"},{4,"southwest"},{1,"south"},
    {1,"southeast"},{20,"south"},{1,"southeast"},{19,"south"},
    {13,"southeast"},{4,"south"},{11,"southwest"},{5,"south"},
    {6,"southwest"},{2,"south"},{1,"southwest"},{4,"south"},
    {2,"southeast"},{7,"east"},{4,"southeast"},{3,"northeast"},
    {4,"east"},{2,"northeast"},{7,"east"},{2,"southeast"},
    {5,"northeast"},{2,"north"},{2,"northwest"},{3,"north"},
    {6,"northwest"},{4,"northeast"},{3,"east"},{2,"northeast"},
    {1,"port"},
}
routes["Icemule Trace"]["Ta'Vaalor"] = {
    {1,"southwest"},{4,"south"},{4,"southwest"},{1,"south"},
    {1,"southeast"},{20,"south"},{1,"southeast"},{19,"south"},
    {13,"southeast"},{4,"south"},{11,"southwest"},{5,"south"},
    {6,"southwest"},{2,"south"},{1,"southwest"},{4,"south"},
    {2,"southeast"},{7,"east"},{4,"southeast"},{3,"northeast"},
    {4,"east"},{2,"northeast"},{7,"east"},{2,"southeast"},
    {5,"northeast"},{2,"north"},{2,"northwest"},{3,"north"},
    {6,"northwest"},{4,"northeast"},{4,"east"},{6,"northeast"},
    {12,"east"},{6,"northeast"},{6,"east"},{8,"northeast"},
    {4,"north"},{1,"port"},
}

-- ---------------------------------------------------------------------------
-- From Wehnimer's Landing
-- ---------------------------------------------------------------------------
routes["Wehnimer's Landing"] = {}
routes["Wehnimer's Landing"]["Icemule Trace"] = {
    {4,"northwest"},{3,"west"},{3,"northwest"},{1,"north"},
    {4,"northeast"},{4,"north"},{1,"northeast"},{1,"port"},
}
routes["Wehnimer's Landing"]["Kharam Dzu"] = {
    {4,"northwest"},{2,"west"},{2,"south"},{3,"southwest"},
    {15,"south"},{1,"southwest"},{4,"west"},{1,"southwest"},
    {1,"south"},{3,"southwest"},{2,"west"},{4,"northwest"},
    {8,"west"},{1,"port"},
}
routes["Wehnimer's Landing"]["Solhaven"] = {
    {4,"northwest"},{2,"west"},{2,"south"},{3,"southwest"},
    {13,"south"},{5,"southeast"},{1,"port"},
}
routes["Wehnimer's Landing"]["Brisker's Cove"] = {
    {4,"northwest"},{2,"west"},{2,"south"},{3,"southwest"},
    {13,"south"},{1,"southeast"},{18,"south"},{9,"southeast"},
    {1,"northeast"},{1,"port"},
}
routes["Wehnimer's Landing"]["Kraken's Fall"] = {
    {4,"northwest"},{2,"west"},{2,"south"},{3,"southwest"},
    {18,"south"},{1,"southeast"},{2,"south"},{14,"southwest"},
    {6,"south"},{1,"southeast"},{1,"east"},{1,"port"},
}
routes["Wehnimer's Landing"]["River's Rest"] = {
    {4,"northwest"},{2,"west"},{2,"south"},{3,"southwest"},
    {13,"south"},{1,"southeast"},{19,"south"},{14,"southeast"},
    {1,"port"},
}
routes["Wehnimer's Landing"]["Nielira Harbor"] = {
    {4,"northwest"},{2,"west"},{2,"south"},{3,"southwest"},
    {13,"south"},{1,"southeast"},{19,"south"},{13,"southeast"},
    {4,"south"},{11,"southwest"},{5,"south"},{6,"southwest"},
    {2,"south"},{1,"southwest"},{4,"south"},{2,"southeast"},
    {7,"east"},{4,"southeast"},{3,"northeast"},{4,"east"},
    {2,"northeast"},{7,"east"},{2,"southeast"},{5,"northeast"},
    {2,"north"},{2,"northwest"},{3,"north"},{6,"northwest"},
    {4,"northeast"},{3,"east"},{2,"northeast"},{1,"port"},
}
routes["Wehnimer's Landing"]["Ta'Vaalor"] = {
    {4,"northwest"},{2,"west"},{2,"south"},{3,"southwest"},
    {13,"south"},{1,"southeast"},{19,"south"},{13,"southeast"},
    {4,"south"},{11,"southwest"},{5,"south"},{6,"southwest"},
    {2,"south"},{1,"southwest"},{4,"south"},{2,"southeast"},
    {7,"east"},{4,"southeast"},{3,"northeast"},{4,"east"},
    {2,"northeast"},{7,"east"},{2,"southeast"},{5,"northeast"},
    {2,"north"},{2,"northwest"},{3,"north"},{6,"northwest"},
    {4,"northeast"},{4,"east"},{6,"northeast"},{12,"east"},
    {6,"northeast"},{6,"east"},{8,"northeast"},{4,"north"},
    {1,"port"},
}

-- ---------------------------------------------------------------------------
-- From Kharam Dzu (Teras Isle)
-- ---------------------------------------------------------------------------
routes["Kharam Dzu"] = {}
routes["Kharam Dzu"]["Icemule Trace"] = {
    {8,"east"},{4,"southeast"},{5,"east"},{3,"southeast"},
    {4,"northeast"},{6,"north"},{1,"northwest"},{20,"north"},
    {1,"northwest"},{1,"north"},{4,"northeast"},{4,"north"},
    {1,"northeast"},{1,"port"},
}
routes["Kharam Dzu"]["Wehnimer's Landing"] = {
    {8,"east"},{4,"southeast"},{2,"east"},{3,"northeast"},
    {1,"north"},{1,"northeast"},{4,"east"},{1,"northeast"},
    {15,"north"},{3,"northeast"},{2,"north"},{2,"east"},
    {4,"southeast"},{1,"port"},
}
routes["Kharam Dzu"]["Solhaven"] = {
    {8,"east"},{5,"southeast"},{9,"east"},{5,"northeast"},
    {1,"southeast"},{1,"port"},
}
routes["Kharam Dzu"]["Brisker's Cove"] = {
    {8,"east"},{4,"southeast"},{2,"east"},{8,"southeast"},
    {1,"south"},{10,"southeast"},{2,"east"},{1,"port"},
}
routes["Kharam Dzu"]["Kraken's Fall"] = {
    {1,"east"},{1,"southeast"},{15,"south"},{9,"southeast"},
    {1,"east"},{1,"port"},
}
routes["Kharam Dzu"]["River's Rest"] = {
    {7,"east"},{5,"southeast"},{3,"east"},{9,"southeast"},
    {2,"south"},{14,"southeast"},{1,"port"},
}
routes["Kharam Dzu"]["Nielira Harbor"] = {
    {7,"east"},{5,"southeast"},{3,"east"},{9,"southeast"},
    {2,"south"},{13,"southeast"},{4,"south"},{11,"southwest"},
    {5,"south"},{6,"southwest"},{2,"south"},{1,"southwest"},
    {4,"south"},{2,"southeast"},{7,"east"},{4,"southeast"},
    {3,"northeast"},{4,"east"},{2,"northeast"},{7,"east"},
    {2,"southeast"},{5,"northeast"},{2,"north"},{2,"northwest"},
    {3,"north"},{6,"northwest"},{4,"northeast"},{3,"east"},
    {2,"northeast"},{1,"port"},
}
routes["Kharam Dzu"]["Ta'Vaalor"] = {
    {7,"east"},{5,"southeast"},{3,"east"},{9,"southeast"},
    {2,"south"},{13,"southeast"},{4,"south"},{11,"southwest"},
    {5,"south"},{6,"southwest"},{2,"south"},{1,"southwest"},
    {4,"south"},{2,"southeast"},{7,"east"},{4,"southeast"},
    {3,"northeast"},{4,"east"},{2,"northeast"},{7,"east"},
    {2,"southeast"},{5,"northeast"},{2,"north"},{2,"northwest"},
    {3,"north"},{6,"northwest"},{4,"northeast"},{4,"east"},
    {6,"northeast"},{12,"east"},{6,"northeast"},{6,"east"},
    {8,"northeast"},{4,"north"},{1,"port"},
}

-- ---------------------------------------------------------------------------
-- From Solhaven
-- ---------------------------------------------------------------------------
routes["Solhaven"] = {}
routes["Solhaven"]["Icemule Trace"] = {
    {5,"northwest"},{20,"north"},{1,"northwest"},{1,"north"},
    {4,"northeast"},{4,"north"},{1,"northeast"},{1,"port"},
}
routes["Solhaven"]["Wehnimer's Landing"] = {
    {5,"northwest"},{13,"north"},{3,"northeast"},{2,"north"},
    {2,"east"},{4,"southeast"},{1,"port"},
}
routes["Solhaven"]["Kharam Dzu"] = {
    {1,"northwest"},{5,"southwest"},{9,"west"},{5,"northwest"},
    {8,"west"},{1,"port"},
}
routes["Solhaven"]["Brisker's Cove"] = {
    {1,"northwest"},{2,"southwest"},{14,"south"},{7,"southeast"},
    {2,"east"},{1,"port"},
}
routes["Solhaven"]["Kraken's Fall"] = {
    {1,"northwest"},{1,"southwest"},{1,"south"},{19,"southwest"},
    {4,"southeast"},{1,"east"},{1,"port"},
}
routes["Solhaven"]["River's Rest"] = {
    {1,"northwest"},{3,"southwest"},{13,"south"},{14,"southeast"},
    {1,"port"},
}
routes["Solhaven"]["Nielira Harbor"] = {
    {1,"northwest"},{3,"southwest"},{13,"south"},{13,"southeast"},
    {4,"south"},{11,"southwest"},{5,"south"},{6,"southwest"},
    {2,"south"},{1,"southwest"},{4,"south"},{2,"southeast"},
    {7,"east"},{4,"southeast"},{3,"northeast"},{4,"east"},
    {2,"northeast"},{7,"east"},{2,"southeast"},{5,"northeast"},
    {2,"north"},{2,"northwest"},{3,"north"},{6,"northwest"},
    {4,"northeast"},{3,"east"},{2,"northeast"},{1,"port"},
}
routes["Solhaven"]["Ta'Vaalor"] = {
    {1,"northwest"},{3,"southwest"},{13,"south"},{13,"southeast"},
    {4,"south"},{11,"southwest"},{5,"south"},{6,"southwest"},
    {2,"south"},{1,"southwest"},{4,"south"},{2,"southeast"},
    {7,"east"},{4,"southeast"},{3,"northeast"},{4,"east"},
    {2,"northeast"},{7,"east"},{2,"southeast"},{5,"northeast"},
    {2,"north"},{2,"northwest"},{3,"north"},{6,"northwest"},
    {4,"northeast"},{4,"east"},{6,"northeast"},{12,"east"},
    {6,"northeast"},{6,"east"},{8,"northeast"},{4,"north"},
    {1,"port"},
}

-- ---------------------------------------------------------------------------
-- From Brisker's Cove
-- ---------------------------------------------------------------------------
routes["Brisker's Cove"] = {}
routes["Brisker's Cove"]["Icemule Trace"] = {
    {3,"west"},{7,"northwest"},{19,"north"},{1,"northwest"},
    {20,"north"},{1,"northwest"},{1,"north"},{4,"northeast"},
    {4,"north"},{1,"northeast"},{1,"port"},
}
routes["Brisker's Cove"]["Wehnimer's Landing"] = {
    {1,"southwest"},{9,"northwest"},{18,"north"},{1,"northwest"},
    {13,"north"},{3,"northeast"},{2,"north"},{2,"east"},
    {4,"southeast"},{1,"port"},
}
routes["Brisker's Cove"]["Kharam Dzu"] = {
    {2,"west"},{10,"northwest"},{1,"north"},{8,"northwest"},
    {2,"west"},{4,"northwest"},{8,"west"},{1,"port"},
}
routes["Brisker's Cove"]["Solhaven"] = {
    {2,"west"},{7,"northwest"},{14,"north"},{2,"northeast"},
    {1,"southeast"},{1,"port"},
}
routes["Brisker's Cove"]["Kraken's Fall"] = {
    {2,"west"},{8,"northwest"},{1,"north"},{5,"northwest"},
    {12,"southwest"},{3,"southeast"},{1,"east"},{1,"port"},
}
routes["Brisker's Cove"]["River's Rest"] = {
    {1,"west"},{1,"southwest"},{6,"southeast"},{1,"port"},
}
routes["Brisker's Cove"]["Nielira Harbor"] = {
    {1,"west"},{1,"southwest"},{5,"southeast"},{4,"south"},
    {11,"southwest"},{5,"south"},{6,"southwest"},{2,"south"},
    {1,"southwest"},{4,"south"},{2,"southeast"},{7,"east"},
    {4,"southeast"},{3,"northeast"},{4,"east"},{2,"northeast"},
    {7,"east"},{2,"southeast"},{5,"northeast"},{2,"north"},
    {2,"northwest"},{3,"north"},{6,"northwest"},{4,"northeast"},
    {3,"east"},{2,"northeast"},{1,"port"},
}
routes["Brisker's Cove"]["Ta'Vaalor"] = {
    {1,"west"},{1,"southwest"},{5,"southeast"},{4,"south"},
    {11,"southwest"},{5,"south"},{6,"southwest"},{2,"south"},
    {1,"southwest"},{4,"south"},{2,"southeast"},{7,"east"},
    {4,"southeast"},{3,"northeast"},{4,"east"},{2,"northeast"},
    {7,"east"},{2,"southeast"},{5,"northeast"},{2,"north"},
    {2,"northwest"},{3,"north"},{6,"northwest"},{4,"northeast"},
    {4,"east"},{6,"northeast"},{12,"east"},{6,"northeast"},
    {6,"east"},{8,"northeast"},{4,"north"},{1,"port"},
}

-- ---------------------------------------------------------------------------
-- From Kraken's Fall
-- ---------------------------------------------------------------------------
routes["Kraken's Fall"] = {}
routes["Kraken's Fall"]["Icemule Trace"] = {
    {1,"west"},{4,"northwest"},{17,"northeast"},{7,"north"},
    {1,"northwest"},{20,"north"},{1,"northwest"},{1,"north"},
    {4,"northeast"},{4,"north"},{1,"northeast"},{1,"port"},
}
routes["Kraken's Fall"]["Wehnimer's Landing"] = {
    {1,"west"},{1,"northwest"},{6,"north"},{14,"northeast"},
    {2,"north"},{1,"northwest"},{18,"north"},{3,"northeast"},
    {2,"north"},{2,"east"},{4,"southeast"},{1,"port"},
}
routes["Kraken's Fall"]["Kharam Dzu"] = {
    {1,"west"},{9,"northwest"},{15,"north"},{1,"northwest"},
    {1,"west"},{1,"port"},
}
routes["Kraken's Fall"]["Solhaven"] = {
    {1,"west"},{4,"northwest"},{19,"northeast"},{1,"north"},
    {1,"northeast"},{1,"southeast"},{1,"port"},
}
routes["Kraken's Fall"]["Brisker's Cove"] = {
    {1,"west"},{3,"northwest"},{12,"northeast"},{5,"southeast"},
    {1,"south"},{8,"southeast"},{2,"east"},{1,"port"},
}
routes["Kraken's Fall"]["River's Rest"] = {
    {1,"west"},{4,"northwest"},{12,"northeast"},{5,"southeast"},
    {1,"south"},{14,"southeast"},{1,"south"},{1,"port"},
}
routes["Kraken's Fall"]["Nielira Harbor"] = {
    {1,"south"},{4,"southeast"},{5,"south"},{10,"southeast"},
    {4,"south"},{6,"southwest"},{2,"south"},{1,"southwest"},
    {4,"south"},{2,"southeast"},{7,"east"},{4,"southeast"},
    {3,"northeast"},{4,"east"},{2,"northeast"},{7,"east"},
    {2,"southeast"},{5,"northeast"},{2,"north"},{2,"northwest"},
    {3,"north"},{6,"northwest"},{4,"northeast"},{3,"east"},
    {2,"northeast"},{1,"port"},
}
routes["Kraken's Fall"]["Ta'Vaalor"] = {
    {1,"south"},{4,"southeast"},{5,"south"},{10,"southeast"},
    {4,"south"},{6,"southwest"},{2,"south"},{1,"southwest"},
    {4,"south"},{2,"southeast"},{7,"east"},{4,"southeast"},
    {3,"northeast"},{4,"east"},{2,"northeast"},{7,"east"},
    {2,"southeast"},{5,"northeast"},{2,"north"},{2,"northwest"},
    {3,"north"},{6,"northwest"},{4,"northeast"},{4,"east"},
    {6,"northeast"},{12,"east"},{6,"northeast"},{6,"east"},
    {8,"northeast"},{4,"north"},{1,"port"},
}

-- ---------------------------------------------------------------------------
-- From River's Rest
-- ---------------------------------------------------------------------------
routes["River's Rest"] = {}
routes["River's Rest"]["Icemule Trace"] = {
    {14,"northwest"},{19,"north"},{1,"northwest"},{1,"north"},
    {4,"northeast"},{4,"north"},{1,"northeast"},{1,"port"},
}
routes["River's Rest"]["Wehnimer's Landing"] = {
    {14,"northwest"},{19,"north"},{1,"northwest"},{13,"north"},
    {3,"northeast"},{2,"north"},{2,"east"},{4,"southeast"},
    {1,"port"},
}
routes["River's Rest"]["Kharam Dzu"] = {
    {14,"northwest"},{2,"north"},{9,"northwest"},{3,"west"},
    {5,"northwest"},{7,"west"},{1,"port"},
}
routes["River's Rest"]["Solhaven"] = {
    {14,"northwest"},{13,"north"},{3,"northeast"},{1,"southeast"},
    {1,"port"},
}
routes["River's Rest"]["Brisker's Cove"] = {
    {6,"northwest"},{1,"northeast"},{1,"east"},{1,"port"},
}
routes["River's Rest"]["Kraken's Fall"] = {
    {1,"north"},{14,"northwest"},{1,"north"},{5,"northwest"},
    {12,"southwest"},{4,"southeast"},{1,"east"},{1,"port"},
}
routes["River's Rest"]["Nielira Harbor"] = {
    {1,"southwest"},{2,"south"},{11,"southwest"},{5,"south"},
    {6,"southwest"},{2,"south"},{1,"southwest"},{4,"south"},
    {2,"southeast"},{7,"east"},{4,"southeast"},{3,"northeast"},
    {4,"east"},{2,"northeast"},{7,"east"},{2,"southeast"},
    {5,"northeast"},{2,"north"},{2,"northwest"},{3,"north"},
    {6,"northwest"},{4,"northeast"},{3,"east"},{2,"northeast"},
    {1,"port"},
}
routes["River's Rest"]["Ta'Vaalor"] = {
    {1,"southwest"},{2,"south"},{11,"southwest"},{5,"south"},
    {6,"southwest"},{2,"south"},{1,"southwest"},{4,"south"},
    {2,"southeast"},{7,"east"},{4,"southeast"},{3,"northeast"},
    {4,"east"},{2,"northeast"},{7,"east"},{2,"southeast"},
    {5,"northeast"},{2,"north"},{2,"northwest"},{3,"north"},
    {6,"northwest"},{4,"northeast"},{4,"east"},{6,"northeast"},
    {12,"east"},{6,"northeast"},{6,"east"},{8,"northeast"},
    {4,"north"},{1,"port"},
}

-- ---------------------------------------------------------------------------
-- From Nielira Harbor
-- ---------------------------------------------------------------------------
routes["Nielira Harbor"] = {}
routes["Nielira Harbor"]["Icemule Trace"] = {
    {2,"southwest"},{3,"west"},{4,"southwest"},{6,"southeast"},
    {3,"south"},{2,"southeast"},{2,"south"},{5,"southwest"},
    {2,"northwest"},{7,"west"},{2,"southwest"},{4,"west"},
    {3,"southwest"},{4,"northwest"},{7,"west"},{2,"northwest"},
    {4,"north"},{1,"northeast"},{2,"north"},{6,"northeast"},
    {5,"north"},{11,"northeast"},{4,"north"},{13,"northwest"},
    {19,"north"},{1,"northwest"},{20,"north"},{1,"northwest"},
    {1,"north"},{4,"northeast"},{4,"north"},{1,"northeast"},
    {1,"port"},
}
routes["Nielira Harbor"]["Wehnimer's Landing"] = {
    {2,"southwest"},{3,"west"},{4,"southwest"},{6,"southeast"},
    {3,"south"},{2,"southeast"},{2,"south"},{5,"southwest"},
    {2,"northwest"},{7,"west"},{2,"southwest"},{4,"west"},
    {3,"southwest"},{4,"northwest"},{7,"west"},{2,"northwest"},
    {4,"north"},{1,"northeast"},{2,"north"},{6,"northeast"},
    {5,"north"},{11,"northeast"},{4,"north"},{13,"northwest"},
    {19,"north"},{1,"northwest"},{13,"north"},{3,"northeast"},
    {2,"north"},{2,"east"},{4,"southeast"},{1,"port"},
}
routes["Nielira Harbor"]["Kharam Dzu"] = {
    {2,"southwest"},{3,"west"},{4,"southwest"},{6,"southeast"},
    {3,"south"},{2,"southeast"},{2,"south"},{5,"southwest"},
    {2,"northwest"},{7,"west"},{2,"southwest"},{4,"west"},
    {3,"southwest"},{4,"northwest"},{7,"west"},{2,"northwest"},
    {4,"north"},{1,"northeast"},{2,"north"},{6,"northeast"},
    {5,"north"},{11,"northeast"},{4,"north"},{13,"northwest"},
    {2,"north"},{9,"northwest"},{3,"west"},{5,"northwest"},
    {7,"west"},{1,"port"},
}
routes["Nielira Harbor"]["Solhaven"] = {
    {2,"southwest"},{3,"west"},{4,"southwest"},{6,"southeast"},
    {3,"south"},{2,"southeast"},{2,"south"},{5,"southwest"},
    {2,"northwest"},{7,"west"},{2,"southwest"},{4,"west"},
    {3,"southwest"},{4,"northwest"},{7,"west"},{2,"northwest"},
    {4,"north"},{1,"northeast"},{2,"north"},{6,"northeast"},
    {5,"north"},{11,"northeast"},{4,"north"},{13,"northwest"},
    {13,"north"},{3,"northeast"},{1,"southeast"},{1,"port"},
}
routes["Nielira Harbor"]["Brisker's Cove"] = {
    {2,"southwest"},{3,"west"},{4,"southwest"},{6,"southeast"},
    {3,"south"},{2,"southeast"},{2,"south"},{5,"southwest"},
    {2,"northwest"},{7,"west"},{2,"southwest"},{4,"west"},
    {3,"southwest"},{4,"northwest"},{7,"west"},{2,"northwest"},
    {4,"north"},{1,"northeast"},{2,"north"},{6,"northeast"},
    {5,"north"},{11,"northeast"},{4,"north"},{13,"northwest"},
    {4,"north"},{5,"northwest"},{1,"northeast"},{1,"east"},
    {1,"port"},
}
routes["Nielira Harbor"]["Kraken's Fall"] = {
    {2,"southwest"},{3,"west"},{4,"southwest"},{6,"southeast"},
    {3,"south"},{2,"southeast"},{2,"south"},{5,"southwest"},
    {2,"northwest"},{7,"west"},{2,"southwest"},{4,"west"},
    {3,"southwest"},{4,"northwest"},{7,"west"},{2,"northwest"},
    {4,"north"},{1,"northeast"},{2,"north"},{6,"northeast"},
    {4,"north"},{10,"northwest"},{5,"north"},{4,"northwest"},
    {1,"north"},{1,"port"},
}
routes["Nielira Harbor"]["River's Rest"] = {
    {2,"southwest"},{3,"west"},{4,"southwest"},{6,"southeast"},
    {3,"south"},{2,"southeast"},{2,"south"},{5,"southwest"},
    {2,"northwest"},{7,"west"},{2,"southwest"},{4,"west"},
    {3,"southwest"},{4,"northwest"},{7,"west"},{2,"northwest"},
    {4,"north"},{1,"northeast"},{2,"north"},{6,"northeast"},
    {5,"north"},{11,"northeast"},{2,"north"},{1,"northeast"},
    {1,"port"},
}
routes["Nielira Harbor"]["Ta'Vaalor"] = {
    {1,"east"},{4,"northeast"},{12,"east"},{4,"northeast"},
    {3,"east"},{2,"northeast"},{3,"east"},{8,"northeast"},
    {4,"north"},{1,"port"},
}

-- ---------------------------------------------------------------------------
-- From Ta'Vaalor
-- ---------------------------------------------------------------------------
routes["Ta'Vaalor"] = {}
routes["Ta'Vaalor"]["Icemule Trace"] = {
    {4,"south"},{8,"southwest"},{6,"west"},{6,"southwest"},
    {12,"west"},{6,"southwest"},{4,"west"},{4,"southwest"},
    {6,"southeast"},{3,"south"},{2,"southeast"},{2,"south"},
    {5,"southwest"},{2,"northwest"},{7,"west"},{2,"southwest"},
    {4,"west"},{3,"southwest"},{4,"northwest"},{7,"west"},
    {2,"northwest"},{4,"north"},{1,"northeast"},{2,"north"},
    {6,"northeast"},{5,"north"},{11,"northeast"},{4,"north"},
    {13,"northwest"},{19,"north"},{1,"northwest"},{20,"north"},
    {1,"northwest"},{1,"north"},{4,"northeast"},{4,"north"},
    {1,"northeast"},{1,"port"},
}
routes["Ta'Vaalor"]["Wehnimer's Landing"] = {
    {4,"south"},{8,"southwest"},{6,"west"},{6,"southwest"},
    {12,"west"},{6,"southwest"},{4,"west"},{4,"southwest"},
    {6,"southeast"},{3,"south"},{2,"southeast"},{2,"south"},
    {5,"southwest"},{2,"northwest"},{7,"west"},{2,"southwest"},
    {4,"west"},{3,"southwest"},{4,"northwest"},{7,"west"},
    {2,"northwest"},{4,"north"},{1,"northeast"},{2,"north"},
    {6,"northeast"},{5,"north"},{11,"northeast"},{4,"north"},
    {13,"northwest"},{19,"north"},{1,"northwest"},{13,"north"},
    {3,"northeast"},{2,"north"},{2,"east"},{4,"southeast"},
    {1,"port"},
}
routes["Ta'Vaalor"]["Kharam Dzu"] = {
    {4,"south"},{8,"southwest"},{6,"west"},{6,"southwest"},
    {12,"west"},{6,"southwest"},{4,"west"},{4,"southwest"},
    {6,"southeast"},{3,"south"},{2,"southeast"},{2,"south"},
    {5,"southwest"},{2,"northwest"},{7,"west"},{2,"southwest"},
    {4,"west"},{3,"southwest"},{4,"northwest"},{7,"west"},
    {2,"northwest"},{4,"north"},{1,"northeast"},{2,"north"},
    {6,"northeast"},{5,"north"},{11,"northeast"},{4,"north"},
    {13,"northwest"},{2,"north"},{9,"northwest"},{3,"west"},
    {5,"northwest"},{7,"west"},{1,"port"},
}
routes["Ta'Vaalor"]["Solhaven"] = {
    {4,"south"},{8,"southwest"},{6,"west"},{6,"southwest"},
    {12,"west"},{6,"southwest"},{4,"west"},{4,"southwest"},
    {6,"southeast"},{3,"south"},{2,"southeast"},{2,"south"},
    {5,"southwest"},{2,"northwest"},{7,"west"},{2,"southwest"},
    {4,"west"},{3,"southwest"},{4,"northwest"},{7,"west"},
    {2,"northwest"},{4,"north"},{1,"northeast"},{2,"north"},
    {6,"northeast"},{5,"north"},{11,"northeast"},{4,"north"},
    {13,"northwest"},{13,"north"},{3,"northeast"},{1,"southeast"},
    {1,"port"},
}
routes["Ta'Vaalor"]["Brisker's Cove"] = {
    {4,"south"},{8,"southwest"},{6,"west"},{6,"southwest"},
    {12,"west"},{6,"southwest"},{4,"west"},{4,"southwest"},
    {6,"southeast"},{3,"south"},{2,"southeast"},{2,"south"},
    {5,"southwest"},{2,"northwest"},{7,"west"},{2,"southwest"},
    {4,"west"},{3,"southwest"},{4,"northwest"},{7,"west"},
    {2,"northwest"},{4,"north"},{1,"northeast"},{2,"north"},
    {6,"northeast"},{5,"north"},{11,"northeast"},{4,"north"},
    {13,"northwest"},{4,"north"},{5,"northwest"},{1,"northeast"},
    {1,"east"},{1,"port"},
}
routes["Ta'Vaalor"]["Kraken's Fall"] = {
    {4,"south"},{8,"southwest"},{6,"west"},{6,"southwest"},
    {12,"west"},{6,"southwest"},{4,"west"},{4,"southwest"},
    {6,"southeast"},{3,"south"},{2,"southeast"},{2,"south"},
    {5,"southwest"},{2,"northwest"},{7,"west"},{2,"southwest"},
    {4,"west"},{3,"southwest"},{4,"northwest"},{7,"west"},
    {2,"northwest"},{4,"north"},{1,"northeast"},{2,"north"},
    {6,"northeast"},{4,"north"},{10,"northwest"},{5,"north"},
    {4,"northwest"},{1,"north"},{1,"port"},
}
routes["Ta'Vaalor"]["River's Rest"] = {
    {4,"south"},{8,"southwest"},{6,"west"},{6,"southwest"},
    {12,"west"},{6,"southwest"},{4,"west"},{4,"southwest"},
    {6,"southeast"},{3,"south"},{2,"southeast"},{2,"south"},
    {5,"southwest"},{2,"northwest"},{7,"west"},{2,"southwest"},
    {4,"west"},{3,"southwest"},{4,"northwest"},{7,"west"},
    {2,"northwest"},{4,"north"},{1,"northeast"},{2,"north"},
    {6,"northeast"},{5,"north"},{11,"northeast"},{2,"north"},
    {1,"northeast"},{1,"port"},
}
routes["Ta'Vaalor"]["Nielira Harbor"] = {
    {4,"south"},{8,"southwest"},{3,"west"},{2,"southwest"},
    {3,"west"},{4,"southwest"},{12,"west"},{4,"southwest"},
    {1,"west"},{1,"port"},
}

return routes
