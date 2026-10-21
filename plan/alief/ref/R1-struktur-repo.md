# R1 — Struktur folder `backend/` dan `ios/ShooApp/`

Folder lain di repo milik Umar/Imelda dan tidak diubah. Folder baru di `ios/ShooApp/` butuh `cd ios && xcodegen` ulang (target Shoo memakai `sources: path: ShooApp`, jadi semua subfolder ikut otomatis).

## 1. `backend/`

```text
backend/
├── CLAUDE.md                     (sudah ada, jangan dihapus)
├── README.md                     setup lokal, deploy manual, daftar env (fase 07, diperbarui tiap fase be)
├── .gitignore                    .dev.vars, .env, node_modules, .wrangler, supabase/.temp, *.p8
├── .env.example                  nama variabel tanpa nilai
├── api/                          Cloudflare Worker (TypeScript)
│   ├── package.json              hono, zod, postgres; dev: wrangler, vitest@^4, @cloudflare/vitest-plugin, typescript
│   ├── wrangler.jsonc            name shoo-api, hyperdrive binding DB, triggers.crons, vars (non-secret)
│   ├── .dev.vars.example
│   ├── tsconfig.json
│   ├── vitest.config.ts
│   ├── src/
│   │   ├── index.ts              export default { fetch: app.fetch, scheduled }
│   │   ├── app.ts                Hono app: middleware (requestId, error, auth), mount routes
│   │   ├── env.ts                tipe Env (bindings + vars + secrets)
│   │   ├── db/
│   │   │   ├── client.ts         postgres(env.DB.connectionString, { max: 5, fetch_types: false, prepare: false })
│   │   │   └── repo/             satu file per tabel: devices.ts, families.ts, codes.ts, joinAttempts.ts, scans.ts, verdicts.ts
│   │   ├── http/
│   │   │   ├── auth.ts           Bearer → sha256 → device (principal)
│   │   │   ├── errors.ts         ApiError(code, status) → { error: { code, message } }
│   │   │   ├── rateLimit.ts      batas per device/IP berbasis tabel (R3 §5)
│   │   │   └── validate.ts       helper zod
│   │   ├── routes/               devices.ts, family.ts, scans.ts, verdicts.ts, blocklist.ts, join-page.ts, health.ts
│   │   ├── services/
│   │   │   ├── family.ts         kode, join, batas 3
│   │   │   ├── scans.ts          simpan, kuota screenshot, cursor, mapping ke ScanResult
│   │   │   ├── verdicts.ts
│   │   │   ├── screenshots.ts    interface ScreenshotStore + SupabaseStorageStore (+ R2Store nanti)
│   │   │   └── push/
│   │   │       ├── sender.ts     interface PushSender
│   │   │       ├── apns.ts       ApnsSender (JWT ES256, HTTP/2 via fetch)
│   │   │       ├── relay.ts      RelaySender → Edge Function push (hanya kalau spike gagal)
│   │   │       ├── log.ts        LogSender (dipakai saat secret APNs belum ada / test)
│   │   │       └── messages.ts   teks push EN/ID
│   │   └── cron/retention.ts
│   └── test/                     *.test.ts (vitest-plugin), helpers/seed.ts, fixtures dari contracts/fixtures
├── db/
│   └── supabase/
│       ├── config.toml           supabase init
│       ├── migrations/           YYYYMMDDHHMMSS_<slug>.sql
│       ├── tests/                *.test.sql (pgTAP, dijalankan `supabase test db`)
│       ├── seed.sql              data lokal (Guardian + 2 Protected + scan dari fixtures)
│       └── functions/push/       HANYA kalau spike APNs fase 07 gagal (Deno)
└── ci/
    ├── README.md                 langkah pasang untuk Umar (C2)
    └── backend.yml               draf workflow (inert di sini)
```

## 2. `ios/ShooApp/`

```text
ios/ShooApp/
├── CLAUDE.md, Info.plist, Shoo.entitlements   (sudah ada)
├── ShooApp.swift                 @main, inject AppEnvironment, onOpenURL, AppDelegate adaptor (push)
├── ContentView.swift             diganti RootView (fase 01); contoh extensionLastSeenAt dipindah ke ExtensionStatus
├── App/
│   ├── AppEnvironment.swift      repository + settings + router (DI)
│   ├── RootView.swift            onboarding vs TabView
│   ├── Router.swift              navigasi ke Detail(scanId), Profile, Family code
│   └── AppSettings.swift         bahasa, Family mode terakhir (GD-02), onboarding selesai
├── Data/
│   ├── ShooRepository.swift      protocol (semua operasi contracts/api.md yang dipakai app)
│   ├── MockRepository.swift      membaca Fixtures/*.json
│   ├── ApiRepository.swift       fase 13
│   ├── APIClient.swift           URLSession, Bearer, decode error kontrak (fase 13)
│   ├── SessionStore.swift        Keychain + tulis key App Group (fase 13)
│   ├── ExtensionStatus.swift     baca AppGroup.Key.extensionLastSeenAt
│   └── Fixtures/                 salinan contracts/fixtures/*.json (sumber kebenaran tetap contracts/)
├── Features/
│   ├── Onboarding/               ON-01, 02, 03, 05
│   ├── Shield/                   PR-04, GD-01, GD-03
│   ├── Activity/                 PR-05, GD-05
│   ├── Detail/                   DT-01..06, GD-07
│   ├── Profile/                  PF-01
│   └── Pairing/                  GD-04, PR-01, 02, 03 (fase 14)
├── Components/                   ScoreRing, StatusChip, AvatarView, SiteIcon, EmptyStateView, PrimaryButton
├── Support/                      Formatters (waktu relatif, persen), Localization helper
├── Resources/
│   ├── Localizable.xcstrings     EN (development language) + ID
│   └── Assets.xcassets           avatar_01..12, ilustrasi placeholder
├── Tests/                        ShooAppTests (Swift Testing)
├── UITests/                      ShooAppUITests (XCUITest)
└── ci/
    └── ios-app.yml               draf workflow (inert, di-exclude dari target lewat project.yml)
```

`Tests/`, `UITests/`, dan `ci/` di-exclude dari target Shoo dan dimasukkan ke target test lewat PR `chore/APP-test-targets` (D-alief-02).
