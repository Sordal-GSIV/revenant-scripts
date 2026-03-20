-- help.lua — help text, examples, and changelog for invdb
-- Ported from invdb-beta.lic by Xanlin (original author).

local M = {}

local VERSION = "20260319.1"

function M.version()
  return VERSION
end

local HELP_TEXT = [[
  ;invdb help      > help text (this)
  ;invdb examples  > examples
  ;invdb changelog > changelog

  first parameter: action (default to refresh all if no parameters provided)
    options: refresh, query, sum (or total), count, export, reset, delete, remove, update
      refresh     load/update your database
      query       prints out results to your story window
      sum         less detail than query, aggregates by type and item
      count       shows totals by character and location
      export      export table or query to a file
      reset       clear everything and start over
      delete      delete character data (requires char= filter)

  second parameter: target (defaults to all or item)
    options: bank, bounty, char, item, inv, locker, lumnis, resource, tickets
             room/prop, rooms, room_objects
      bank         bank account & silvers
      bounty       shows bounty info
      char         character info
      item         both inventory and lockers
      inv          inventory, but not lockers
      locker       locker(s), but not inventory
      lumnis       lumnis status
      resource     resource and suffusion status, and voln favor
      tickets      ticket balance information
      rooms        rooms for room inventory
      room_objects objects scanned for room inventory
      room/prop    room inventory

  optional parameters and filters:
    all queries have a game filter, defaulting to the current game
    char=name
    game=gs3                         # defaults to the current game
    type=gem                         # based on your GameObj type data
    category=Container               # based on Simutronics category
    amount(>|>=|=|<=|<)42            # filter by amount
    qty(>|>=|=|<=|<)42               # alias for amount
    noun=stone                       # filter by item noun
    path=backpack                    # all items that start in a backpack
    stack=(jar|bundle|stack|pack)    # stack type filter
    epf=(empty|partial|full)         # to find empty or full jars
    marked=Y                         # items with marks
    registered=Y                     # items with registration
    groupby=char                     # adds char column to sum/total queries
    orderby="path asc, qty desc"     # customize result order
    limit=5                          # limits number of rows output
    delay=N                          # delay N seconds before running

  All other input is used as a search string for item name.
  If no parameters are provided, defaults to `refresh all`.
  +-------------------------------------------------------------+
  exporting:
    ;invdb export (char|item|inv|locker|bank|tickets) (filters)
    additional export parameters:
      format=(csv|txt|pipe)         default = csv
      dir=/path/to/dir              default = scripts/data/
      file=filename.ext             default = target_timestamp.csv
  +-------------------------------------------------------------+
  most commands have abbreviations:
    q  = query      c = char        m = marked
    i  = item       g = game        r = registered
    in = inv        t = type        s = stack
    l  = locker     n = noun        epf = stack_status
    b  = bank       p = path
  +-------------------------------------------------------------+
  settings (use true/false or on/off):
    ;invdb --settings              lists your current settings
    ;invdb --jar=on/off            turn on/off looking in jars
    ;invdb --stack=on/off          read stacks of notes
    ;invdb --lumnis=on/off         include lumnis in refresh all
    ;invdb --resource=on/off       include resource in refresh all
    ;invdb --open_containers=on/off  open containers during scan
]]

local HELP_EXAMPLES = [[
  examples:
    ;invdb                             # refresh all
    ;invdb query item golden glim      # search for golden glim
    ;invdb q i golden glim             # same (abbreviated)
    ;invdb q i gold*glim               # * is a wildcard
    ;invdb q i =golden wand            # exact match
    ;invdb type=wand gold              # wands with gold in name
    ;invdb sapphire char=xanlin        # Xanlin's sapphires
    ;invdb path=backpack char=xanlin   # all items in Xanlin's backpack
    ;invdb path=*sack                  # items in any sack
    ;invdb count locker char=xanlin    # locker counts for Xanlin
    ;invdb sum type=gem                # total gem counts
    ;invdb sum type=gem =uncut dia*    # total uncut diamonds
    ;invdb type=jar epf=empty          # find empty jars
    ;invdb q bank                      # bank balances
    ;invdb sum bank                    # bank totals by bank
    ;invdb q char                      # character list
    ;invdb refresh lumnis              # update lumnis data
    ;invdb refresh resource            # update resource/favor data
    ;invdb export item char=xanlin format=csv  # export to CSV
]]

local HELP_CHANGELOG = [[
  changelog:
    20260319.x (2026-03)
      - Revenant port: full conversion to Lua folder script
      - Added SQLite API (Sqlite.open, conn:exec, conn:query2, etc.)
      - Implemented REGEXP support via fancy-regex Rust crate
      - Maintained full parity with invdb-beta.lic v20250606.1

    20250606.1 (2025-06)
      - Original invdb-beta.lic by Xanlin

    (pre-2025 changelog preserved from original):
      - beta: added bounty
      - beta: more fixes for property/room inventory
      - beta: silver proc to methods refactor
      - beta: large refactor and database update: item notes,
              room/property inventory, item categories
      - fix for checking lumnis to reset resource weekly
      - skip updating resource for those with no profession resource or favor
      - added lumnis
      - added resource
]]

function M.print_help(script_name)
  local sn = script_name or "invdb"
  local text = HELP_TEXT:gsub(";invdb", ";" .. sn)
  respond('<output class="mono" />\n' .. text .. '\n<output class="" />')
end

function M.print_examples(script_name)
  local sn = script_name or "invdb"
  local text = HELP_EXAMPLES:gsub(";invdb", ";" .. sn)
  respond('<output class="mono" />\n' .. text .. '\n<output class="" />')
end

function M.print_changelog(script_name)
  local sn = script_name or "invdb"
  local text = HELP_CHANGELOG:gsub(";invdb", ";" .. sn)
  respond('<output class="mono" />\n' .. text .. '\n<output class="" />')
end

function M.print_version()
  respond("invdb version: " .. VERSION)
end

return M
