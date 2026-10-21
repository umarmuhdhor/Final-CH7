# ShooApp — owner: Team App

All app screens: Onboarding (ON-*), Protected (PR-*), Guardian & Family mode (GD-*), Detail (DT-*), Profile (PF-*).
PRD: docs/README.md. Use the PRD IDs in branch names and PR titles.

- Build UI against `contracts/fixtures/*.json` (copy into a Preview/mock file) — don't wait for the backend.
- Use models from `ShooShared/` (`ScanResult`, `Signal`, `Verdict`, `AppGroup`). Never redefine them.
- After onboarding, write device session keys to the App Group (contracts/app-group-keys.md) so the extension can call the API.
- Extension Active/Off = `AppGroup.Key.extensionLastSeenAt` is recent. Do not invent another way.
- Copy is English by default + Bahasa Indonesia (use String Catalog `Localizable.xcstrings`).
- Do not touch `ShooExtension/`, `ShooLiveActivity/`, `ShooShared/`, `project.yml`.
