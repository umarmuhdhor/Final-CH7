# Spike: Dynamic Island from the Safari extension (EX-03)

**Question:** Can the running score appear in the Dynamic Island while the user browses in Safari?
**Fallback (PRD §10):** floating pill in-page.

## Paths to test
- [ ] A. Extension (`SafariWebExtensionHandler`) calls `Activity.request` directly — expected to fail (extensions usually can't start Live Activities).
- [ ] B. Extension updates an Activity the app started earlier (app starts one on launch / when Safari is used).
- [ ] C. Push-to-start / push updates via APNs from the server (latency per score update?).
- [ ] D. None works → in-page pill.

Code ready: `ShooShared/ScoreActivityAttributes.swift`, `ShooLiveActivity/`. Test on a real iPhone with Dynamic Island (simulator Live Activities are not reliable for this).

## Result
- Works? 
- Path chosen: 
- Latency per update: 
- Evidence (screenshot / video / logs): 
