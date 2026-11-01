# Cek lintas fase 19–26 (1 Nov 2026)

Worktree `.claude/worktrees/alief-plan-19-26`, branch `docs/alief-plan-19-26`. Kode dicek di `origin/main` b88a962. Plan ditulis terhadap 2720b13; sejak itu #204 dan #205 sudah MERGED (31 Okt 15:40 UTC).

## Yang diperbaiki di file fase

Semua perubahan ada di baris yang sama, jadi rujukan baris antar-fase tetap benar (dicek ulang). Tiap file mendapat satu baris `- Cek lintas fase (1 Nov 2026): …` di `## Riwayat verifikasi`.

- **19 ↔ 21, gauge vs drop**: fase 19 K5.1/K5.2 dan fase 21 K3 `:131`, `:136`, runbook `:185` sekarang memperlakukan `level` gauge (`ok`/`reserve`/`full`) sebagai **keadaan** kuota. Drop dibuktikan hanya oleh event `replica_dropped` dengan `reason` `global_*`. Runbook memeriksa ada drop nyata dulu sebelum kill-switch. Hitungan per alasan hanya lewat custom alert Cloudflare (fase 21 C7, belum terverifikasi). Catatan fase 19 Ronde 2 tentang `:131` sudah usang dan ditandai.
- **20 ↔ 21, gerbang retensi**: fase 20 langkah 20c.1 dan LANGKAH MANUAL 3 sekarang meminta run **sesudah** deploy 20b. Buktinya `/ops/status` `jobs.retention.failed = 0` dengan `ageHours` lebih muda dari deploy 20b (kalau 21a sudah live), atau log `retention`. Fase 21 `:278` sudah menyatakan hal yang sama.
- **20 ↔ 22, file app**: 20d memecah `ScreenshotView.swift` dan mengganti nama helper di `ReplicaLoader.swift`/`SiteIcon.swift`, padahal 22b/22c mengubah file yang sama. Aturan rebase dan peta file baru ada di Catatan handoff fase 22 dan Riwayat fase 20. Baris `DetailView.swift` di 20d bergeser karena #204.
- **CI `.github/`**: fase 22 K11 (langkah `bundle-size.mjs`) digabung menjadi pertanyaan 4 issue CI backend fase 21 K7. Diubah di fase 21 K7 dan Peta, serta fase 22 C-kesimpulan, Peta, K11, langkah 12, LANGKAH MANUAL 5, DoD. iOS CI (fase 23 K5) tetap issue sendiri.
- **23 ↔ 20**: fase 23 menyebut "20b" untuk `DetailUITests`. Yang benar **20d**; sudah diperbaiki di Fase berikutnya dan handoff. Bentrok `AppEnvironment.swift`/UITest dengan 26a ditambahkan.
- **24 ↔ 21**: langkah `inactive_devices` harus jalan sebelum `finishJob('retention')` (Peta fase 24). Dengan begitu gagalnya masuk `failed`.
- **24 ↔ 19**: tidak ada konflik. Device kandidat hapus tidak punya upload 24 jam, dan akar keluarganya sama. Dicatat di kedua file.
- **Fakta usang/berbeda**:
  - Sumber angka CPU (`POST /scans` 52–186 ms) sekarang `log/fase-18.md:92` di `main` (fase 19 C6, fase 21 `:19`, fase 22).
  - Status #204/#205 MERGED (fase 22 Prasyarat/Bacaan, fase 23 Prasyarat/handoff, log fase 18 `:128` → `:129`).
  - LANGKAH MANUAL 3 fase 18 lulus, tetapi CPU cron tetap belum terukur (fase 19 Prasyarat, fase 20 C18).
  - Biaya penyerang fase 19 Risiko sekarang ±2,3–4× (sama dengan K2).
  - `screenshot_dropped` hilang sejak 20a (fase 19 K5.3 + handoff).
  - Fase 22 K12 merujuk akar keluarga fase 19 C1/K5.2, bukan K4.
  - Fase 26: `join-page.ts:38-46` → `39-47`, `project.yml:154-174` → `164-174`.
