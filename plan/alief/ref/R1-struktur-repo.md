# R1 — Struktur folder `backend/` dan `ios/ShooApp/`

Folder lain di repo milik Umar/Imelda dan tidak diubah. Folder baru di `ios/ShooApp/` butuh `cd ios && xcodegen` ulang (target Shoo memakai `sources: path: ShooApp`, jadi semua subfolder ikut otomatis).

> Diperbarui 19 Nov 2026 terhadap `main` `b68957b8` (Dynamic Island dihapus di #555). Gambaran lapisan dan alur: [`../ARCHITECTURE.md`](../ARCHITECTURE.md). Daftar endpoint lengkap: `backend/README.md` + `backend/API.md`.

## 1. `backend/`

```text
backend/
├── CLAUDE.md                     (sudah ada, jangan dihapus)
├── README.md                     setup lokal, deploy, daftar env dan endpoint (diperbarui tiap fase be)
├── API.md                        referensi semua endpoint (bentuk JSON, error, batas)
├── .gitignore                    .dev.vars, .env, node_modules, .wrangler, supabase/.temp, *.p8
├── .env.example                  nama variabel tanpa nilai
├── api/                          Cloudflare Worker (TypeScript)
│   ├── package.json              hono, zod, postgres; dev: wrangler, vitest, @cloudflare/vitest-plugin, @cloudflare/workers-types, typescript, ajv; scripts: dev, test, typecheck, deploy
│   ├── wrangler.jsonc            name shoo-api, hyperdrive DB, R2 REPLICAS (`shoo-replicas`) + REPLICA_ARCHIVE (`shoo-replica-archive`), ratelimits (5 binding hitEdge), triggers.crons `0 19 * * *` + `5 * * * *`, vars (non-secret)
│   ├── .dev.vars.example
│   ├── tsconfig.json
│   ├── vitest.config.ts
│   ├── src/
│   │   ├── index.ts              export default { fetch: app.fetch, scheduled }; CRONS = retention `0 19 * * *`, notifications `5 * * * *`
│   │   ├── app.ts                Hono app: requestId, batas body awal (413), Cache-Control no-store, header keamanan, mount routes
│   │   ├── env.ts                tipe Env (bindings + vars + secrets)
│   │   ├── policy.ts             RETENTION_DAYS = 14 (satu sumber angka retensi)
│   │   ├── assets/               og-invite.jpg, mascot-wave.webp, mascot-sorry.webp (halaman undangan)
│   │   ├── cron/
│   │   │   ├── retention.ts      harian (R4 §5)
│   │   │   └── notifications.ts  per jam: "Perlindungan mati" + ringkasan mingguan (PF-01)
│   │   ├── db/
│   │   │   ├── client.ts         postgres(env.DB.connectionString, { max: 5, fetch_types: false }) — prepare default (JANGAN prepare:false, docs Hyperdrive)
│   │   │   ├── locks.ts          kelas advisory lock, satu kelas per tujuan (fase 27k F-B12)
│   │   │   └── repo/             blocklist, codes, config, devices, domainLists, families, fragments, joinAttempts, latestScams, ops, push, scans, tombstones, verdictLock, verdicts
│   │   ├── http/
│   │   │   ├── auth.ts           Bearer → sha256 → device (principal), requireMode
│   │   │   ├── errors.ts         ApiError(code, status) → { error: { code, message } }
│   │   │   ├── rateLimit.ts      `limits`; hit (Postgres), hitLight, hitEdge (binding Rate Limiting, cadangan Postgres) (R3 §5)
│   │   │   ├── bodyLimit.ts, crypto.ts, keyHash.ts (HMAC RATE_KEY_SECRET), logError.ts
│   │   │   └── validate.ts       helper zod
│   │   ├── routes/               app-site-association, blocklist, config, devices, family, favicons, health, join-page, latest-scams, ops, privacy, replicas, scans, screenshots, site-icons, support, terms, verdicts
│   │   │                         (debug-apns.ts sementara fase 07 sudah dihapus)
│   │   └── services/
│   │       ├── family.ts         kode 6 digit, validateJoinInTx, joinFamily, batas 3
│   │       ├── becomeProtected.ts  POST /devices/me/protected dalam satu transaksi (fase 27a)
│   │       ├── scans.ts          mapping ke ScanResult, link screenshot (scan lama)
│   │       ├── replicas.ts, replicaStore.ts   salinan halaman di R2 (EX-07)
│   │       ├── favicons.ts, faviconFetch.ts   favicon diunduh Worker, disimpan di R2 (PR-05)
│   │       ├── fragments.ts      fragmen bukti + favicon per domain ke arsip R2 (ADM-07)
│   │       ├── screenshots.ts    ScreenshotStore (Supabase Storage, scan lama) + R2, tombstone
│   │       ├── screenshotLinks.ts  link HMAC screenshot/favicon/replica (3600 s)
│   │       ├── images.ts, opsStatus.ts
│   │       └── push/
│   │           ├── sender.ts     PushSender, LogSender, pemilihan pushSender(env)
│   │           ├── apns.ts       ApnsSender langsung dari Worker (JALUR UTAMA, D-alief-B01; cache JWT per isolate)
│   │           ├── jwt.ts        JWT ES256 APNs (test di vitest)
│   │           ├── deliver.ts    send → kosongkan token (410) → push_log, di waitUntil
│   │           ├── notify.ts     guardianPush + ownPush (hanya Guardian, PF-01), quiet hours, batas 10 / 10 menit
│   │           ├── quiet.ts      jam tenang per zona waktu
│   │           └── messages.ts   teks push EN/ID (scan, keluarga: remind/disconnected/memberLeft, protection off, ringkasan)
│   │       (live.ts + routes/live.ts Dynamic Island dihapus di #555; kolom token dibuang migrasi 20261117120000)
│   │       (RelaySender + Edge Function push tidak pernah dibuat: jalur langsung lulus D7, D-alief-B11)
│   └── test/                     *.test.ts (vitest-plugin), helpers/{resetDb,seed,schema}.ts. resetDb MENGOSONGKAN DB di SHOO_TEST_DB_URL
├── db/
│   ├── scripts/                  daftar domain admin (seed, diff, golden), estimasi kuota, uji konkurensi admin
│   └── supabase/
│       ├── config.toml           supabase init
│       ├── migrations/           YYYYMMDDHHMMSS_<slug>.sql
│       ├── tests/                *.test.sql (pgTAP, dijalankan `supabase test db`)
│       └── seed.sql              data lokal (Guardian + 2 Protected + scan dari fixtures)
│       (tidak ada `functions/`: Edge Function relay APNs D-alief-16 dibatalkan oleh D-alief-B01/B11; sekarang, 15 Nov 2026: push hanya dari Worker)
└── ci/
    ├── README.md                 cara kerja Action backend
    └── app-identity.mjs, bundle-size.mjs, ops-watch.mjs (+ *.test.mjs)
    (workflow aktif ada di `.github/workflows/backend.yml` dan `ops-watch.yml`; draf `backend/ci/backend.yml` sudah dipindah)
```

Allowlist statis `src/data/allowlist.ts` (rencana awal) tidak ada lagi. Sekarang (15 Nov 2026): `db/repo/domainLists.ts:11` `isProtected` membaca `admin.v_domain_lists_public` (daftar yang diedit dashboard, ADM-09).

## 2. `ios/ShooApp/`

```text
ios/ShooApp/
├── CLAUDE.md                     (sudah ada)
├── ShooApp.swift                 @main, RootView + AppDelegate adaptor (push, environment)
├── Info.plist, Shoo.entitlements DI-GENERATE XcodeGen dari ios/project.yml: JANGAN diedit (perubahan hilang); key baru = permintaan ke Umar (TODO C3). Entitlement `applinks:join.shoo.ai.id` + `applinks:shoo-api.afindo-mi01.workers.dev` (Universal Link #129, PR-03)
├── PrivacyInfo.xcprivacy
├── App/
│   ├── AppDelegate.swift         token APNs, tap push → AppEnvironment.openPush
│   ├── AppEnvironment.swift      repository + settings + router + siklus sesi (DI)
│   ├── AppSettings.swift         bahasa, mode, Family mode, onboarding selesai, consent
│   ├── AppConfig.swift           base URL API (`#if DEBUG` localhost / Release cloud), publicBaseURL `https://join.shoo.ai.id`, shareURL `/get`, flag `cameraEnabled`
│   ├── DeepLink.swift            shoo://join?code=, https://<api host>/j/<code> (Universal Link), shoo://scan/<id>, shoo://activity, lainnya → Shield
│   ├── Router.swift              navigasi + kode undangan tertunda (`pendingJoinCode`, hilang setelah 30 menit)
│   └── RootView.swift            sessionExpired → dataConsent → main → onboarding, di bawah LaunchSplash
├── Data/
│   ├── ShooRepository.swift      protocol (semua operasi contracts/api.md yang dipakai app)
│   ├── ApiRepository.swift, APIClient.swift   URLSession, Bearer, decode error kontrak
│   ├── MockRepository.swift, MockScenarios.swift   mode demo + test, membaca Fixtures/*.json
│   ├── SessionStore.swift        Keychain + key App Group (device.*, guardian.name, base URL)
│   ├── Keychain.swift, LinkedAccountSettings.swift, CheckStats.swift, Models.swift
│   ├── ExtensionStatus.swift     baca AppGroup.Key.extensionLastSeenAt
│   └── Fixtures/                 salinan contracts/fixtures/*.json (sumber kebenaran tetap contracts/)
├── Features/
│   ├── Onboarding/               ON-01..05 (Splash, Name, TurnOnExtension + checkbox consent, SafariDefault, DataConsentView untuk device lama)
│   ├── Main/                     MainTabView, SessionExpiredView
│   ├── Shield/                   PR-04, GD-01, GD-03 (GuardianHomeModel, ProtectedShieldView, LatestScamsCard `GET /scams/latest`, HomeChrome)
│   ├── Activity/                 PR-05, GD-05
│   ├── Detail/                   DT-01..06, GD-07 (replica, VerdictLock, SafeReasonSheet)
│   ├── Profile/                  PF-01 (MemberDetail, pengaturan, "Punya kode undangan?")
│   └── Pairing/                  GD-04, PR-01..03 (FamilyCodeModel, ConnectModel, InviteSheet, QR)
├── Components/                   ScoreRing, StatusChip, AvatarView, SiteIcon, EmptyStateView, StateViews, HalftoneShield, …
├── Support/                      Formatters, L10n, AppLanguage, DeviceInfo, NotificationPermission, NotificationRouter (payload push → scanId), Log
├── Debug/                        ComponentGalleryView (#if DEBUG). ExtensionSpikeView fase 01S sudah dihapus
├── Resources/
│   ├── Localizable.xcstrings     EN (development language) + ID
│   └── Assets.xcassets
├── Tests/                        ShooAppTests (Swift Testing)
├── UITests/                      ShooAppUITests (XCUITest)
└── ci/
    └── run-tests.sh              dipakai workflow `.github/workflows/ios-app.yml`
```

`Tests/`, `UITests/`, dan `ci/` di-exclude dari target Shoo dan dimasukkan ke target test lewat PR `chore/APP-test-targets` (D-alief-02). `ContentView.swift` sudah diganti `RootView` (fase 01).
