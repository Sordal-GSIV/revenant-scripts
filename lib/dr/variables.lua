--- DR global constants and lookup tables.
-- Ported from Lich5 drvariables.rb
-- @module lib.dr.variables
local M = {}

--- Ordinal words, indexed 1-20.
M.ORDINALS = {
  "first", "second", "third", "fourth", "fifth",
  "sixth", "seventh", "eighth", "ninth", "tenth",
  "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth",
  "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth",
}

--- The three DR currency types.
M.CURRENCIES = { "Kronars", "Lirums", "Dokoras" }

--- Denomination multipliers (value in copper).
M.DENOMINATIONS = {
  platinum = 10000,
  gold     = 1000,
  silver   = 100,
  bronze   = 10,
  copper   = 1,
}

--- City name to currency type mapping.
M.BANK_CURRENCIES = {
  -- Kronar cities
  ["Crossings"]     = "Kronars",
  ["Dirge"]         = "Kronars",
  ["Ilaya Taipa"]   = "Kronars",
  ["Leth Deriel"]   = "Kronars",
  -- Lirum cities
  ["Aesry Surlaenis'a"] = "Lirums",
  ["Hara'jaal"]         = "Lirums",
  ["Mer'Kresh"]         = "Lirums",
  ["Muspar'i"]          = "Lirums",
  ["Ratha"]             = "Lirums",
  ["Riverhaven"]        = "Lirums",
  ["Rossman's Landing"] = "Lirums",
  ["Therenborough"]     = "Lirums",
  ["Throne City"]       = "Lirums",
  -- Dokora cities
  ["Ain Ghazal"]        = "Dokoras",
  ["Boar Clan"]         = "Dokoras",
  ["Chyolvea Tayeu'a"]  = "Dokoras",
  ["Hibarnhvidar"]      = "Dokoras",
  ["Fang Cove"]         = "Dokoras",
  ["Raven's Point"]     = "Dokoras",
  ["Shard"]             = "Dokoras",
}

--- Word-to-number mapping.
M.NUM_MAP = {
  one   = 1,
  two   = 2,
  three = 3,
  four  = 4,
  five  = 5,
  six   = 6,
  seven = 7,
  eight = 8,
  nine  = 9,
  ten   = 10,
}

return M