- **Branch**: 26 nama, semua unik. Tidak bentrok dengan branch remote yang ada.
- **K**: tidak ada keputusan yang bertentangan antar fase. Nomor K per fase bentrok namanya (mis. "K7" = issue di fase 20 dan 21), jadi selalu tulis "fase NN K#".

## (a) Urutan yang disarankan

Alief sendirian. "Paralel" berarti boleh diselang-seling tanpa bentrok file, bukan subagent paralel.

| # | Fase | Track | Bergantung pada | Bisa mulai kapan | Alasan urutan |
|---|---|---|---|---|---|
| 0 | Bug kecil (d1, d2/d3 setelah K10) | app/be | K10 mailbox untuk d2/d3 | Sekarang | Bug yang terlihat pengguna, PR kecil |
| 1 | 20 LANGKAH MANUAL 1 (G2) + issue fase 20 K7 | manual | — | Sekarang | G1 (≥ 15 hari) adalah jalur kritis terpanjang (20b paling cepat ±16 Nov) |
| 2 | 20a `fix/EX-07-ignore-screenshot-upload` | be | G2 lulus, issue fase 20 K7 dibuat | Hari G2 lulus | Menghentikan jam G1; screenshot tidak lagi sinkron sebelum push |
| 3 | 23a `fix/C2-test-flakes` (+ issue 23 K5) | app | #204 (sudah merge) | Sekarang | CI iOS hijau dulu untuk semua PR app berikutnya |
| 4 | 21a `feat/B9-ops-status` (+ issue CI backend fase 21 K7) | be | Jawaban fase 21 K1/K3/K6 | Sekarang | Memberi bukti gerbang 20b→20c dan memantau dry-run 24a |
| 5 | 19a `feat/EX-07-replica-family-quota` | be | K2/K3 + LANGKAH MANUAL 1 fase 19 | Setelah jawaban Alief | Harus sebelum 20b, 21c, 22a-2 (file sama: `db/repo/scans.ts`, `services/replicas.ts`, `test/replicas.test.ts`) |
| 6 | 26a `feat/PR-03-deferred-invite-app` | app | Spike 26-0; sebaiknya setelah 23a (helper + `AppEnvironment.swift`) | Setelah 23a | Bebas dari backend; bug U6 bisa dipisah lebih dulu |
| 7 | 22a-0 baseline → 22a-1 `fix/BE-worker-cpu` | be | Jawaban fase 22 K1–K3 | Setelah 19a merge (tidak wajib) | Sebelum 20b supaya 20b memindah cache kunci ke `signedLinks.ts` (atau sebaliknya, fase 22 handoff) |
| 8 | 21c `feat/EX-07-ops-replica` | be | 19a merge | Setelah 19a | Memakai `replicaUsage` |
| 9 | 22a-2 `fix/EX-07-replica-inflate` | be | 19a merge, fase 22 K4/K12 | Setelah 19a | Kuota awal di `precheckReplica` memakai rumus fase 19 |
| 10 | 22b `fix/DT-04-snapshot-perf` | app | #204/#205 (sudah), fase 22 K7–K9 setelah S6/S7 | Setelah 23a | Sebelum 20d supaya 20d yang rebase (20d tertahan G1) |
| 11 | 20b `feat/EX-07-screenshot-sunset` | be | G1 + G3–G5 nol, 19a merge | ≥ ±16 Nov | Menulis ulang `retention.ts` (satu store) |
| 12 | 20d `feat/DT-04-screenshot-sunset` | app | G1; rebase di atas 22b | ≥ ±16 Nov | Boleh berselang dengan 20c |
| 13 | 20c `feat/EX-07-drop-screenshot-columns` + LANGKAH MANUAL 3–4 (cabut kunci) | be | 20b live + 1 run retensi `failed: 0` (lewat `/ops/status`) + G6 | ±17–18 Nov | Drop kolom satu deploy setelah 20b |
| 14 | 24a-1 `feat/E7-inactive-devices` (dry_run) | be | Setelah 20b + 21a (rebase `retention.ts`) | Setelah 20b | Tiga fase mengubah `retention.ts`; yang terakhir paling sedikit rebase |
| 15 | 24c-1/24c-2 sisa (`/support`, manifest) + issue E6 | be/app | K10–K12 | Kapan saja | Prasyarat TestFlight eksternal (fase 16) |
| 16 | 24b-1 `feat/C22-shared-keychain` + issue C22 | app | Spike S1 | Kapan saja (tidak mendesak) | — |
| 17 | 21b `feat/B9-ops-watch` | be/CI | 21a live, issue CI backend dijawab, LANGKAH MANUAL 4 | Setelah Umar | Workflow milik Umar |
| 18 | 25-0 + 25a-be `feat/EX-06-verdict-latency-log` + issue EX-06 | be | — | Kapan saja | Kecil; baseline untuk K8 |
| 19 | 25b spike → 25c | be | Umar Q2–Q4, go K8, kontrak | Setelah Umar | Paling banyak ketergantungan luar |
| 20 | 24a-2 `feat/E7-inactive-devices-on` | be | 7 run dry-run `failed: 0`, K1/K3/K4 | ≥ 7 hari setelah 24a-1 | Hapus pertama nyata ±Jan 2027 |
| 21 | 26b `feat/PR-03-deferred-invite-page` | be | Teks: tidak ada; `APP_STORE_URL`: issue PR-03 Q1 | Teks kapan saja | — |
| 22 | 23c, 22c, 22a-3 (opsional), 24b-2 | app/be | 23a; fase 22 K10; S3 positif; PR Umar C22 | Terakhir | Opsional / menunggu Umar |

