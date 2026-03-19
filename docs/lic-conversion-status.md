# Lich5 .lic Script Conversion Status

This document tracks the conversion status of all .lic scripts that have been evaluated
for Revenant Lua conversion. Scripts are sourced from two mirrors:
- `/mnt/unraid/CLAUDE/scripts/` (elanthia-online/lich-5-scripts)
- `/mnt/unraid/CLAUDE/lich_repo_mirror/` (lichless repo mirror)

## How to Find Audited Scripts

```bash
grep -rl "@lic-audit" scripts/
```

---

## SKIPPED — Not Applicable to Revenant

These scripts are Lich5 infrastructure, GTK3-only applications, or Wrayth FE panel
scripts that have no game logic separable from the Lich5/GTK platform.

### Lich5 Package Management Infrastructure

| Script | Lines | Reason |
|--------|-------|--------|
| **jinx.lic** | 2686 | Lich5 federated package manager. Downloads/installs .lic files from repo.elanthia.online. Revenant has its own `pkg` system with TOML manifests. |
| **repository.lic** | 2980 | Lich5 repository client for repo.lichproject.org:7157. Custom TLS protocol, .lic distribution. Revenant has its own package infrastructure. |

### GTK3 GUI Applications (No Separable Game Logic)

| Script | Lines | Reason |
|--------|-------|--------|
| **creaturewindow.lic** | 2308 | Real-time creature tracking panel using Wrayth FE panels / GTK3. Shows targets with status icons, kill metrics, bounty buttons. 100% UI code. |
| **flarewindow.lic** | 1278 | Combat flare tracking display in Wrayth FE panel. Tracks flare streaks, combo stats. Discord webhook is trivially reimplementable but the rest is GTK3 window rendering. |
| **playerwindow.lic** | 1622 | Player display window in Wrayth FE / GTK3. Shows room players with status, clickable interactions (poke sleeping, pull prone, cast unstun). |
| **merchantical.lic** | 3682 | Full GTK3 item management application. Locker management, batch sales, HTML/RTF shop export, color themes, loresang integration. Entirely UI-driven. |
| **nautical-charts.lic** | 514 | GTK3 interactive ocean map viewer for OSA sailing. PNG maps, zoom/pan, shift-click navigation, Cairo drawing. Requires full GTK3 runtime. |

### Novelty / Low Value

| Script | Lines | Reason |
|--------|-------|--------|
| **butterfly.lic** | 298 | Novelty script that replaces game names with butterfly names or song lyrics. Not worth converting. |

### DragonRealms Lich5 Infrastructure

| Script | Lines | Reason |
|--------|-------|--------|
| **noop.lic** (DR) | 13 | CI/testing placeholder that exits immediately. No functionality. |

**NOTE**: dependency.lic (DR) was previously listed here but has been moved to active conversion — it contains ArgParser, get_settings, get_data, and bot managers that DR scripts depend on.

---

## DEFERRED — Convertible But Queued for Future Sessions

These scripts have real game logic but are blocked by dependencies, overlap with
in-progress work, or need infrastructure that isn't mature yet.

### Large Combat Scripts (Dedicated Sessions)

| Script | Lines | Completion | Blocker |
|--------|-------|-----------|---------|
| **bigshot.lic** | 8217 | ~15-20% | 45+ missing command handlers, full GTK3 GUI, hunt_monitor, DRb group system. Needs dedicated multi-session effort. |
| **ebounty.lic** | 3753 | ~40% | 36 gaps including BigShot integration (set_eval, profiles), container management, spell casting in forage/heirloom. Depends on bigshot patterns. |
| **eloot.lic** | 6900 | ~15% | Massive gaps across every module: loot filtering, sell system, boxes, hoarding, inventory. Needs dedicated session. |
| **osacombat.lic** | 5134 | N/A | Full combat script like bigshot. GTK3 setup window (~1500 lines). Best tackled after bigshot to share combat patterns. |

### GTK3 Setup GUI Needed

| Script | Lines | Completion | Blocker |
|--------|-------|-----------|---------|
| **dirty_deeds.lic** | 1724 | ~3% | Current Lua is WRONG SCRIPT (rogue tracker instead of GS deed acquisition). Full GTK3 GUI for deed management, gem appraisal, bank runs. Needs complete rewrite. |
| **Combatical.lic** | 4362 | ~8% | Full GTK3 app with drag-and-drop ability management, resource bars, NPC targeting. Minimal stub exists. |
| **loresang.lic** | 1155 | N/A | Bard loresinging engine is pure game logic (~700 lines). GTK3 setup window (~300 lines) needs Revenant Gui replacement. Medium priority — could be done soon. |

### Dependency Blocked

| Script | Lines | Blocker |
|--------|-------|---------|
| **poolparty_new.lic** | 707 | Depends on oleani-lib.lic (Oleani framework) and slop-lib.lic (CLI parsing). Neither converted. Would need rewrite to use Revenant primitives. |
| **gs4tools.lic** | 833 | **CONVERTED** → `gs/gs4tools.lua` v2.0.0. Full parity: consent system, open/sync with base64url-encoded URLs via Crypto.base64url_encode, normalized profile support, Regex-based capture patterns. Browser auto-open replaced with URL printing. |

---

## Conversion Statistics (as of 2026-03-18)

- **Audited & Tagged**: 45 scripts (grep for `@lic-audit`)
- **Skipped**: 9 scripts (GTK3/Lich5 infrastructure)
- **Deferred**: 9 scripts (large/blocked)
- **In Progress**: See active session notes

---

## Notes

- Scripts tagged `--- @lic-audit: validated <date>` have been validated against their
  .lic originals, all gaps fixed, and confirmed complete.
- "Completion %" estimates are based on line-by-line feature comparison, not just
  line count ratios.
- GTK3 scripts may become convertible once Revenant's `Gui.*` widget system matures
  enough to replace the full GTK3 Builder/TreeView/Dialog ecosystem.
