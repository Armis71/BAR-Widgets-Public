BAR Widget Suite by Kerwin

A unified collection of modern, replay‑safe, performance‑optimized widgets for Beyond All Reason (BAR).
This suite enhances economic visibility, commander‑kill tracking, and UI control while maintaining a clean, consistent visual style across all components.
All widgets are designed to work together seamlessly and follow the same UI theme, borders, fonts, and interaction patterns.

 Included Widgets
- Eco Graph — Real‑time Metal/Energy economy visualization
- Energy‑to‑Metal Conversion (E‑Conv) — Integrated conversion panel
- Toggle Menu — Quick widget visibility and mode toggles
- Commander Kill Tracker — Detailed commander kill log with icons, timestamps, and weapon info

 Eco Graph — Real‑Time Economy Visualization
Eco Graph provides a clear, modern view of your Metal and Energy economy over time.
It is optimized for competitive play, casting, and replay analysis.
Features
- Live Metal and Energy graphs with smooth sampling
- Accurate ETA predictions for stalls, storage fill, and storage empty
- Visual alerts for extreme eco states
- Draggable and resizable panel
- White‑border UI theme shared with the rest of the suite
- Fully replay‑safe and team‑switch‑safe
- Low CPU usage with optimized sampling
Benefits
- Understand eco trends at a glance
- Predict stalls and overflows before they happen
- Cleaner and more informative than stock UI bars

 Energy‑to‑Metal Conversion (E‑Conv)
E‑Conv is fully integrated into Eco Graph’s right side in Full View, forming a single unified economic dashboard.
Features
- Real‑time conversion rate display
- Accurate efficiency calculations
- Automatic detection of conversion structures
- Tooltip‑rich breakdown of conversion sources
- UI matches Eco Graph’s border, spacing, and fonts
- Replay‑safe and spectate‑safe
Benefits
- No more guessing how much energy is being converted
- Clear visibility into conversion efficiency and impact
- Seamless integration with Eco Graph

 Toggle Menu — Quick Widget Control
A compact, modern toggle menu that lets you quickly enable/disable widgets or switch modes without opening the full widget list.
Features
- Clean, minimal UI
- Fast access to widget toggles
- Consistent styling with the rest of the suite
- Optional hotkey support
Benefits
- Faster control during gameplay
- Cleaner than the default widget list
- Helps manage multiple widgets without clutter

 Commander Kill Tracker — Detailed Kill Log
A modern commander kill tracker with full visual context.
Shows killer icons, team colors, timestamps, weapon info, and sortable totals.
Features
- Killer name + team color
- Victim name + team color
- Unit icon of the killing unit
- Weapon used
- Timestamp
- Sortable totals
- Draggable + resizable UI
- Auto‑appearing scrollbar
- Tooltips on hover
- Flash highlight on new kills
- Fully replay‑safe
Benefits
- Perfect for competitive play and casting
- Clear attribution of commander kills
- Easy to review kill history in replays

 Recent Fixes & Improvements (2026‑03)
 Strict Commander Detection
Commander detection was refined to avoid false positives from structures using commander‑related customParams (e.g., builder turrets).
Now only true commanders are counted using:
- iscommander
- commtype
- iscommanderunit
- iscommanderclass
- deathExplosion == "commanderexplosion"
 Accurate Explosion Kill Attribution
Explosion‑based commander kills (nukes, AOE, chain‑explosions) now always credit the correct player.
Chain‑explosion roots are resolved before team filtering, fixing cases where the engine reports explosion damage as self‑damage.
 Unified UI Theme
All widgets now share:
- white border
- subtle inner highlight
- consistent padding
- unified font sizes
 Replay & Spectator Robustness
All widgets rebuild correctly when:
- jumping in replays
- switching teams
- entering spectator mode

 Summary
This widget suite provides a cohesive, modern set of tools for BAR players who want:
- deeper economic insight
- accurate commander kill tracking
- clean UI controls
- consistent styling
- replay‑safe behavior
- low CPU usage
Eco Graph + E‑Conv form a unified economic dashboard, the Toggle Menu provides fast UI control, and the Commander Kill Tracker adds high‑quality kill visualization for both players and casters.
