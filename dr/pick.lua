--- @revenant-script
--- name: pick
--- version: 2.0.0
--- author: Seped
--- game: dr
--- description: Full lockpicking automation — disarm, harvest, pick, loot boxes
--- tags: lockpicking, thief, boxes, training
---
--- Ported from pick.lic (dr-scripts) to Revenant Lua
--- Original author: Seped
--- Changelog:
---   2.0.0 (2026-03-18) - Full feature parity with dr-scripts/pick.lic:
---     multiple sources, glance optimization, difficulty thresholds, trap
---     type detection/blacklist/greylist, skeleton key, buff bot, waggle sets,
---     gem pouch management, loot_specials, lockpick ring refill, trap harvest,
---     safe-room walkback, tend own wounds, assumed difficulty
---   1.0.0             - Initial stub from lich_repo_mirror/pick.lic
---
--- @lic-certified: complete 2026-03-18
---
--- Usage:
---   ;pick                      - Process boxes from configured container
---   ;pick --refill             - Refill lockpick ring only (then exit)
---   ;pick --source=bag         - Override box source container
---   ;pick --all                - Ignore stop_pick_on_mindlock setting
---   ;pick --assume=quick       - Skip identification; assume quick difficulty
---   ;pick --assume=normal      - Skip identification; assume normal difficulty
---   ;pick --assume=careful     - Skip identification; assume careful difficulty
---   ;pick --stand              - Stand while picking (default: sit)
---   ;pick --debug              - Enable verbose debug output

local args_lib = require("lib/args")
local args = args_lib.parse(Script.vars[0] or "")

-- ============================================================
-- PICKING DATA (inlined from dr-scripts/data/base-picking.yaml)
-- ============================================================

