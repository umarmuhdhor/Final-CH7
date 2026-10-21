# R5 — Konvensi

## 1. Swift (ios/ShooApp)

- Swift 5 mode (project.yml `SWIFT_VERSION: 5.0`), iOS 17. `@Observable` untuk state, `@MainActor` untuk view model, `async/await` untuk I/O. Tidak ada Combine baru.
- Satu fitur = satu folder `Features/<Nama>/` berisi `<Nama>View.swift`, `<Nama>Model.swift` (view model), subview kecil.
- View tidak memanggil jaringan/fixture langsung; selalu lewat `ShooRepository` dari `AppEnvironment`.
- Model data dari `ShooShared` (`ScanResult`, `Signal`, `Verdict`, `AppGroup`, `ScoreThreshold`, `JSONDecoder.shoo`). Jangan membuat salinan model. Tipe khusus app (mis. `FamilyMember`, `FamilyCode`, `DeviceSession`) didefinisikan di `Data/` sesuai bentuk JSON kontrak.
- Teks: semua string UI lewat String Catalog (`Localizable.xcstrings`), key = teks Inggris. Teks sinyal: `signal.label.text(for:)` / `labelSimple` (Protected), tidak diterjemahkan ulang.
- Bahasa in-app (PF-01): `AppSettings.language` → `.environment(\.locale, …)` di root. BELUM DIVERIFIKASI bahwa `Text(LocalizedStringKey)` mengikuti environment locale untuk String Catalog di iOS 17; diuji di fase 01. Fallback: helper `L10n.string(_:)` dengan `String(localized:bundle:locale:)`.
- Aksesibilitas: setiap kontrol punya label VoiceOver, target ≥ 44 pt, mendukung Dynamic Type sampai XL tanpa terpotong.
- Lint: `swift format` bawaan Xcode (tanpa tool tambahan).

## 2. TypeScript (backend/api)

- TS strict, ESM, Node-free (hanya Web API + `nodejs_compat` untuk postgres.js). Format: Prettier default. Lint: `tsc --noEmit`.
- Route tipis → service → repo. Service menerima `sql` dan dependency (sender push, store screenshot) lewat parameter supaya bisa dites.
- Validasi semua input dengan zod di route. Respons dibentuk oleh fungsi mapper `toScanResult(row)` dkk. sesuai kontrak.
- SQL hanya lewat tagged template `sql\`…\``. Tidak ada `sql.unsafe` dengan input pengguna.
- Client memakai `fetch_types: false` (D-alief-17), jadi **jangan** kirim array JS sebagai parameter (`= any(${ids})`). Daftar ID memakai ekspansi list `where id in ${sql(ids)}`. Skema tidak punya kolom array (`signals` = jsonb).

## 3. Git

- Branch: README §3 (satu ID PRD per branch, prefix `feat/`, `fix/`, `chore/`, `docs/`).
- Commit: Conventional Commits, scope = ID PRD atau area: `feat(GD-04): rotate family code every 60 s`, `test(BE-family): join rate limit`, `docs(plan): log fase 08`.
- Akhir pesan commit dari agent: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (atau model yang dipakai).
- PR: judul `<ID PRD>: <judul>`, reviewer `@umarmuhdhor`, isi mengikuti `.github/pull_request_template.md`.

## 4. Test

| Lapis | Tool | Lokasi | Perintah |
|---|---|---|---|
| Logika app | Swift Testing | `ios/ShooApp/Tests/` | `xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests` |
| Alur UI | XCUITest | `ios/ShooApp/UITests/` | `… -only-testing:ShooAppUITests` |
| API | vitest `^4.1.0` + `@cloudflare/vitest-plugin` (`cloudflareTest()` di `vitest.config.ts`, binding Hyperdrive lewat `miniflare.hyperdrives`) | `backend/api/test/` | `pnpm -C backend/api test`; satu file: `pnpm -C backend/api exec vitest run <pola>` |
| SQL | pgTAP | `backend/db/supabase/tests/` | `cd backend/db && supabase test db` |

Semua perintah dijalankan dari **root repo**. Setiap blok Verifikasi iOS diawali `source plan/alief/ref/sim.sh` yang mengisi `$SIM` (nama iPhone simulator yang tersedia, tanpa spasi di akhir). Perintah backend memakai subshell `(cd backend/db && …)` atau `pnpm -C backend/api …` supaya direktori tidak berpindah. Test API memakai Supabase lokal (`supabase start`) dan reset data per file lewat helper `test/helpers/resetDb.ts`. Server lokal ditunggu dengan `pnpm -C backend/api exec wait-on tcp:8787` (devDependency) sebelum `curl`.

## 5. Waktu & bahasa dokumen

- Log dan plan: Bahasa Indonesia, WITA. Kode, komentar, commit: Inggris.

## 6. Env & file contoh

- `backend/.env.example`, `backend/api/.dev.vars.example`: nama variabel saja.
- `api.baseURL` app: konstanta Swift di `ios/ShooApp/App/AppConfig.swift` dengan `#if DEBUG` (Debug = `http://localhost:8787`, Release = URL Worker cloud). **Bukan** `Info.plist`: Info.plist dan entitlements di-generate XcodeGen dari `ios/project.yml` (milik Umar) dan ditulis ulang setiap `xcodegen`, jadi edit manual hilang. Key Info.plist/entitlement baru = permintaan ke Umar (TODO C3).

## 7. Placeholder

Format penanda: `// TODO(sync:<umar|imelda|alief>): <apa> — replace after <PR/fase>`. Daftar placeholder aktif ada di log fase.

## 8. Nama file terlarang

Nama file tidak boleh mengandung `token`, `secret`, `password`, `credential`, `apikey`, `api-key`, `api_key`, dan tidak boleh berakhiran `.p8`, `.pem`, `.key` di repo. Gunakan `access.ts`, `session.ts`, `SessionStore.swift`.
