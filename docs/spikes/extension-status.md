# Spike: detect extension On/Off from the app (ON-04, PR-04, GD-01)

**Question:** Can the app know if the user turned the Safari extension on?
**Fallback (PRD §10, already built):** extension writes a heartbeat to the App Group; app reads it when it comes back to foreground.

Already implemented:
- `content.js` → `background.js` → `sendNativeMessage({type:"heartbeat"})` → `SafariWebExtensionHandler` writes `extension.lastSeenAt`.
- `ShooApp/ContentView.swift` shows Active/Off on foreground.

## To test on device
- [ ] Turn extension on + "Allow on every website", open any site, return to app → Active?
- [ ] How fast does the first heartbeat arrive after enabling? (Needs a page load. Does the user have to open Safari first?)
- [ ] Turn extension off → how does the app find out? (Heartbeat just goes stale — pick a window; currently 24 h in `AppGroup.extensionActiveWindow`.)
- [ ] Revoke "Allow on every website" → content script stops → same as off? (EX-01)
- [ ] `extension.allSites` (U7): "All websites" → `true`. Change to "Ask" / a few sites → `false` right away (`permissions.onRemoved`) or on the next page / hourly alarm? Does `browser.permissions.contains` exist on iOS Safari at all? (If not, the key is never written.)
- [ ] Any public iOS API for extension state? (`SFSafariExtensionManager` is macOS-only.)

## Result
- Decision: 
- Active window: 
- What ON-04 should tell the user to do after toggling (e.g. "open any website"): 