Jalur kritis: G2 → 20a → (15 hari) → 20b → 20c. Sambil menunggu G1, kerjakan 21a, 19a, 22a-1, 23a, 26a, 22b.

## (b) Issue ke Umar (setelah digabung)

Semua memakai template question, label `question`, assign @umarmuhdhor.

1. **`EX-07: remove deprecated screenshotBase64 / screenshotUrl (fase 20)`** (fase 20 K7; dibuat sebelum merge 20a)
   1. Hapus field + fixture + `ShooShared/ScanResult.swift:13` setelah 20d merge?
   2. Sampai itu, backend boleh `screenshotUrl: null` dan mengabaikan `screenshotBase64`?
   3. Fixture app disalin Alief (pola 18f) atau Umar?
   4. `docs/mandates/alief.md:52,56` ikut diperbarui?
2. **`B9: CI backend — workflow ops-watch, environment ops, langkah backend.yml`** (fase 21 K7 **digabung dengan fase 22 K11**; sebelum 21b)
   1. Alief boleh menulis `ops-watch.yml` lewat PR, dengan logika di `backend/ci/ops-watch.mjs`?
   2. Umar membuat Environment `ops` + 3 secret + var `OPS_WATCH_ENABLED`?
   3. Issue publik `ops-alert` (isi kode saja) boleh jadi kanal alert?
   4. `backend.yml` job `test` boleh menjalankan `node --test backend/ci/` + `node backend/ci/bundle-size.mjs` setelah Worker build check (`:44-47`)?
   5. `public-blocklist.yml` ikut dicek ops-watch, atau cukup notifikasi GitHub ke Umar?
3. **`C2: iOS CI — pisah job unit/UI, xcresult, retry UI, timeout`** (fase 23 K5; tetap terpisah karena file `ios-app.yml` dan topiknya lain)
   1. Pisah job unit/UI, `timeout-minutes: 45` untuk UI?
   2. xcresult jadi artifact saat gagal (7 hari)?
   3. Retry hanya UI, dengan daftar "lolos setelah retry" di summary?
   4. Batas waktu per test (`-default-test-execution-time-allowance 300`)?
   5. Simulator dipilih lewat UDID, bukan nama?
