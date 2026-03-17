--- @revenant-script
--- name: crutch
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Empath healing GUI helper - clickable wound healing interface (text-mode fallback)
--- tags: empath, healing, GUI, wounds
---
--- Ported from crutch.lic (Lich5) to Revenant Lua
---
--- Note: The original script uses GTK3 GUI with mannequin images.
--- This is a text-mode fallback version for Revenant.
---
--- Usage:
---   ;crutch   - Show wound status and healing commands

echo("=== The Crutch - Empath Healing Assistant ===")
echo("Text-mode version (original uses GTK GUI)")
echo("")
echo("The original Crutch provides a clickable mannequin GUI for empath healing.")
echo("It requires GTK3 bindings which are not available in Revenant.")
echo("")
echo("Quick healing commands:")
echo("  TOUCH <person>     - Begin empathic link")
echo("  HEAL               - Check your wounds")
echo("  TRANSFER <person>  - Transfer wounds from someone")
echo("  CAST <bodypart>    - Cast prepared healing spell on body part")
echo("")
echo("Body parts: head, neck, chest, abdomen, back,")
echo("  left arm, right arm, left hand, right hand,")
echo("  left leg, right leg, left eye, right eye, skin")
echo("")
echo("For automated healing, use ;nurse or ;healme instead.")
