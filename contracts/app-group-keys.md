# App ↔ Extension

App and extension are separate processes. They share data only through:
1. **App Group** `group.com.shoo.app` by default, overridable per developer (`SHOO_APP_GROUP` in `ios/Config/`) — UserDefaults suite, Swift side, both read/write. Always use `AppGroup.id`.
2. **Native messaging** — extension JS calls `browser.runtime.sendNativeMessage`, `SafariWebExtensionHandler.swift` answers by reading the App Group.

Swift constants live in `ios/ShooShared/AppGroup.swift` — always use those, never raw strings.

## App Group keys
| Key | Type | Written by | Read by | Meaning |
|---|---|---|---|---|
| `device.id` | String | App | Extension | Backend device id (after `POST /devices`) |
| `device.token` | String | App | Extension | Bearer token for API calls |
| `device.mode` | `"guardian"` \| `"protected"` | App | Extension | Chosen in ON-03, never changes |
| `device.name` | String | App | Extension | ON-02 name |
| `guardian.name` | String? | App | Extension | Protected only: "Waiting for [name] to check" (EX-06) |
| `extension.lastSeenAt` | Date | Extension | App | Heartbeat. App shows Active if recent (ON-04, PR-04, GD-01) |
| `api.baseURL` | String | App | Extension | Backend base URL |
| `ai.baseURL` | String | App | Extension | AI service base URL |

## Language
There is **no language key**. Extension UI (popup, marks, block screen) and the signal wording it shows follow the **iPhone's language** (`en`, or `id` when iOS is set to Bahasa Indonesia). The in-app language setting (PF-01) only changes the app.

## Native messages (extension JS → Swift)
All messages: `{ "type": string, ... }`. Response always `{ "ok": boolean, ... }`.

| type | Request | Response |
|---|---|---|
| `heartbeat` | `{}` | `{ ok }` — writes `extension.lastSeenAt` |
| `getSession` | `{}` | `{ ok, deviceId, token, mode, name, guardianName, apiBaseURL, aiBaseURL }` (`ok: false` if app not onboarded) |