4. **`C22: token device dari App Group ke Keychain bersama`** (fase 24)
   1. Access group = `AppGroup.id`, atau `keychain-access-groups` eksplisit?
   2. Konstanta service/account di `ShooShared/AppGroup.swift`?
   3. `sessionReply()` membaca Keychain dulu, App Group sebagai cadangan?
   4. `device.token` di kontrak ditandai deprecated lalu dihapus satu rilis kemudian?
   5. Helper Keychain untuk extension ditulis Umar, atau `KeychainItem` dipindah ke `ShooShared/`?
5. **`E6: App Privacy App Store Connect + data extension/AI`** (fase 24)
   1. `ai/` menyimpan/me-log apa per request selain cache RDAP?
   2. Manifest extension tetap tanpa tipe data?
   3. Siapa mengisi App Privacy + Privacy/Support URL (usulan isian K12)?
   4. Ada keberatan tetap di workers.dev (`associated-domains`)?
6. **`EX-06: verdict realtime + jadwal polling layar blokir`** (fase 25)
   1. Jadwal polling adaptif + teks kontrak?
   2. WebSocket dari `blocked.html` (pengecualian `ShooExtension/CLAUDE.md:21,24`) dan siapa yang menjalankan spike S2 di device?
   3. Endpoint + format tiket?
   4. Pesan background `liveTicket` (juga Chrome)?
   5. Flag `on` hanya setelah build extension ada di TestFlight?