local PICK_DATA = {

  -- Ordered by difficulty index 0..16 (0 = easiest)
  pick_messages_by_difficulty = {
    "An aged grandmother could",                               -- 0
    "you could do it blindfolded",                            -- 1
    "lock is a trivially constructed piece of junk",          -- 2
    "will be a simple matter for you to unlock",              -- 3
    "should not take long with your skills",                  -- 4
    "with only minor troubles",                               -- 5
    "You think this lock is precisely at your skill level",   -- 6
    "lock has the edge on you, but you've got a good shot at", -- 7
    "odds are against you",                                   -- 8
    "You have some chance of being able to",                  -- 9
    "would be a longshot",                                    -- 10
    "Prayer would be a good start for any",                   -- 11
    "You have an amazingly minimal chance",                   -- 12
    "You really don't have any chance",                       -- 13
    "You probably have the same shot as a snowball",          -- 14
    "You could just jump off a cliff and save",               -- 15
    "A pitiful snowball encased in the Flames",               -- 16
  },

  pick_retry = {
    "fails to teach you anything about the lock guarding it",
  },

  disarm_messages_by_difficulty = {
    "An aged grandmother could defeat this trap in her sleep",         -- 0
    "This trap is a laughable matter",                                 -- 1
    "trivially constructed gadget which you can take down any time",   -- 2
    "will be a simple matter for you to disarm",                       -- 3
    "should not take long with your skills",                           -- 4
    "with only minor troubles",                                        -- 5
    "You think this trap is precisely at your skill level",            -- 6
    "trap has the edge on you, but you've got a good shot at disarming", -- 7
    "odds are against you",                                            -- 8
    "You have some chance of being able to disarm",                    -- 9
    "would be a longshot",                                             -- 10
    "Prayer would be a good start for any",                            -- 11
    "You have an amazingly minimal chance",                            -- 12
    "You really don't have any chance",                                -- 13
    "You probably have the same shot as a snowball",                   -- 14
    "You could just jump off a cliff and save",                        -- 15
    "A pitiful snowball encased in the Flames",                        -- 16
  },

  disarm_retry = {
    "You work with the trap for a while but are unable to make any progress",
    "You doubt you'll be this lucky every time",
  },

  disarm_identify_failed = {
    "fails to reveal to you what type of trap protects it",
    "something to shift",
  },

  disarm_succeeded = {
    "stopping it up and disarming the trap",
    "contact fibers away from the cube of black powder",
    "you shove the pin away from the tumblers and it springs upward and lodges",
    "into the tip of the clay and gently slide the tiny tube out of it",
    "so that the openings are sealed shut",
    "move the rune away from the lock and push it deep inside",
    "you feel satisfied that the trap is no longer a threat",
    "you gently remove the string that holds the bladder shut",
    "you manage to bend it well away from the mesh bag",
    "you manage to bend it away from the tiny hammer set to break it",
    "you wedge a small stick between the tiny hammer and the tube",
    "Reaching into the keyhole carefully, you knock free the coin sized piece of metal",
    "being extremely careful not to break it",
    "and allow its unsavory contents to spray harmlessly upon the ground",
    "allowing the deadly naphtha to drain harmlessly",
    "poison or something else, you work first at draining it",
    "you carefully bend the head of the needle so that it can no longer spring",
    "allowing it to be opened safely",
    "Finally, the body of the faux insect falls away and crumbles",
    "and unhook it from the blade rendering it harmless",
    "you nudge the black crystal away from its position next to the lock",
    "you carefully pry at the studs working them away from what you surmise are contacts",
    "use a strong sustained breath to blow the powder away from the lock",
    "then pack it into the pinholes, blocking them",
    "bend it away until its metal no longer touches the hinges at all",
  },

  trap_sprung = {
    "lock springs out and stabs you painfully in the finger",
    "An acrid stream of sulfurous air hisses quietly",
    "A stream of corrosive acid sprays out from the",
    "With a sinister swishing noise, a deadly sharp scythe blade whips out the front of the",
    "There is a sudden flash of greenish light, and a huge electrical charge sends you flying",
    "A stoppered vial opens with a pop and cloud of thick green vapor begins to pour out of the",
    "A glass sphere on the seal begins to glow with an eerie black light",
    "Just as your ears register the sound of a sharp snap",
    "Looking at the needle, you notice with horror the rust colored coating on the tip",
    "You barely have time to register a faint click before a blinding flash explodes around you",
    "Moving with the grace of a pregnant goat, you carelessly flick at the piece of metal causing",
    "With a cautious hand, you attempt to undo the string tying the bladder to the locking mechanism",
    "Almost casually, you press on the tiny hammer set to break the tube. The hammer slips from its locked",
    "Nothing happened. Maybe it was a dud.",
    "You get a feeling that something isn't right. Before you have time to think what it might be you find...",
    "and emits a sound like tormented souls being freed, then fades away suddenly",
    "has gotten much bigger",
    "and clumsily shred the fatty bladder behind it in the process.",
    "liquid shadows",
    "You wiggle the milky-white tube back and forth for a few moments in an attempt to remove it from",
    "With a nasty look and a liberal amount of hurled, unladylike epithets, she wiggles back inside and slams",
    "Not sure where to start, you begin by prying off the body of the crusty scarab, hoping to break it free",
    "You feel like you've done a good job of blocking up the pinholes, until you peer closely to examine",
    "oversized, red, ant-like insects emerge and begin to race across your hands",
    "As the stinging winds die down, they leave in their place several very angry vykathi reapers",
    "The liquid contents of the bladder empty, spraying you completely",
    "You experience a great wrenching in your gut and everything goes utterly black",
    "The dart flies through your fingers and plants itself",
    "You just begin to move it when a slight",
    "and sends tiny projectiles slamming into you",
  },

  -- trap_type -> identification message snippet
  traps = {
    acid         = "you notice a tiny hole right next to the lock",
    boomer       = "surrounded by a tight ring of fibrous cord",
    bouncer      = "Connected to the pin is a small shaft that runs downward into a shadow",
    concussion   = "you see a tiny metal tube just poking out of a small wad of brown clay",
    crossbow     = "concealing the points of several wickedly barbed crossbow bolts",
    curse        = "you notice a small glowing rune hidden inside the box near the lock",
    cyanide      = "tip of a dart and a slight smell of almonds",
    disease      = "you see what appears to be a small, swollen animal bladder",
    fireants     = "The bag twitches on occasion, leading you to believe the blade",
    fleas        = "Small black dots bounce inside, though the lack of transparency",
    frog         = "you notice a lumpy green rune hidden inside the",
    laughgas     = "a tiny glass tube filled with a black gaseous substance",
    lightning    = "Looking closely into the keyhole, you spy what appears to be a pulsating ball",
    mana         = "seal is covered in strange runes and a glass sphere is embedded within",
    mime         = "A tiny bronze face, Fae in appearance, grins ridiculously",
    naphthafire  = "A tiny striker is cleverly concealed under the lid",
    naphthasoak  = "Though it's hard to see, there also appears to be a liquid-filled bladder",
    nervepoison  = "You notice a tiny needle with a rust colored discoloration",
    poison       = "You notice a tiny needle with a greenish discoloration",
    poisoncrossbow = "concealing the points of several crossbow bolts glistening with moisture",
    poisongas    = "You notice a vial of lime green liquid just under the",
    reaper       = "crust-covered black scarab of some unidentifiable substance",
    scythe       = "you notice a glint of razor sharp steel hidden within a suspicious looking seam",
    shadowling   = "you notice a small black crystal deep in the shadows of the",
    shocker      = "You notice two silver studs right below the keyhole",
    shrapnel     = "keyhole is packed tightly with a powder around the insides of the lock",
    sleep        = "Two sets of six pinholes on either side of the",
    teleport     = "covered with a thin metal circle that has been lacquered with a shade",
  },

  -- trap_type -> already-disarmed message snippet
  disarmed_traps = {
    acid         = "stuffed with dirt rendering the trap harmless",
    boomer       = "separated harmlessly from their charge",
    bouncer      = "You see a pin and shaft lodged into the frame",
    concussion   = "been pulled away and whatever was inside, removed",
    crossbow     = "have been bent in such a way that they no longer will function",
    curse        = "You see a glowing rune pushed deep within the chest",
    cyanide      = "the dart has been moved too far out of position for the mechanism to function",
    disease      = "animal bladder and a disconnected string",
    fireants     = "indicating the trap is no longer a danger",
    fleas        = "have been bent away from each other",
    frog         = "It seems far enough away from the lock to be harmless",
    laughgas     = "You deem it quite safe",
    lightning    = "seems a small portion of the trap has been removed",
    mana         = "The seal has been pried away from the lid",
    mime         = "metallic visage rests a small deflated bladder",
    naphthasoak  = "indicating a liquid was drained out",
    naphthafire  = "as if something had been poured out the hole",
    poison       = "A bent needle sticks harmlessly out",
    poisongas    = "Someone has unhooked the stopper, rendering it harmless",
    reaper       = "was picked apart and removed from the",
    scythe       = "It is no longer attached to a razor-sharp scythe blade",
    shadowling   = "It seems harmless",
    shocker      = "whatever it was has been pried out",
    shrapnel     = "and the remnants of some type of powder",
    sleep        = "sealed with dirt, blocking whatever",
    teleport     = "has been peeled away from the hinges",
  },

  trap_parts = {
    "glass reservoir", "steel striker", "black cube", "chitinous leg",
    "coiled spring", "brown clay", "animal bladder", "sharp blade",
    "tiny hammer", "sealed vial", "stoppered vial", "metal spring",
    "metal lever", "iron disc", "broken needle", "curved blade",
    "silver studs", "metal circle", "steel pin", "broken rune",
    "green runestone", "bronze seal", "glass sphere", "bronze face",
    "black crystal", "capillary tube", "short needle",
  },

  lockpick_costs = {
    Crossing     = { ordinary = 125,  stout = 250,  slim = 500  },
    Riverhaven   = { ordinary = 100,  stout = 200,  slim = 400  },
    Shard        = { ["stout iron"] = 270, bronze = 451, ["slim ivory"] = 1443, ["slim copper"] = 2706 },
    ["Ain Ghazal"]   = { ["ordinary metal"] = 157, ["stout azure"] = 248, ["night-black"] = 157 },
    Hibarnhvidar     = { ["ordinary metal"] = 157, ["stout azure"] = 248, ["night-black"] = 157 },
    ["Muspar'i"]     = { ["pale beige ordinary"] = 100, ["sand-hued stout"] = 200, ["earth-toned slim"] = 400 },
  },
}

-- Build reverse-lookup tables for trap identification
local trap_by_msg    = {}   -- identification snippet -> trap_type
local disarmed_by_msg = {}  -- already-disarmed snippet -> trap_type
local all_trap_msgs   = {}  -- flat list of all identification snippets
local disarmed_msgs   = {}  -- flat list of all already-disarmed snippets

