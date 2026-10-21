# Spike: open Safari › Extensions from the app (ON-04 "Turn on" button)

**Question:** Can a button deep-link straight to Settings › Apps › Safari › Extensions › Shoo?
**Fallback (PRD §10):** open Settings + step illustration + video tutorial (PiP).

## To test on the target iOS version
- [ ] Any public API / URL that opens the extension's settings page directly?
- [ ] `UIApplication.openSettingsURLString` → where does it land? How many taps from there to the toggle?
- [ ] Private `App-prefs:` URLs → do NOT ship (App Review rejection risk); note only.

## Result
- Direct link possible? 
- Taps needed from where we land: 
- Steps for the illustration (screenshots per step): 
