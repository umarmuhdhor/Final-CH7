# ShooApp — owner: Team App

All app screens: Onboarding (ON-*), Protected (PR-*), Guardian & Family mode (GD-*), Detail (DT-*), Profile (PF-*).
PRD: docs/README.md. Use the PRD IDs in branch names and PR titles.

- Build UI against `contracts/fixtures/*.json` (copy into a Preview/mock file) — don't wait for the backend.
- Use models from `ShooShared/` (`ScanResult`, `Signal`, `Verdict`, `AppGroup`). Never redefine them.
- After onboarding, write device session keys to the App Group (contracts/app-group-keys.md) so the extension can call the API.
- Extension Active/Off = `AppGroup.Key.extensionLastSeenAt` is recent. Do not invent another way.
- Copy is English by default + Bahasa Indonesia (use String Catalog `Localizable.xcstrings`).
- Do not touch `ShooExtension/`, `ShooLiveActivity/`, `ShooShared/`, `project.yml`.
- Everything must follow Apple security & privacy (plan/alief/SECURITY.md §3): privacy manifest, Keychain `AfterFirstUnlockThisDeviceOnly`, `os.Logger` with `privacy: .private`, just-in-time permissions, no third-party SDKs, user data never written to disk caches. When in doubt, pick the most privacy-preserving option.