7. **`PR-03: store link for the invite page Install button`** (fase 26; tautkan #55; terkait issue 5 karena pemegang akun App Store Connect sama, tetapi topiknya beda)
   1. Link publik TestFlight atau belum ada?
   2. (Info) Ada aturan App Review soal `PasteButton`?
8. **Opsional / bersyarat**:
   - Fase 24 K9 `EX: extension berhenti memanggil API setelah 401`: satu pertanyaan, prioritas rendah.
   - Fase 19 K8 `EX-07: atestasi device (App Attest/DeviceCheck)`: hanya kalau fase 21 menunjukkan drop `global_*` nyata.
   - Fase 22 K4 (b) dan fase 19 C7: cukup komentar di #176, bukan issue baru.

Total wajib: 7 issue (sebelumnya 8; fase 22 K11 digabung ke issue 2).

## (c) Keputusan yang harus dijawab Alief

| Fase | K | Rekomendasi |
|---|---|---|
| 19 | K2 | Per keluarga 60 upload + 10 MB / 24 jam; device 50, IP 300, global tetap; tanpa batas churn join (masuk TODO kalau gauge `global_*`) |
| 19 | K3 | (b) cadangan 20 % terakhir global untuk keluarga < 10 upload |
| 20 | K1 | (b) 20a dulu, lalu 20b, lalu 20c |
| 20 | K5 | Ganti nama ke `objectStore.ts` / `signedLinks.ts`; `SCREENSHOT_URL_SECRET` tetap |
| 20 | K8 | VoiceOver "Copy of the page" EN/ID; identifier tetap |
| 20 | K9 | Matikan kunci JWT legacy kalau tidak terpakai (opsional) |
| 21 | K1 | A: workflow GitHub Actions `ops-watch` |
| 21 | K3 | Angka ambang di tabel K3 (26 jam, 350/450 MB, 15 hari 6 jam, dst.) |
| 21 | K6 | Token header, 404 tanpa token, isi issue kode saja |
| 22 | K1 | (a) p50 ≤ 10 ms per rute DB, p99 tanpa `exceededCpu` |
| 22 | K2 / K3 | `import * as z` / `minify` + source map |
| 22 | K4 | (a) slice 16 KB, yield `setTimeout` tetap |
| 22 | K5 | Dari S3; bawaan (b) tetap transaksi |
| 22 | K6 | (a) tetap Free |
| 22 | K7 / K8 / K9 | (a) 390 × 1800 pt / (a) kalau WebContent < 100 MB / (a) hapus kode mati |
| 22 | K10 / K12 | (a) cache favicon (22c) / (a) cek kuota sebelum slot IP + inflate |
| 23 | K1 | (c) retry hanya UI |
| 23 | K2 / K3 / K4 | (a) `-UITestReduceMotion` / (a) batas 5 s + rasio / (a) `WebKitTests` serial |
| 23 | K6 / K7 | (a) satu simulator, skrip host / (a) `replica-ui.sh` baru |
| 24 | K1 / K3 / K4 / K5 | 90 hari / keluarga satu unit / 30 hari registrasi tak terpakai / tanpa push |
| 24 | K10 / K11 / K12 | Mailbox tim gratis (**mendesak**, bug d2) / tetap workers.dev / deklarasi lebih (User ID, Product Interaction, Coarse Location, Other) |
| 25 | K1 | (b) adaptif + spike DO (juga Umar) |
| 25 | K7 / K8 | Log `verdict_seen` ya / kriteria go-no-go seperti tertulis |
| 26 | K1 / K4 / K7 | Kartu di splash + Connect / ketat / kosongkan clipboard setelah join |

## (d) Bug di kode sekarang yang bisa diperbaiki tanpa menunggu plan

Semua dicek di `origin/main` b88a962.

1. `ios/ShooApp/Features/Pairing/ConnectModel.swift:60-65`: setter `code` memfilter digit dari seluruh teks. Kalau link `https://shoo-api.afindo-mi01.workers.dev/j/482193` ditempel, hasilnya `014821` (digit `mi01` ikut), lalu `code_invalid`. Hal yang sama terjadi kalau pesan undangan (`FamilyCodeModel.swift:185-187`) ditempel utuh. Perbaikan = U6 fase 26 (`InvitePaste.code(inText:)`), bisa jadi PR kecil sendiri.
2. `ios/ShooApp/App/AppConfig.swift:29-30`: `supportEmail = "halo@shoo.id"`, padahal `shoo.id` NXDOMAIN (dig 31 Okt). "Contact us" di `Features/Profile/ProfilePages.swift:1364-1365` mengirim ke domain yang tidak ada, dan pemilik domain di masa depan bisa menerima email pengguna. Butuh mailbox fase 24 K10.
3. `backend/api/src/routes/privacy.ts:11-12`: kontak di halaman privasi publik masih placeholder ("contact address coming before public release"). Sama, butuh K10 (24c-1).
4. `backend/api/wrangler.jsonc:26`: `APP_STORE_URL` kosong, jadi tombol Install di `/j/<kode>` dan `/get` membuka beranda App Store, bukan Shoo. Ini konfigurasi; nilainya dari Umar (issue 7).
5. `backend/api/src/routes/scans.ts:132-139`: screenshot dari build lama di-decode/upload **sinkron sebelum** lookup push, jadi push ke Guardian tertunda. Perbaikannya 20a (kecil), siap setelah G2.
6. `ios/ShooApp/Features/Detail/DetailView.swift:361`: `Task.detached` tidak ikut dibatalkan saat Detail ditutup. Dua pindai 3 MB tetap jalan (CPU sia-sia). Fase 22 C14, perbaikan `nonisolated async`.
7. `ios/ShooApp/UITests/DeepLinkUITests.swift:14-24`: launch tanpa `-UITestReset YES`, jadi setelan test sebelumnya terbawa. Ini salah satu penyebab flake F4 (fase 23 C5).
8. `backend/api/src/services/screenshotLinks.ts:14-15`: `importKey` HMAC dipanggil per link (≤ 50 per `GET /scans`). Ini CPU, bukan salah perilaku; fase 22 O1.
9. (Rendah) `backend/api/src/db/repo/devices.ts:155-173`: `deleteDevice` tanpa `lock_timeout`, jadi `DELETE /devices/me` bisa menunggu kunci lama. Fase 24 K7 hanya menambahkannya untuk jalur cron. `backend/api/src/app.ts:85`: log `onError` tanpa field `event` (fase 21 handoff).

## Belum terverifikasi (dari cek ini)

- Isi `log/fase-18.md:90,92,113-114,129,131` dibaca dari `origin/main`, bukan dari worktree (worktree di belakang `main`).
- Bentrok rebase di daftar fase 25 (`vitest.config.ts`, `app.ts`, `env.ts`, `wrangler.jsonc`) adalah prediksi dari Peta dampak, belum dicoba.
