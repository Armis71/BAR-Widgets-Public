Commander Kill Tracker — Overview
The Commander Kill Tracker is a modern, replay‑safe BAR widget that displays commander kills with full visual context. It shows killer icons, team colors, timestamps, weapon info, sortable totals, and a clean draggable/resizable UI with automatic scrolling.

Key Features
- Tracks every commander kill with:
- killer name + team color
- victim name + team color
- unit icon of the killing unit
- weapon used
- timestamp
- Accurate kill attribution for:
- nukes
- AOE damage
- chain‑explosions
- commander‑explosion propagation
- Clean UI:
- draggable
- resizable
- auto‑appearing scrollbar
- tooltips on hover
- subtle flash highlight on new kills
- Fully replay‑safe
- Works in both live games and replays

Recent Fixes (2026‑03)

Commander Misclassification Fixed
Commander detection was tightened to avoid false positives from structures that use commander‑related customParams (e.g., large builder turrets).
The widget now only recognizes true commanders using a strict set of BAR‑accurate flags:
- iscommander
- commtype
- iscommanderunit
- iscommanderclass
- deathExplosion == "commanderexplosion"
This prevents non‑commander structures from being counted.
Accurate Explosion Kill Attribution
Explosion‑based commander kills (nukes, AOE, chain‑explosions) are now always credited correctly.
The kill‑resolution logic was updated so that chain‑explosion roots are resolved before team filtering, fixing cases where the engine reports explosion damage as self‑damage.

This ensures:
- no missed commander kills
- no false self‑kills
- correct attribution for multi‑commander chain reactions

Summary
This widget provides a polished, reliable, and visually clean way to track commander kills in BAR. With the latest fixes, it now has fully accurate commander detection and explosion‑kill attribution, making it suitable for competitive play, casting, and replay analysis.