for trap_type, msg in pairs(PICK_DATA.traps) do
  trap_by_msg[msg] = trap_type
  all_trap_msgs[#all_trap_msgs + 1] = msg
end
for trap_type, msg in pairs(PICK_DATA.disarmed_traps) do
  disarmed_by_msg[msg] = trap_type
  disarmed_msgs[#disarmed_msgs + 1] = msg
end

-- ============================================================
-- SETTINGS LOAD
-- ============================================================

local S = {}
local pick_cfg = CharSettings.get("pick") or {}
if type(pick_cfg) ~= "table" then pick_cfg = {} end

-- Box sources (multiple sources supported)
if args.source then
  S.sources = { args.source }
elseif pick_cfg.picking_box_sources and type(pick_cfg.picking_box_sources) == "table" then
  S.sources = pick_cfg.picking_box_sources
else
  local src = pick_cfg.picking_box_source
            or CharSettings.get("picking_box_source")
            or CharSettings.get("box_source")
  S.sources = src and { src } or nil
end

if not S.sources or #S.sources == 0 then
  DRC.message("Pick: No valid configuration found for box source. Run ;pick_setup first.")
  return
end

S.debug                       = args.debug or pick_cfg.debug or false
S.stand                       = args.stand or false
S.use_lockpick_ring           = CharSettings.get("use_lockpick_ring") or false
S.lockpick_container          = CharSettings.get("lockpick_container") or "lockpick ring"
S.balance_lockpick_container  = pick_cfg.balance_lockpick_container or false
S.tie_gem_pouches             = CharSettings.get("tie_gem_pouches") or false
S.stop_pick_on_mindlock       = (args.all and false) or CharSettings.get("stop_pick_on_mindlock") or false
S.loot_nouns                  = CharSettings.get("lootables") or {}
S.trash_nouns                 = CharSettings.get("trash_nouns") or {}
S.lockpicking_armor           = CharSettings.get("lockpicking_armor") or {}
S.has_glance                  = (DRStats.guild == "Thieves") and ((DRStats.circle or 0) >= 13)
S.use_glance                  = pick_cfg.use_glance
if S.use_glance == nil then S.use_glance = S.has_glance end
S.trash_empty_boxes           = pick_cfg.trash_empty_boxes or CharSettings.get("trash_empty_boxes") or false
S.worn_trashcan               = CharSettings.get("worn_trashcan")
S.worn_trashcan_verb          = CharSettings.get("worn_trashcan_verb")
S.dismantle_type              = CharSettings.get("lockpick_dismantle") or ""
S.pick_buff_bot_name          = CharSettings.get("lockpick_buff_bot")
S.pick_buff_bot_buff          = pick_cfg.buff_bot_buff or "hol"
S.has_pick_waggle             = type(CharSettings.get("waggle_sets")) == "table" and CharSettings.get("waggle_sets")["pick"] ~= nil
S.pick_quick_threshold        = pick_cfg.pick_quick_threshold   or 2
S.pick_normal_threshold       = pick_cfg.pick_normal_threshold  or 4
S.pick_careful_threshold      = pick_cfg.pick_careful_threshold or 7
S.disarm_quick_threshold      = pick_cfg.disarm_quick_threshold    or 0
S.disarm_normal_threshold     = pick_cfg.disarm_normal_threshold   or 2
S.disarm_careful_threshold    = pick_cfg.disarm_careful_threshold  or 5
S.disarm_too_hard_threshold   = pick_cfg.disarm_too_hard_threshold or 10
S.too_hard_container          = pick_cfg.too_hard_container
S.max_identify_attempts       = pick_cfg.max_identify_attempts or 5
S.max_disarm_attempts         = pick_cfg.max_disarm_attempts   or 5
S.assumed_difficulty          = args.assume or pick_cfg.assumed_difficulty
S.trap_blacklist              = pick_cfg.trap_blacklist    or {}
S.blacklist_container         = pick_cfg.blacklist_container
S.trap_greylist               = pick_cfg.trap_greylist     or {}
S.harvest_traps               = pick_cfg.harvest_traps or CharSettings.get("harvest_traps") or false
S.component_container         = pick_cfg.component_container or CharSettings.get("component_container")
S.trap_parts                  = PICK_DATA.trap_parts
S.tend_own_wounds             = pick_cfg.tend_own_wounds or false
S.lockpick_costs              = pick_cfg.lockpick_costs or PICK_DATA.lockpick_costs
S.lockpick_type               = CharSettings.get("lockpick_type") or "ordinary"
S.refill_town                 = CharSettings.get("refill_town") or CharSettings.get("hometown") or "Crossing"
S.skip_lockpick_ring_refill   = CharSettings.get("skip_lockpick_ring_refill") or false
S.saferoom_health_threshold   = CharSettings.get("saferoom_health_threshold") or 30
S.use_skeleton_key            = CharSettings.get("use_skeleton_key") or false
S.skeleton_key                = CharSettings.get("skeleton_key")
S.gem_pouch_noun              = CharSettings.get("gem_pouch_noun") or "pouch"
S.gem_pouch_adjective         = CharSettings.get("gem_pouch_adjective")
S.spare_gem_pouch_container   = CharSettings.get("spare_gem_pouch_container")
S.full_pouch_container        = CharSettings.get("full_pouch_container")
S.fill_pouch_with_box         = CharSettings.get("fill_pouch_with_box") or false
S.loot_specials               = CharSettings.get("loot_specials") or {}
S.picking_room_id             = Room and Room.id

-- Debug output
if S.debug then
  echo("Pick: settings loaded")
  echo("  sources:                " .. table.concat(S.sources, ", "))
  echo("  use_lockpick_ring:      " .. tostring(S.use_lockpick_ring))
  echo("  lockpick_container:     " .. S.lockpick_container)
  echo("  balance_lp_container:   " .. tostring(S.balance_lockpick_container))
  echo("  harvest_traps:          " .. tostring(S.harvest_traps))
  echo("  stop_pick_on_mindlock:  " .. tostring(S.stop_pick_on_mindlock))
  echo("  has_glance:             " .. tostring(S.has_glance))
  echo("  use_glance:             " .. tostring(S.use_glance))
  echo("  pick_buff_bot:          " .. tostring(S.pick_buff_bot_name))
  echo("  tend_own_wounds:        " .. tostring(S.tend_own_wounds))
  echo("  disarm_too_hard_thresh: " .. S.disarm_too_hard_threshold)
  echo("  max_identify_attempts:  " .. S.max_identify_attempts)
  echo("  max_disarm_attempts:    " .. S.max_disarm_attempts)
  echo("  assumed_difficulty:     " .. tostring(S.assumed_difficulty))
  echo("  trap_blacklist:         " .. table.concat(S.trap_blacklist, ", "))
  echo("  trap_greylist:          " .. table.concat(S.trap_greylist, ", "))
end

-- ============================================================
-- FLAGS SETUP
-- ============================================================

Flags.add("disarm-shift",    "something to shift")
Flags.add("disarm-trap-type", table.unpack(all_trap_msgs))
Flags.add("more-traps",      "not fully disarmed", "not yet fully disarmed",
                              "still has more to torment you with")
Flags.add("more-locks",      "You discover another lock protecting")
Flags.add("glance-no-traps", "It looks like there are no traps left on")
Flags.add("glance-no-locks", "It looks like there are no locks left on")

-- ============================================================
-- UTILITY
-- ============================================================

local function dbg(msg)
  if S.debug then echo("[pick] " .. msg) end
end

local function stop_picking()
  return S.stop_pick_on_mindlock and (DRSkill.getxp("Locksmithing") or 0) >= 30
end

local function holding_box(box)
  return DRCI.in_hands(box.noun)
end

local function in_list(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- ============================================================
-- CONTAINER SETUP
-- ============================================================

local function open_containers()
  for _, src in ipairs(S.sources) do
    DRCI.open_container(src)
  end
  if S.too_hard_container    then DRCI.open_container(S.too_hard_container)    end
  if S.blacklist_container   then DRCI.open_container(S.blacklist_container)   end
  if S.component_container   then DRCI.open_container(S.component_container)   end
end

local function check_for_boxes()
  local boxes_by_bag = {}
  for _, src in ipairs(S.sources) do
    boxes_by_bag[src] = DRCI.get_box_list_in_container(src)
  end
  local total = 0
  for _, boxes in pairs(boxes_by_bag) do total = total + #boxes end
  if total == 0 then
    DRC.message("Pick: No boxes found in source containers. Exiting.")
    return nil
  end
  return boxes_by_bag
end

-- ============================================================
-- GEAR MANAGEMENT
-- ============================================================

local removed_armor = {}

local function remove_hindering_gear()
  -- Empty hands first
  local lh = DRC.left_hand()
  local rh = DRC.right_hand()
  if lh then DRCI.stow_hand("left")  end
  if rh then DRCI.stow_hand("right") end

  -- Remove configured lockpicking armor
  removed_armor = {}
  for _, item in ipairs(S.lockpicking_armor) do
    if DRCI.remove_item(item) then
      removed_armor[#removed_armor + 1] = item
    end
  end

  -- Verify hands are empty
  if DRC.left_hand() or DRC.right_hand() then
    DRC.message("Pick: Items still in hands after removing hindering gear. Exiting.")
    for _, item in ipairs(removed_armor) do DRCI.wear_item(item) end
    return false
  end
  return true
end

local function wear_normal_gear()
  for _, item in ipairs(removed_armor) do
    DRCI.wear_item(item)
  end
end

-- ============================================================
-- BUFFS
-- ============================================================

local function do_buffs()
  if S.pick_buff_bot_name then
    local pcs = DRRoom.pcs or {}
    if type(pcs) == "table" then
      for _, pc in ipairs(pcs) do
        if pc == S.pick_buff_bot_name then
          DRC.bput("whisper " .. S.pick_buff_bot_name .. " buff " .. S.pick_buff_bot_buff,
            "You whisper")
          break
        end
      end
    end
  end
  if S.has_pick_waggle then
    DRC.wait_for_script_to_complete("buff", {"pick"})
  end
end

local function stop_buffs()
  if not S.has_pick_waggle then return end
  local guild = DRStats.guild
  if guild == "Barbarians" then
    DRC.bput("meditate stop", ".*")
  elseif guild == "Thieves" then
    local waggle = type(CharSettings.get("waggle_sets")) == "table"
                   and CharSettings.get("waggle_sets")["pick"]
    if waggle and type(waggle) == "table" then
      for name, _ in pairs(waggle) do
        DRC.bput("khri stop " .. name, "You attempt to relax your mind")
      end
    end
  else
    local waggle = type(CharSettings.get("waggle_sets")) == "table"
                   and CharSettings.get("waggle_sets")["pick"]
    if waggle and type(waggle) == "table" then
      for _, spell_data in pairs(waggle) do
        if type(spell_data) == "table" and spell_data.abbrev then
          DRC.bput("release " .. spell_data.abbrev, "You release", "You don't have that spell")
        end
      end
    end
  end
end

-- ============================================================
-- LOCKPICK MANAGEMENT
-- ============================================================

local function find_lockpick()
  if DRC.left_hand() then return end
  if not DRCI.get_item("lockpick", S.lockpick_container) then
    DRC.message("Pick: Out of lockpicks. Exiting.")
    DRCI.stow_hands()
    return false
  end
  return true
end

local function balance_lockpick_container()
  if not S.use_lockpick_ring or not S.balance_lockpick_container then return end
  DRC.bput("turn my " .. S.lockpick_container .. " to best",
    "You fiddle with", "You think about it")
end

-- ============================================================
-- LOCKPICK RING REFILL
-- ============================================================

local function refill_ring()
  if not S.use_lockpick_ring then return end
  if S.skip_lockpick_ring_refill then return end

  local lockpicks_needed = DRCI.count_lockpick_container(S.lockpick_container)
  if lockpicks_needed < 15 then return end

  local town_costs = S.lockpick_costs[S.refill_town]
  if not town_costs then
    DRC.message("Pick: No lockpick costs configured for town '" .. S.refill_town .. "'. Cannot refill.")
    return
  end

  local cost = town_costs[S.lockpick_type]
  if not cost then
    DRC.message("Pick: Unknown lockpick type '" .. S.lockpick_type .. "' for '" .. S.refill_town .. "'. Cannot refill.")
    return
  end

  DRCM.ensure_copper_on_hand(cost * lockpicks_needed)
  DRCT.refill_lockpick_container(S.lockpick_type, S.refill_town, S.lockpick_container, lockpicks_needed)
end

-- ============================================================
-- SKELETON KEY
-- ============================================================

local function try_unlock_box_with_key(box)
  if not S.use_skeleton_key or not S.skeleton_key then return end
  if not DRCI.get_item_if_not_held(S.skeleton_key) then
    DRC.message("Pick: Could not get skeleton key '" .. S.skeleton_key .. "'. Skipping key attempt.")
    return
  end
  local result = DRC.bput("turn my " .. S.skeleton_key .. " at my " .. box.noun,
    "^You turn", "that doesn't seem to do much",
    "I could not find", "What were you referring")
  if waitrt then waitrt() end
  if result:find("^You turn") then
    box.trapped = false
    box.locked  = false
  end
end

-- ============================================================
-- GLANCE
-- ============================================================

local function glance(box)
  Flags.reset("glance-no-traps")
  Flags.reset("glance-no-locks")
  DRC.bput("glance my " .. box.noun,
    "Looking more closely you see",
    "It looks like there are no locks",
    "^You glance")
  if Flags.get("glance-no-traps") then box.trapped = false end
  if Flags.get("glance-no-locks") then box.locked  = false end
end

-- ============================================================
-- TRAP SPRUNG HANDLER
-- ============================================================

local function handle_trap_sprung(trap_type)
  DRC.message("Pick: **SPRUNG TRAP**")
  DRC.message("Pick: **SPRUNG TRAP**")
  if trap_type then DRC.message("Pick:   TRAP TYPE: " .. trap_type) end

  -- Wait while stunned
  pause(1)
  while stunned and stunned() do pause(1) end

  -- Stow anything in hand that we grabbed
  local lh = DRC.left_hand()
  local rh = DRC.right_hand()
  if lh then DRCI.stow_hand("left")  end
  if rh then DRCI.stow_hand("right") end

  if S.tend_own_wounds then
    DRC.wait_for_script_to_complete("tendme")
  end

  DRC.wait_for_script_to_complete("safe-room")

  if S.picking_room_id and Room and Room.id ~= S.picking_room_id then
    DRCT.walk_to(S.picking_room_id)
  end
end

-- ============================================================
-- TOO HARD / BLACKLISTED
-- ============================================================

local function handle_trap_too_hard_or_blacklisted(box, container)
  if container then
    if DRCI.put_away_item(box.noun, container) then return end
    DRC.message("Pick: Throwing away box because stowing in " .. container .. " failed.")
  end
  DRCI.dispose_trash(box.noun, S.worn_trashcan, S.worn_trashcan_verb)
end

-- ============================================================
-- HAND MANAGEMENT
-- ============================================================

local function stow_hands_except(item_noun)
  if DRCI.in_hands("lockpick") then
    DRCI.put_away_item("lockpick", S.lockpick_container)
  end
  local lh = DRC.left_hand()
  local rh = DRC.right_hand()
  if lh and not lh:find(item_noun, 1, true) then DRCI.stow_hand("left")  end
  if rh and not rh:find(item_noun, 1, true) then DRCI.stow_hand("right") end
end

-- ============================================================
-- TRAP IDENTIFICATION
-- ============================================================

local function identify_trap(box)
  dbg("identify_trap(" .. box.noun .. ")")

  Flags.reset("more-traps")
  Flags.reset("disarm-trap-type")

  local patterns = {
    "Thanks to an instinct provided by your sense of security",
    "You'll need to have the item in your hands or placed on the ground",
    "You're in no shape to be disarming anything",
  }
  for _, p in ipairs(PICK_DATA.trap_sprung)                 do patterns[#patterns + 1] = p end
  for _, p in ipairs(PICK_DATA.disarm_identify_failed)      do patterns[#patterns + 1] = p end
  for _, p in ipairs(PICK_DATA.disarm_messages_by_difficulty) do patterns[#patterns + 1] = p end
  for _, msg in ipairs(disarmed_msgs)                        do patterns[#patterns + 1] = msg end

  local result = DRC.bput("disarm my " .. box.noun .. " identify", table.unpack(patterns))

  local trapped = true
  local trap = nil
  local difficulty = nil

  if result:find("Thanks to an instinct") then
    trapped = true
    dbg("Sense of security detected trap presence")
  elseif result:find("You'll need to have the item in your hands") then
    DRC.message("Pick: Lost your box somehow.")
    trapped = false
  elseif result:find("You're in no shape to be disarming") then
    DRC.message("Pick: Too injured to continue. Exiting.")
    wear_normal_gear()
    DRC.fix_standing()
    return false  -- caller should check
  else
    -- Check sprung
    local sprung = false
    for _, p in ipairs(PICK_DATA.trap_sprung) do
      if result:find(p, 1, true) then sprung = true; break end
    end
    if sprung then
      handle_trap_sprung(nil)
      trapped = false
    else
      -- Check identify failed
      local failed = false
      for _, p in ipairs(PICK_DATA.disarm_identify_failed) do
        if result:find(p, 1, true) then failed = true; break end
      end
      if failed then
        dbg("Failed to identify trap, will retry")
        -- difficulty stays nil → caller retries
      else
        -- Check already disarmed
        local already = false
        for trap_type, msg in pairs(PICK_DATA.disarmed_traps) do
          if result:find(msg, 1, true) then
            dbg("Already-disarmed trap: " .. trap_type)
            trap = trap_type
            trapped = false
            difficulty = 0
            already = true
            break
          end
        end
        if not already then
          -- Match difficulty message
          for idx, p in ipairs(PICK_DATA.disarm_messages_by_difficulty) do
            if result:find(p, 1, true) then
              difficulty = idx - 1   -- 0-indexed
              break
            end
          end
          -- Get trap type from disarm-trap-type flag
          local trap_flag = Flags.get("disarm-trap-type")
          if trap_flag and type(trap_flag) == "string" then
            trap = trap_by_msg[trap_flag]
          end
          dbg("Identified trap: " .. tostring(trap) .. " difficulty: " .. tostring(difficulty))
        end
      end
    end
  end

  box.trapped = trapped
  box.trap = trap
  box.trap_difficulty = difficulty

  if waitrt then waitrt() end

  if Flags.get("more-traps") then
    dbg("Another trap detected after disarm/trip")
    box.trapped = true
    box.trap_difficulty = nil
  end
  return true
end

-- ============================================================
-- DISARM TRAP
-- ============================================================

local function disarm_trap(box)
  dbg("disarm_trap(" .. box.noun .. " diff=" .. tostring(box.trap_difficulty) .. ")")

  local speed
  if S.assumed_difficulty then
    speed = S.assumed_difficulty
    dbg("Using assumed difficulty: " .. speed)
  else
    local d = box.trap_difficulty or S.disarm_careful_threshold
    if d < S.disarm_quick_threshold then
      speed = "blind";   dbg("Disarm blind")
    elseif d < S.disarm_normal_threshold then
      speed = "quick";   dbg("Disarm quick")
    elseif d < S.disarm_careful_threshold then
      speed = "";        dbg("Disarm normal")
    else
      speed = "careful"; dbg("Disarm careful")
    end
  end

  Flags.reset("more-traps")
  Flags.reset("disarm-shift")

  local patterns = {}
  patterns[#patterns + 1] = "Thanks to an instinct provided by your sense of security"
  for _, p  in ipairs(PICK_DATA.trap_sprung)   do patterns[#patterns + 1] = p   end
  for _, msg in ipairs(disarmed_msgs)           do patterns[#patterns + 1] = msg end
  for _, p  in ipairs(PICK_DATA.disarm_retry)  do patterns[#patterns + 1] = p   end
  for _, p  in ipairs(PICK_DATA.disarm_succeeded) do patterns[#patterns + 1] = p end

  local cmd = speed ~= "" and ("disarm my " .. box.noun .. " " .. speed)
                           or ("disarm my " .. box.noun)
  local result = DRC.bput(cmd, table.unpack(patterns))
  dbg("disarm result: " .. result)

  local trapped = true

  -- Check sprung
  local sprung = false
  for _, p in ipairs(PICK_DATA.trap_sprung) do
    if result:find(p, 1, true) then sprung = true; break end
  end

  if sprung then
    handle_trap_sprung(box.trap)
    trapped = false
  elseif result:find("Thanks to an instinct") then
    trapped = true
  else
    local already = false
    for _, msg in ipairs(disarmed_msgs) do
      if result:find(msg, 1, true) then already = true; break end
    end
    local retry = false
    for _, p in ipairs(PICK_DATA.disarm_retry) do
      if result:find(p, 1, true) then retry = true; break end
    end
    local succeeded = false
    for _, p in ipairs(PICK_DATA.disarm_succeeded) do
      if result:find(p, 1, true) then succeeded = true; break end
    end
    if already or succeeded then
      trapped = false; dbg("Trap disarmed/already gone")
    elseif retry then
      trapped = true; dbg("Failed to disarm trap, will retry")
    end
  end

  box.trapped = trapped
  if Flags.get("disarm-shift") then
    box.trap_difficulty = (box.trap_difficulty or 0) + 1
    dbg("Difficulty shifted up to " .. tostring(box.trap_difficulty))
  end

  if waitrt then waitrt() end

  if Flags.get("more-traps") then
    dbg("Another trap after disarming/tripping")
    box.trapped = true
    box.trap_difficulty = nil
  end
  dbg("After disarm: trapped=" .. tostring(box.trapped))
end

-- ============================================================
-- HARVEST TRAP COMPONENTS
-- ============================================================

local function harvest(box)
  dbg("Harvesting trap from " .. box.noun)
  for attempt = 1, S.max_disarm_attempts do
    local result = DRC.bput("disarm my " .. box.noun .. " harvest",
      "You fumble around with the trap apparatus",
      "much for it to be successfully harvested",
      "completely unsuitable for harvesting",
      "previous trap have already been completely harvested",
      "Roundtime")
    dbg("Harvest result: " .. result)
    if result:find("fumble around") then
      -- retry
    elseif result:find("Roundtime") then
      if waitrt then waitrt() end
      local lh = DRC.left_hand()
      if lh then
        local is_part = false
        for _, part in ipairs(S.trap_parts) do
          if lh:find(part, 1, true) then is_part = true; break end
        end
        if is_part and not S.component_container then
          DRCI.dispose_trash(lh, S.worn_trashcan, S.worn_trashcan_verb)
        elseif S.component_container then
          DRCI.put_away_item(lh, S.component_container)
        else
          DRCI.put_away_item(lh)
        end
      end
      return
    else
      return  -- unsuitable or already harvested
    end
    if attempt >= S.max_disarm_attempts then
      DRC.message("Pick: Failed to harvest trap after " .. S.max_disarm_attempts .. " attempts. Skipping.")
      return
    end
  end
end

local function analyze_and_harvest(box)
  dbg("Analyze and harvest: " .. box.noun)
  for attempt = 1, S.max_identify_attempts do
    local result = DRC.bput("disarm my " .. box.noun .. " analyze",
      "You've already analyzed",
      "You are unable to determine a proper method",
      "Roundtime")
    if result:find("unable to determine") then
      -- retry
    else
      break
    end
    if attempt >= S.max_identify_attempts then
      DRC.message("Pick: Failed to analyze trap after " .. S.max_identify_attempts .. " attempts. Skipping harvest.")
      return
    end
  end
  harvest(box)
end

-- ============================================================
-- LOCK IDENTIFICATION
-- ============================================================

local function identify_lock(box)
  dbg("identify_lock(" .. box.noun .. ")")

  local patterns = {
    "better have an empty hand first",
    "Find a more appropriate tool and try again",
    "It's not even locked, why bother",
  }
  for _, p in ipairs(PICK_DATA.trap_sprung)                  do patterns[#patterns + 1] = p end
  for _, p in ipairs(PICK_DATA.pick_retry)                   do patterns[#patterns + 1] = p end
  for _, p in ipairs(PICK_DATA.pick_messages_by_difficulty)  do patterns[#patterns + 1] = p end

  local result = DRC.bput("pick my " .. box.noun .. " ident", table.unpack(patterns))

  if result:find("better have an empty hand") then
    stow_hands_except(box.noun)
    return
  end

  if result:find("Find a more appropriate tool") then
    box.locked = true
    box.lock_difficulty = nil
    S.use_lockpick_ring = false
    return
  end

  if result:find("It's not even locked") then
    box.locked = false
    box.lock_difficulty = 0
    return
  end

  for _, p in ipairs(PICK_DATA.trap_sprung) do
    if result:find(p, 1, true) then
      handle_trap_sprung(nil)
      return
    end
  end

  for _, p in ipairs(PICK_DATA.pick_retry) do
    if result:find(p, 1, true) then
      box.locked = true
      box.lock_difficulty = nil
      return
    end
  end

  for idx, p in ipairs(PICK_DATA.pick_messages_by_difficulty) do
    if result:find(p, 1, true) then
      box.lock_difficulty = idx - 1
      dbg("Lock difficulty: " .. box.lock_difficulty)
      return
    end
  end
end

-- ============================================================
-- PICK LOCK
-- ============================================================

local function pick_lock(box)
  dbg("pick_lock(" .. box.noun .. " diff=" .. tostring(box.lock_difficulty) .. ")")

  local speed
  if S.assumed_difficulty then
    speed = S.assumed_difficulty
    dbg("Using assumed difficulty: " .. speed)
  else
    local d = box.lock_difficulty or S.pick_careful_threshold
    if d < S.pick_quick_threshold then
      speed = "blind";   dbg("Pick blind")
    elseif d < S.pick_normal_threshold then
      speed = "quick";   dbg("Pick quick")
    elseif d < S.pick_careful_threshold then
      speed = "";        dbg("Pick normal")
    else
      speed = "careful"; dbg("Pick careful")
    end
  end

  Flags.reset("more-locks")
  Flags.reset("more-traps")

  local patterns = {
    "you remove your lockpick and open and remove the lock",
    "not even locked",
    "You discover another lock protecting",
    "You are unable to make any progress towards opening the lock",
    "Find a more appropriate tool and try again",
    "better have an empty hand first",
    "Pick what",
  }
  for _, p in ipairs(PICK_DATA.trap_sprung) do patterns[#patterns + 1] = p end

  local cmd = speed ~= "" and ("pick my " .. box.noun .. " " .. speed)
                           or ("pick my " .. box.noun)
  local result = DRC.bput(cmd, table.unpack(patterns))
  dbg("Pick result: " .. result)

  if result:find("Find a more appropriate tool") then
    S.use_lockpick_ring = false
  elseif result:find("better have an empty hand") then
    stow_hands_except(box.noun)
  elseif result:find("you remove your lockpick") or result:find("not even locked") then
    box.locked = false
  elseif result:find("Pick what") then
    DRC.message("Pick: Box is missing.")
    box.locked = false
  else
    for _, p in ipairs(PICK_DATA.trap_sprung) do
      if result:find(p, 1, true) then
        handle_trap_sprung(nil)
        break
      end
    end
  end

  if waitrt then waitrt() end

  if Flags.get("more-traps") then
    box.trapped = true
    box.trap_difficulty = nil
  end
  if Flags.get("more-locks") then
    box.lock_difficulty = nil
    box.locked = true
  end
end

-- ============================================================
-- LOOT
-- ============================================================

local function pouch_ref()
  if S.gem_pouch_adjective then
    return S.gem_pouch_adjective .. " " .. S.gem_pouch_noun
  end
  return S.gem_pouch_noun
end

local function swap_out_full_gempouch()
  if not S.spare_gem_pouch_container then
    DRC.message("Pick: spare_gem_pouch_container not set. Cannot swap pouch.")
    pause(10)
    return
  end
  local pref = pouch_ref()
  local lowered = DRC.left_hand()
  if lowered then DRCI.lower_item(lowered) end

  DRCI.remove_item(pref)
  if S.full_pouch_container then
    DRCI.put_away_item(pref, S.full_pouch_container)
  else
    DRCI.put_away_item(pref)
  end

  DRCI.get_item(pref, S.spare_gem_pouch_container)
  DRCI.wear_item(pref)

  if lowered then
    DRCI.get_item(lowered)
    DRCI.put_away_item(lowered)
  end

  if S.tie_gem_pouches then
    DRC.bput("tie my " .. pref, "You tie", "it's empty", "has already been tied off")
  end
end

local function loot_item(item_short, box_noun)
  if item_short:find("fragment", 1, true) then return end
  if item_short:find("stuff",    1, true) then return end

  local result = DRC.bput("get " .. item_short .. " from my " .. box_noun,
    "You get",
    "You pick up",
    "What were you referring")

  if result:find("You pick up") then return end  -- coins, auto-picked
  if result:find("What were you referring") then
    DRC.message("Pick: Could not get '" .. item_short .. "' from " .. box_noun .. ". Skipping.")
    return
  end

  local item_long = result:match("You get (.*) from") or item_short

  -- loot_specials: route by keyword to a specific container
  for _, special in ipairs(S.loot_specials) do
    if item_long:lower():find(special.name:lower(), 1, true) then
      DRCI.put_away_item(item_short, special.bag)
      return
    end
  end

  -- loot_nouns: gems/treasure to stow (auto-uses gem pouch)
  for _, noun in ipairs(S.loot_nouns) do
    if item_long:find(noun, 1, true)
        and not item_long:find("sunstone runestone", 1, true) then
      local sr = DRC.bput("stow my " .. item_short,
        "You put", "You open",
        "is too full to fit another gem",
        "You'd better tie it up before putting")
      if sr:find("too full") or sr:find("better tie") then
        swap_out_full_gempouch()
        DRC.bput("stow my " .. item_short, "You put", "You open", "is too full")
      end
      return
    end
  end

  -- trash_nouns: dispose
  for _, noun in ipairs(S.trash_nouns) do
    if item_long:lower():find(noun:lower(), 1, true) then
      DRCI.dispose_trash(item_short, S.worn_trashcan, S.worn_trashcan_verb)
      return
    end
  end

  -- Unrecognized — trash it
  DRC.message("Pick: Unrecognized item '" .. item_long .. "' — trashing.")
  DRCI.dispose_trash(item_short, S.worn_trashcan, S.worn_trashcan_verb)
end

local function loot(box_noun)
  dbg("Looting " .. box_noun)

  local open_result = DRC.bput("open my " .. box_noun,
    "In the .* you see", "That is already open", "It is locked")
  if open_result:find("It is locked") then
    DRC.message("Pick: Bug — tried to loot locked box. Skipping.")
    return
  end

  -- Fill gem pouch from box if configured
  if S.fill_pouch_with_box or #S.loot_specials == 0 then
    DRC.bput("fill my " .. pouch_ref() .. " with my " .. box_noun,
      "You fill your", "You open your", "What were you referring to",
      "any gems", "too full to fit")
  end

  -- Loot all items (loop handles very full boxes that show "stuff")
  for round = 1, 10 do
    local box_items = DRCI.get_item_list(box_noun, "look")
    if not box_items or #box_items == 0 then break end

    local found_stuff = false
    for _, item in ipairs(box_items) do
      if item:lower():find("stuff") then found_stuff = true end
      loot_item(item, box_noun)
    end
    if not found_stuff then break end
    if round >= 10 then
      DRC.message("Pick: Exceeded max loot rounds. Box may still have items.")
    end
  end
end

-- ============================================================
-- DISMANTLE / DISPOSE
-- ============================================================

local function dismantle(box)
  DRC.release_invisibility()
  local command = "dismantle my " .. box.noun
  if S.dismantle_type and S.dismantle_type ~= "" then
    command = command .. " " .. S.dismantle_type
  end
  for attempt = 1, 5 do
    local result = DRC.bput(command,
      "repeat this request in the next 15 seconds",
      "Roundtime",
      "You must be holding the object you wish to dismantle",
      "Your hands are too full for that",
      "You can not dismantle that")
    if result:find("repeat this request") then
      -- loop again
    elseif result:find("Your hands are too full") then
      stow_hands_except(box.noun)
    elseif result:find("You can not dismantle that") then
      DRCI.dispose_trash(box.noun, S.worn_trashcan, S.worn_trashcan_verb)
      return
    else
      return  -- success or box gone
    end
    if attempt >= 5 then
      DRC.message("Pick: Failed to dismantle box. Trashing it.")
      DRCI.dispose_trash(box.noun, S.worn_trashcan, S.worn_trashcan_verb)
      return
    end
  end
end

local function dispose_empty_box(box)
  if S.trash_empty_boxes then
    DRCI.dispose_trash(box.noun, S.worn_trashcan, S.worn_trashcan_verb)
  else
    dismantle(box)
  end
end

-- ============================================================
-- ATTEMPT OPEN — the main per-box state machine
-- ============================================================

local function attempt_open(box_noun)
  dbg("attempt_open(" .. box_noun .. ")")

  local box = {
    noun           = box_noun,
    trap_difficulty = nil,
    trap           = nil,
    trapped        = true,
    lock_difficulty = nil,
    locked         = true,
  }

  try_unlock_box_with_key(box)

  while holding_box(box) and (box.trapped or box.locked) do

    -- ── DISARM PHASE ────────────────────────────────────────
    while holding_box(box) and box.trapped do
      dbg("Starting disarm for " .. box.noun)

      if S.assumed_difficulty then
        box.trap_difficulty = 0
      end

      -- Identify trap
      local id_attempts = 0
      while box.trap_difficulty == nil do
        id_attempts = id_attempts + 1
        if id_attempts > S.max_identify_attempts then
          DRC.message("Pick: Failed to identify trap after " .. S.max_identify_attempts
                      .. " attempts. Proceeding careful.")
          box.trap_difficulty = S.disarm_careful_threshold
          break
        end
        if S.use_glance then glance(box) end
        if not box.trapped then break end
        identify_trap(box)
      end

      if not box.trapped then break end

      -- Blacklist check
      if box.trap and in_list(S.trap_blacklist, box.trap) then
        dbg("Blacklisted trap on box: " .. box.trap)
        handle_trap_too_hard_or_blacklisted(box, S.blacklist_container)
        return
      end

      -- Too-hard check
      if box.trap_difficulty and box.trap_difficulty >= S.disarm_too_hard_threshold then
        dbg("Trap too hard (diff=" .. box.trap_difficulty .. ")")
        handle_trap_too_hard_or_blacklisted(box, S.too_hard_container)
        return
      end

      -- Disarm attempts
      local disarm_attempts = 0
      while holding_box(box) and box.trapped and box.trap_difficulty ~= nil do
        disarm_attempts = disarm_attempts + 1
        if disarm_attempts > S.max_disarm_attempts then
          DRC.message("Pick: Failed to disarm trap after " .. S.max_disarm_attempts .. " attempts. Stowing box.")
          handle_trap_too_hard_or_blacklisted(box, S.too_hard_container)
          return
        end
        -- Greylist: force careful
        if box.trap and in_list(S.trap_greylist, box.trap) then
          box.trap_difficulty = S.disarm_careful_threshold
        end
        disarm_trap(box)
      end

      -- Harvest trap components if enabled
      if holding_box(box) and S.harvest_traps then
        analyze_and_harvest(box)
      end
    end  -- disarm while

    -- ── PICK PHASE ──────────────────────────────────────────
    while holding_box(box) and not box.trapped and box.locked do
      dbg("Starting lockpicking for " .. box.noun)

      if S.assumed_difficulty then
        box.lock_difficulty = 0
      end

      -- Identify lock
      local lock_id_attempts = 0
      while box.lock_difficulty == nil do
        lock_id_attempts = lock_id_attempts + 1
        if lock_id_attempts > S.max_identify_attempts then
          DRC.message("Pick: Failed to identify lock after " .. S.max_identify_attempts
                      .. " attempts. Proceeding careful.")
          box.lock_difficulty = S.pick_careful_threshold
          break
        end
        if S.use_glance then glance(box) end
        if not box.locked then break end
        if not S.use_lockpick_ring then
          if not find_lockpick() then return end
        end
        identify_lock(box)
      end

      if not box.locked then break end

      -- Pick attempts
      local pick_attempts = 0
      while not box.trapped and box.locked and box.lock_difficulty ~= nil do
        pick_attempts = pick_attempts + 1
        if pick_attempts > S.max_disarm_attempts then
          DRC.message("Pick: Failed to pick lock after " .. S.max_disarm_attempts .. " attempts. Stowing box.")
          handle_trap_too_hard_or_blacklisted(box, S.too_hard_container)
          return
        end
        if not S.use_lockpick_ring then
          if not find_lockpick() then return end
        end
        pick_lock(box)
      end
    end  -- pick while

  end  -- outer while

  -- Loot and dismantle
  if holding_box(box) then
    stow_hands_except(box.noun)
    loot(box.noun)
    dispose_empty_box(box)
  else
    dbg("Lost box somehow.")
  end
end

-- ============================================================
-- CRACK BOXES
-- ============================================================

local function crack_boxes(boxes_by_bag)
  for _, src in ipairs(S.sources) do
    local boxes = boxes_by_bag[src] or {}
    for _, box_noun in ipairs(boxes) do
      if stop_picking() then break end

      do_buffs()

      if S.stand then
        DRC.fix_standing()
      else
        if not sitting() then
          DRC.bput("sit", "You sit", "You are already sitting", "You rise", "While swimming?")
        end
      end

      if DRCI.get_item(box_noun, src) then
        balance_lockpick_container()
        attempt_open(box_noun)
      end
    end
    if stop_picking() then break end
  end

  DRC.fix_standing()
end

-- ============================================================
-- MAIN
-- ============================================================

open_containers()
local boxes_by_bag = check_for_boxes()
if not boxes_by_bag then return end

if args.refill then
  refill_ring()
  return
end

if stop_picking() then
  DRC.message("Pick: Locksmithing mindstate is at/above 30. Exiting.")
  return
end

if not remove_hindering_gear() then
  return
end

crack_boxes(boxes_by_bag)
stop_buffs()
wear_normal_gear()
refill_ring()

DRC.message("Pick: Done picking!")

-- ============================================================
-- CLEANUP FLAGS ON EXIT
-- ============================================================

before_dying(function()
  Flags.delete("disarm-trap-type")
  Flags.delete("disarm-shift")
  Flags.delete("more-traps")
  Flags.delete("more-locks")
  Flags.delete("glance-no-traps")
  Flags.delete("glance-no-locks")
end)
