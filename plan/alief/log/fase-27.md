# Log fase 27 — audit state machine tersirat

Plan: [`../fase-27-state-machines.md`](../fase-27-state-machines.md). Basis: `main` `02d590e4` (11 Nov 2026, setelah batch #402).

## DB terpisah (`shoo_audit`)

`vitest` mengosongkan DB di `SHOO_TEST_DB_URL`; `wrangler dev` sesi lain memakai DB `postgres` lokal. Dibuat sekali:

```bash
docker exec supabase_db_shoo bash -c '
  psql -U postgres -q -c "create database shoo_audit"
  pg_dump -U postgres --schema-only -n public -n admin -n supabase_migrations postgres > /tmp/schema.sql
  psql -U postgres -d shoo_audit -q -f /tmp/schema.sql          # 10 error "default privileges" / "schema public exists": tidak berpengaruh
  pg_dump -U postgres --data-only --disable-triggers -n admin \
    --exclude-table=admin.admin_audit --exclude-table=admin.scan_archive --exclude-table="admin.domain_intel*" \
    --exclude-table=admin.stats_daily --exclude-table=admin.analysis_runs --exclude-table=admin.case_library postgres \
    | psql -U postgres -d shoo_audit -q'
```

Lalu salin `log/fase-27-repro/audit-env.sh.txt` ke luar repo dan `source` dari root repo atau `backend/api` (mengganti `/postgres` → `/shoo_audit` di URL default `vitest.config.ts`, berhenti kalau gagal).

Baseline seluruh suite di `shoo_audit`: **724/732 lulus**, 1 dilewati. 7 gagal semuanya di trigger arsip admin (`fragments.test.ts` 4, `scans-rdap.test.ts` 2, `verdicts.test.ts` "notes reach the admin label" 1) karena data `admin` tidak disalin lengkap. Bukan temuan fase ini.

## Repro backend

`npx vitest run test/fase27-repro.test.ts` (file: `log/fase-27-repro/fase27-repro.test.ts.txt`, salin ke `backend/api/test/fase27-repro.test.ts`). Setiap test menegaskan perilaku benar, jadi gagal = temuan terbukti:

```text
     × never leaves a protected device without a guardian 181ms
     × replay: count → Mom joins G → copy joins Budi → delete old G; Mom keeps a guardian 156ms
     × (state-only variant, no timing) the ghost copy from a committed join holds a slot 109ms
     × Activity still shows the guardian's decision for the row it was made on 156ms
     × does not return to the review queue after not_safe → safe → not_safe by its only supporter 204ms
     × (probe) a guardian sees a member's scans from before they were linked 158ms
⎯⎯⎯⎯⎯⎯⎯ Failed Tests 6 ⎯⎯⎯⎯⎯⎯⎯
AssertionError: 200 but the new protected device has no guardian: expected null not to be null
AssertionError: Mom silently lost her guardian: expected null not to be null
AssertionError: copies of G linked to Budi: expected 2 to be 1 // Object.is equality
AssertionError: expected { rowVerdict: null, orphanSafe: 1 } to not deeply equal { rowVerdict: null, orphanSafe: 1 }
AssertionError: rejected domain is back in the queue: expected false to be true // Object.is equality
AssertionError: expected [ 'https://before-link.example/x' ] to not include 'https://before-link.example/x'
      Tests  6 failed (6)
```

Catatan: versi paralel F-B2/F-B3 (koneksi `postgres()` kedua memegang kunci sambil `call()` ke route) macet 20 s di pool workerd. Diganti replay berurutan memakai fungsi yang sama dengan route (`insertProtectedCopy`, `joinFamily`, `deleteDevice`) dan varian state-only.

## Repro app

Simulator "Shoo Fase27" `008727CA-5EB3-4FD4-9817-3DAFEDB0338F` (iPhone 17), derived data di scratchpad. Run pertama tanpa batas waktu macet 27 menit; run ulang:

```bash
xcodebuild test-without-building -project ios/Shoo.xcodeproj -scheme Shoo -destination 'id=008727CA-5EB3-4FD4-9817-3DAFEDB0338F' \
  -only-testing:ShooAppTests/Fase27ReproTests -test-timeouts-enabled YES -maximum-test-execution-time-allowance 60
```

```text
✘ Test inviteJoinDoesNotSwapOnboardingOutForConsent() recorded an issue at Fase27ReproTests.swift:39:9: Expectation failed: !env.needsDataConsent
✘ Test inviteJoinDoesNotSwapOnboardingOutForConsent() failed after 0.652 seconds with 1 issue.
✘ Test protectedAfterInviteStillReachesTurnOnExtension() recorded an issue at Fase27ReproTests.swift:48:9: Expectation failed: rebuilt.step != .done
✘ Test protectedAfterInviteStillReachesTurnOnExtension() failed after 0.013 seconds with 1 issue.
✘ Test failedInviteJoinSavesNoMode(code:) recorded an issue with 1 argument code → "999999" at Fase27ReproTests.swift:57:9: Expectation failed: settings.mode == nil
✘ Test failedInviteJoinSavesNoMode(code:) recorded an issue with 1 argument code → "000000" at Fase27ReproTests.swift:57:9: Expectation failed: settings.mode == nil
✘ Test failedInviteJoinSavesNoMode(code:) recorded an issue with 1 argument code → "888888" at Fase27ReproTests.swift:57:9: Expectation failed: settings.mode == nil
​✘ Test failedInviteJoinSavesNoMode(code:) with 3 test cases failed after 0.053 seconds with 3 issues.
✘ Test loadingMoreSpinnerClearsAfterAFailedRefresh() recorded an issue at Fase27ReproTests.swift:75:9: Expectation failed: !model.isLoadingMore
✘ Test loadingMoreSpinnerClearsAfterAFailedRefresh() failed after 0.431 seconds with 1 issue.
✘ Test homeVerdictIsNotUndoneByAnOlderRefresh() recorded an issue at Fase27ReproTests.swift:93:9: Expectation failed: model.scans.first { $0.id == decided.id }?.verdict != nil
✘ Test homeVerdictIsNotUndoneByAnOlderRefresh() failed after 0.353 seconds with 1 issue.
✘ Test run with 5 tests in 1 suite failed after 1.513 seconds with 7 issues.
** TEST EXECUTE FAILED **  (5 test, 7 asersi gagal, 1,5 s)
```

## Verifikasi dengan membaca kode (11 Nov 2026)

- F-A6: `MainTabView.swift:76-78` identitas = `ObjectIdentifier(env.repository)` + familyMode; `becomeProtected` tidak mengganti repository → model Activity lama dipakai.
- F-A8: `AppEnvironment.swift:200-228` `register()` tidak menyentuh `sentDeviceInfo`; `:398` (`becomeProtected`) mereset.
- F-N1: `GuardianHomeModel.swift:207` dan `MockRepository.swift:369-371` memasang verdict per domain; backend per link (`db/repo/verdicts.ts:87-90`).
- F-N2: `AppEnvironment.swift:436-450` hanya Guardian membuka Detail; komentar menyatakan push Protected tanpa `scanId`, padahal `routes/scans.ts:192` → `ownPush` (`notify.ts:72`).
- F-N3: `MemberDetailModel.swift:112-126` + `MemberDetailView.swift:54-56` tanpa `DeliveredPushes.clear()`; pemanggil lain ada di `FamilyCodeModel.swift:196`, `ProfilePages.swift:34`, `AppEnvironment.swift:322,356,401`.
- F-B6: `routes/devices.ts:176` (setelah #402) `hit(sql, limits.becomeProtected, oldId)` = 30/jam per device saja (`rateLimit.ts:21`). Batas percobaan join 5/device tidak pernah tercapai (id salinan baru tiap percobaan) dan baris per IP ikut terhapus cascade. **Masih terbuka** (review ronde 1), dikerjakan di 27a.
- F-B7: komentar `db/repo/verdicts.ts:114-115` menyatakan penghapusan "rejected or not" disengaja (D-alief-40); perbaikan harus menjaga privasi itu (K5).
- F-A7: `ios/ShooApp/App/LiveActivityTokens.swift` ada di `main` (#386 lewat #402). Ditutup.
