# Log fase 28: truth hunt (cari dan buktikan, tanpa perbaikan)

Plan: [`../fase-28-truth-hunt.md`](../fase-28-truth-hunt.md). Matriks edge case: [`../qa/edge-matrix-2026-11-13.md`](../qa/edge-matrix-2026-11-13.md). Bukti: [`fase-28-repro/`](fase-28-repro/), [`../qa/img/fase-28/`](../qa/img/fase-28/). Putusan reviewer per ID dan review plan: [`fase-28-review.md`](fase-28-review.md).

Tanggal run: 13 Nov 2026. Enam hunter (h1 sampai h6), tiga reviewer (r1 sampai r3). **Kalau hunter dan reviewer berbeda, angka reviewer yang dipakai.** Keluaran program di blok kode disalin apa adanya (format angka Inggris). Di luar blok kode angka memakai format Indonesia.

Tidak ada kode produk yang diubah. Tidak ada commit, push, PR, atau issue. Cloud tidak disentuh. Tidak ada secret, token, atau data pribadi di file ini; URL DB ditulis `<redacted>`.

## Lingkungan

| Hal | Nilai |
|---|---|
| Worktree | `.claude/worktrees/fase-28-hunt` di checkout lokal |
| Branch | `docs/alief-fase-28-truth-hunt` |
| Commit dasar | `git rev-parse --short HEAD` → `9e5403ba` · `git merge-base HEAD origin/main` → `9e5403bac388ebb35aac1d0fcec35838aae2512b`. `HEAD` = `origin/main` saat ketiga reviewer bekerja (`git fetch origin`, tanpa selisih), jadi tidak ada temuan yang "sudah diperbaiki di main" |
| PR terbuka saat audit | hanya #484 (`fix/ON-04-figma-only`, mengubah `TurnOnExtensionView.swift`; terkait U-06) |
| Container DB | `supabase_db_shoo_hunt`, Postgres 17.6, port **54522** |
| DB vitest | `shoo_f28` (dikosongkan `resetDb` di setiap run) |
| DB performa | `shoo_f28_perf` (seed 320.000 scan; reviewer hanya SELECT / EXPLAIN, `default_transaction_read_only = on`) |
| DB yang **tidak** disentuh | Tabel DB dev di port **54322**, dan database `postgres` di container hunt. Storage stack dev menerima objek screenshot uji dari `scans.test.ts` (§Cara menunjuk vitest) |
| Simulator | "Shoo F28" (`F9F316F4-910B-461E-AE70-EF2753537144`, iPhone 17, iOS 27.0), "Shoo F28 SE" (iPhone SE generasi 3), "Shoo F28 Max" (iPhone 17 Pro Max). Dibuat untuk sesi ini; simulator lain tidak disentuh |
| Figma | file `6PgxbrY0LSkcdaJ5u4YBJP`, page 18:2. **Baca saja** (`get_metadata`, `scan_text_nodes` pada 1685:5288 dan 1619:2259, `get_screenshot` per frame). Hanya hunter 4 yang membukanya |
| Mesin | Mac Apple silicon. Angka waktu = lokal, cache hangat. Produksi (Supabase Free) lebih lambat; bentuk plan sama |

### Cara menunjuk vitest ke DB terpisah

`vitest` mengosongkan DB lewat **dua** koneksi, jadi **dua** variabel wajib menunjuk DB terpisah:

- `SHOO_TEST_DB_URL` (role `shoo_api`): `resetDb` menghapus 10 tabel `public` lewat koneksi ini (`push_log`, `verdicts`, `scans`, `join_attempts`, `family_codes`, `family_links`, `ops_heartbeat`, `rate_limit_hits`, `storage_tombstones`, `devices`; `backend/api/test/helpers/resetDb.ts:21-28`). Kalau **tidak di-set**, nilainya jatuh ke DB dev `54322/postgres` (`backend/api/vitest.config.ts:6`).
- `SHOO_TEST_ADMIN_DB_URL` (role `postgres`): `resetDb` menghapus `blocklist_entries` dan `ops_jobs` lewat koneksi ini (`backend/api/test/helpers/resetDb.ts:29-32`), dan `withoutTriggers` menulis baris massal di sana (`:40-46`). Kalau **tidak di-set**, nilainya jatuh ke DB dev `54322/postgres` (`backend/api/vitest.config.ts:8`).

`??` di `vitest.config.ts:6,8` hanya jatuh ke 54322 untuk variabel yang tidak di-set. Variabel yang di-export sebagai string kosong tidak jatuh ke sana (koneksinya gagal), tetapi `db_guard` di bawah tetap menolaknya.

Di luar cakupan guard: Storage. `vitest.config.ts:12-22` memakai Storage stack dev (`supabase status -o json` di `backend/db`) kecuali `SHOO_TEST_SUPABASE_URL` + `SHOO_TEST_SUPABASE_KEY` di-set; `env.sh` hanya mengisi dua URL DB. `scans.test.ts` mengunggah objek screenshot uji ke sana (`:62,393`). Itu menambah objek dan hanya menghapus path uji, jadi tidak ada data dev yang hilang; tabel DB dev tetap tidak disentuh.

Hanya mengisi `SHOO_TEST_DB_URL` tetap mengosongkan `blocklist_entries` + `ops_jobs` DB dev (memori "Backend vitest wipes dev DB" baru menyebut variabel pertama). Semua hunter dan reviewer men-`source` satu file `env.sh` dari `backend/api` sebelum setiap run. File itu mengisi **kedua** variabel. Isinya, tanpa kredensial:

```bash
# source dari backend/api. Mengambil dua URL default dari vitest.config.ts
# (role shoo_api dan role postgres) dan mengganti ujungnya:
#   :54322/postgres  →  :54522/shoo_f28
export SHOO_TEST_DB_URL=<redacted>          # berakhir di 54522/shoo_f28
export SHOO_TEST_ADMIN_DB_URL=<redacted>    # berakhir di 54522/shoo_f28
case "$SHOO_TEST_DB_URL" in *54522/shoo_f28) ;; *) echo "env: DB URL not rewritten, abort"; return 1;; esac
```

Guard di `env.sh` itu hanya mengecek variabel pertama, dan `env.sh` tinggal di folder sesi hunt (tidak di repo). Untuk setiap run berikutnya (sub-fase 28j sampai 28o, plan → Verifikasi, dan header run file `fase-28-repro/*.test.ts.txt`) pakai blok di bawah. **Ini satu-satunya definisi `db_guard`**; plan dan file repro merujuk ke sini. Tempel sekali ke shell (bash atau zsh), isi placeholder sendiri. **zsh:** tanpa opsi `interactivecomments` (bawaan macOS kalau tidak ada framework yang menyalakannya) baris `#` ikut terbaca sebagai perintah dan mencetak error; jalankan `setopt interactivecomments` dulu, atau tempel tanpa baris komentar. Nilai return guard tetap benar di kedua shell.

```bash
# Kedua variabel wajib di-export (vitest membaca process.env; variabel shell tanpa export tidak sampai).
# SHOO_TEST_DB_URL: role shoo_api, DB terpisah. SHOO_TEST_ADMIN_DB_URL: role postgres, DB terpisah yang sama.
# db_guard: return 1 kalau salah satu variabel tidak di-set, kosong, tidak di-export, atau menunjuk DB dev (54322).
export SHOO_TEST_DB_URL=postgres://<user>:<pass>@127.0.0.1:<port>/<db>
export SHOO_TEST_ADMIN_DB_URL=postgres://<user>:<pass>@127.0.0.1:<port>/<db>
db_guard() {
  local n v
  for n in SHOO_TEST_DB_URL SHOO_TEST_ADMIN_DB_URL; do
    v=$(printenv "$n" || true)
    case "$v" in ""|*54322*) echo "$n tidak di-set / kosong / tidak di-export / DB dev (54322): berhenti" >&2; return 1;; esac
  done
}
```

**Aturan pakai:** setiap perintah yang menjalankan vitest adalah **satu perintah berantai** di belakang guard, misalnya `cd backend/api && db_guard && npx vitest run test/<file>` atau, dengan salinan repro, `db_guard && cp … && npx vitest run …`. Jangan pernah menaruh `cp` atau `npx vitest` di baris terpisah setelah guard: guard yang gagal di barisnya sendiri hanya mencetak pesan, lalu baris berikutnya tetap jalan, dan `vitest.config.ts:6,8` jatuh ke `54322/postgres` untuk variabel yang tidak ada. Kalau `db_guard` belum ditempel di shell, `db_guard &&` gagal dengan "command not found" dan vitest juga tidak jalan.

Setiap reviewer mengecek ujung **kedua** URL (`54522/shoo_f28`, hitungan 1) sebelum run pertama. Untuk bench rute h5 kedua variabel diarahkan ke `…/shoo_f28_perf`.

Perintah pembuatan `shoo_f28` dan container hunt **tidak tercatat** di laporan hunter. Polanya sama dengan `shoo_audit` di [`fase-27.md`](fase-27.md) → "DB terpisah": database baru, skema `public` + `admin` + `supabase_migrations` dari dump, data `admin` sebagian. Cek bahwa keduanya ada:

```text
$ docker exec supabase_db_shoo_hunt psql -U postgres -Atc "select datname from pg_database where datname like 'shoo%' or datname='postgres'"
postgres
shoo_f28
shoo_f28_perf
```

Perubahan lingkungan di dalam `shoo_f28_perf` saja: ekstensi `pgcrypto` dan `pg_stat_statements` di skema `extensions` (tanpa `pgcrypto` trigger scan gagal di setiap insert), skema kerja `h5`, dan 4 device yang `token_hash`-nya diganti untuk bench.

### Baseline suite di `shoo_f28`

**793 lulus, 7 gagal yang sudah diketahui, 1 dilewati.** Tujuh yang gagal adalah lingkungan (data `admin` tidak disalin lengkap), sama dengan fase 27, dan **bukan temuan**:

| File | Gagal |
|---|---|
| `fragments.test.ts` | 4 |
| `scans-rdap.test.ts` | 2 |
| `verdicts.test.ts` ("notes reach the admin label") | 1 |

Suite lain yang dijalankan apa adanya (h3): extension 314 / 314, detector 72 / 72, chrome 49 / 49. `ai`: 194 test, 184 lulus, 10 file gagal dengan `ERR_MODULE_NOT_FOUND 'hono'` karena worktree ini tanpa `node_modules`. Lingkungan, bukan temuan.

### Aturan run

- Test repro disalin dari `fase-28-repro/*.txt` ke suite, dijalankan, lalu salinannya dihapus. `git status --short` sesudahnya hanya menampilkan path `plan/alief/`.
- Backend saat hunt: kedua variabel diisi `env.sh` (folder sesi, tidak di repo) sebelum setiap run. Run berikutnya: `cd backend/api && db_guard && npx vitest run test/<file>`, satu perintah, dengan `db_guard` dan kedua variabel dari §Cara menunjuk vitest ke DB terpisah.
- App: selalu `-test-timeouts-enabled YES -maximum-test-execution-time-allowance 60` (UI: 120), `-parallel-testing-enabled NO`. Bendera batas waktu membatasi tiap test, bukan proses: satu run (F, SE AX5) tidak berhenti sendiri setelah test terakhir dan diakhiri manual (penanganan: plan §Verifikasi).
- Satu run pertama dengan `CODE_SIGNING_ALLOWED=NO` berakhir di `KeychainItem.Failure.status(-34018)` dan dibuang. Semua angka app dari run bertanda tangan.
- Run pertama tiga file kebenaran h1 sebagai satu file berakhir di Postgres `53300` (terlalu banyak koneksi) setelah sekitar 60 test. Itu runtime test (satu klien per permintaan), bukan temuan. Angka di bawah dari run terpisah per file.

## Repro per temuan

Urutan: P1, P2, lalu P3 yang punya repro, lalu butir "perlu pertanyaan", lalu butir milik Umar / Imelda, lalu yang ditolak. Setiap blok: perintah, baris penentu, lalu baris jalan ulang reviewer.

### Jalan ulang reviewer (ringkas)

| Reviewer | File | Hasil |
|---|---|---|
| r1 | `h1-truth` | `Tests 4 failed \| 21 passed (25)`: B-02a, B-02b, B-01, B-03 |
| r1 | `h1-extra` | `Tests 7 failed \| 25 passed (32)`: B-01b, B-01c, B-05, B-06, B-07 × 3 |
| r1 | `h1-identity` | `Tests 4 failed \| 32 passed (36)`: dot segment, empty port, B-04 unicode path, B-04 dot segment |
| r1 | `h2-poison` | `Tests 3 failed \| 1 passed (4)`: spasi 500 (23514), tab 422, newline 422; backslash 201 |
| r2 | `H2TruthTests` | `✘ Test run with 20 tests in 1 suite failed after 2.391 seconds with 40 issues.` (hunter: 39) |
| r3 | `h3-chain.mjs`, `h3-fail.mjs`, `h3-norm.mjs` | baris BUG yang sama; `cells run: 84; FAIL-WRONG: 10`; `rows 33, disagreement 12` |
| r3 | `h3-chain.test.ts` | `H3 scans \| rows 15 \| refused 6`; `Tests 3 failed \| 5 passed (8)` |

**Tidak dijalankan ulang reviewer:** `h1-matrix` (1.642 sel), `h1-concurrency`, `h5-route-bench`, seed h5, matriks XCUITest h4, halaman web h4. Angkanya dari hunter saja.

Perintah yang dipakai r2 untuk test app (dipakai di semua blok A-* di bawah):

```bash
cp plan/alief/log/fase-28-repro/h2-H2TruthTests.swift.txt ios/ShooApp/Tests/H2TruthTests.swift
(cd ios && xcodegen generate)                      # Shoo.xcodeproj di-gitignore
xcrun simctl boot F9F316F4-910B-461E-AE70-EF2753537144
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination 'id=F9F316F4-910B-461E-AE70-EF2753537144' \
  -derivedDataPath <scratch>/dd -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 60 \
  -only-testing:ShooAppTests/H2TruthTests           # sekitar 2 menit; akhiri prosesnya sendiri
rm ios/ShooApp/Tests/H2TruthTests.swift && (cd ios && xcodegen generate)
xcrun simctl shutdown F9F316F4-910B-461E-AE70-EF2753537144
```

Perintah untuk test backend (dipakai di semua blok B-* di bawah; ganti nama file):

```bash
# db_guard + kedua variabel: §Cara menunjuk vitest ke DB terpisah (ditempel ke shell ini). Satu perintah berantai:
cd backend/api && db_guard \
  && cp ../../plan/alief/log/fase-28-repro/h1-truth.test.ts.txt test/r1-truth.test.ts \
  && { npx vitest run test/r1-truth.test.ts; rm test/r1-truth.test.ts; }
```

### P1

**A-01 · Guardian Home dan Protected Home tetap menenangkan setelah refresh gagal** (`h2-H2TruthTests.swift.txt`: `BUG_A01_*`, `cell_refreshFailsAfterALoad`)

```text
H2 A-01 guardian-home | server has undecided blocked scan: true | hero 'Family protected!': true | says it may be old: false
H2 A-01 protected-home | pill 'Protected by Adhella' | state loaded | says it may be old: false
✘ Test cell_refreshFailsAfterALoad(_:) with 8 test cases failed after 0.149 seconds with 6 issues.
```

r2: sama, 6 dari 8 sel gagal. `git log -S refreshFailed -- ios/ShooApp/Features`: baris itu ada di `f6f5afde` dan hilang saat redesign Home. Tiga dari enam sel (Detail, Profile, Member detail) menjadi pertanyaan Q16, bukan bug.

**U-01 · Hero Guardian Home bilang "Keluarga Terlindungi!" saat muatan pertama** (`h4-Fase28MatrixUITests.swift.txt`: `test022_home_g_loading`, konfigurasi A dan F)

```text
A/home-g-loading.json         [('home.family.protected', 'Keluarga Terlindungi!')]
```

Pohon terekam, bukan asersi: [`h4-tree-A-home-g-loading.json.txt`](fase-28-repro/h4-tree-A-home-g-loading.json.txt) (`home.family.protected` y 308,3). r2: tidak dijalankan ulang; dibaca dari kode `GuardianHomeView.swift:178-193` (`.loading` jatuh ke `else` terakhir). Screenshot: [`U-01`](../qa/img/fase-28/U-01_guardian-home-loading-says-protected.jpg).

### P2

**A-02 · Detail menampilkan "Blocked" + dua tombol padahal server menyimpan `safe` terkunci** (`BUG_A02_detailShowsNoVerdictAfterTheServerSaysTheLinkIsLockedSafe`)

```text
H2 A-02 | server verdict: safe | Detail badge: blocked | error: Optional(Shoo.DetailModel.VerdictError.locked)
✘ Test BUG_A02_detailShowsNoVerdictAfterTheServerSaysTheLinkIsLockedSafe() failed after 0.117 seconds with 2 issues.
```

r2: sama. Severity turun P1 → P2 (teks footer sudah benar; buka ulang Detail memperbaikinya).

**U-02 · Pesan gagal simpan setengah tertutup tab bar** (`test025_home_g_verdict_failed`, A dan F)

```text
A/home-g-verdict-failed.json  ('home.verdictError', y 817.3, h 64) ('state.notice.action', 'Coba lagi', y 827.3, h 44) ('bolt.shield.fill', 'Perisai', y 795, h 54)
```

Layar 874 pt; pesan di y 817,3 sampai 881,3, `Bar Tab` mulai y 791 (tombol tab y 795 sampai 849). Pohon: [`h4-tree-A-home-g-verdict-failed.json.txt`](fase-28-repro/h4-tree-A-home-g-verdict-failed.json.txt). r2: dari pohon + [`U-02`](../qa/img/fase-28/U-02_verdict-failed-notice-under-tabbar.jpg); kata diperbaiki menjadi "setengah tertutup".

**U-05 · Baris Activity memotong ekor nama** (`test046_act_g_edge`, `test114_member_edge_long`; A, F, D, E, B)

Tidak ada baris keluaran penentu: sel ditandai dari nama sel. Bukti = kode `ActivityView.swift:525-529` (`.truncationMode(.tail)`) dan [`U-05`](../qa/img/fase-28/U-05_activity-row-tail-truncates-host.jpg). r2: bertahan; `F/member-edge-long` tidak menampilkan barisnya (bukti lemah). Catatan penulis plan: skenario mock `edge` mengisi `domain` dengan host penuh; pemicu di data nyata = label domain terdaftar yang panjang. Belum dicek reviewer. Pohon h4 juga tidak bisa menunjukkan pemotongan: label aksesibilitas baris = judul penuh (`ActivityView.swift:484-486`). Karena itu test merah 28f = unit pemecahan judul + screenshot SE sebelum / sesudah (plan → tabel test, baris 28f).

**U-06 U-08 · Isi onboarding di belakang footer** (`test003_on_ext`, `test008_on_safariDefault`, `test001_on_name`, `test011_consent_question`)

```text
F/on-name.json                ('name.field', y 625.5, h 58) ('name.continue', 'Selanjutnya', y 575.5, h 57.5)
F | consent-question | OVERLAP 'Shoo memeriksa halaman ya' ~ 'Tanpa ini, Shoo hanya mem'
test001_on_name (F): Failed to synthesize event: Neither element nor any descendant has keyboard focus … TextField, {{24.0, 625.5}, {327.0, 58.0}}
```

Bagian yang membuat U-06 P2 (iPhone SE, EN, ukuran default): screenshot [`U-06_se-default-extension-steps-hidden.jpg`](../qa/img/fase-28/U-06_se-default-extension-steps-hidden.jpg) (judul dan baris consent tampil, tiga langkah di belakang footer). r2 (dari [`h4-tree-E-on-ext.json.txt`](fase-28-repro/h4-tree-E-on-ext.json.txt)): langkah di y 453 sampai 606, consent di 464, tombol di 569; setelah gulung langkah terlihat ([`h4-tree-E-on-ext-switchedOff-end.json.txt`](fase-28-repro/h4-tree-E-on-ext-switchedOff-end.json.txt): y 270 sampai 424). Sel itu dihitung "pass" oleh skrip hunter. Bagian AX5 (P3): pohon [`h4-tree-F-on-name.json.txt`](fase-28-repro/h4-tree-F-on-name.json.txt), [`h4-tree-F-consent-question.json.txt`](fase-28-repro/h4-tree-F-consent-question.json.txt), screenshot [`U-06` AX5](../qa/img/fase-28/U-06_se-ax5-onboarding-footer-covers-content.jpg), [`U-08`](../qa/img/fase-28/U-08_se-ax5-consent-buttons-truncated.jpg). `D/on-name` = positif palsu.

**U-17 · Isi tembus di belakang pertanyaan footer Detail** (cek `h4-check.py.txt`, aturan OVERLAP)

```text
E | dt-g-blocked | OVERLAP 'Reasons detected' ~ 'Is this site dangerous?'
A | dt-g-edge-long | OVERLAP 'Sinyal: Formulir sensitif' ~ 'Apakah situs ini berbahay'
```

7 sel di A, E, B. Pohon: [`h4-tree-E-dt-g-blocked.json.txt`](fase-28-repro/h4-tree-E-dt-g-blocked.json.txt) ("Reasons detected" y 540,5 h 25; "Is this site dangerous?" y 541 h 24). r2: bertahan; penyebab di kode `DetailFooter.swift:100,104-112`. Screenshot: [`U-17`](../qa/img/fase-28/U-17_se-detail-heading-shows-through-footer.jpg).

**X-01 · Guardian melihat "connected" setelah akses Safari dipersempit** (`node h3-chain.mjs <worktree>`)

```text
BUG X-01 | 30 h after access was narrowed | backend rule: ext_last_seen_at > now() - 24 h -> extensionActive TRUE (Guardian sees the member as connected) | PATCHes sent while allSites was false: 30 | expected: 0, or a field that says the access is narrowed
```

r3: baris sama. **Batas bukti:** `fetchJSON` di skrip adalah stub yang selalu sukses. Yang terbukti: "tidak ada cek akses di kode". Yang tidak terbukti: "PATCH sampai" di HP dengan akses dipersempit (`rg -i cors backend/api/src`: 0 hasil). Paruh app (`AppEnvironment.swift:315-323`) dari baca kode. Severity P1 → P2.

**OPT-02 · Family Home membaca sampai 10 halaman berurutan** (baca kode + bench rute)

Tanpa test repro. Kode: `GuardianHomeModel.swift:291-305`. Ukuran per halaman ada di §Performa (`GET /scans owner=family`). Test permanen ditulis baru di 28i.

### P3 dengan repro

**B-02 · `recordScan`: status dan push tidak konsisten** (`h1-truth.test.ts.txt` "BUG B-02a", "BUG B-02b")

```text
expected [ 'warning', 75 ] to deeply equal [ 'blocked', 72 ]
H1 B-02b guardian pushes 5 status { status: 'warning', score: 75 }
expected 5 to be 2
```

r1: sama. P2 → P3 (butuh perubahan ambang admin atau klien buatan).

**B-04 A-09 · URL scan disimpan apa adanya** (`h1-identity.test.ts.txt`, `h2-poison.test.ts.txt`)

```text
H1 identity-scan | dot segment (crafted) | https://toko.example/x/../a | expected same | actual other
H1 identity-scan | empty port (crafted) | https://toko.example:/a | expected same | actual other
H1 B-04 | unicode path | stored verdict url https://toko.example/päth | GET 200 null
H1 B-04 | dot segment | stored verdict url https://toko.example/x/../a | GET 200 null
H2 A-03 backend | "https://toko.example\\path" | POST 201 | GET /scans url "https://toko.example\\path" | members.lastScan.url "https://toko.example\\path"
" https://toko.example/a " → POST 500 (PostgresError 23514)
```

r1: `h1-identity` 4 gagal / 32 lulus; `h2-poison` 3 gagal / 1 lulus. Catatan r1: `h2-poison` menegaskan `201` untuk semua sel, jadi itu probe, bukan test perilaku benar. "Gagal di main" untuk file itu tidak berarti apa-apa; harus ditulis ulang di 28j.

**B-06 · `GET /verdicts` dengan URL lebih dari 2.048 karakter → 500** (`h1-extra.test.ts.txt` "BUG B-06")

```text
H1 B-06 {"over":500,"at2048":200,"postScansOver":422}
log: {"route":"/verdicts","error":{"name":"TypeError"}}
```

r1: sama.

**B-07 · Path param anggota dengan NUL → 500** (`h1-extra.test.ts.txt` "BUG B-07")

```text
H1 B-07 | DELETE /family/members/a%00b | 500      (PATCH 500, POST …/remind 500)
log: {"route":"/family/members/:deviceId","error":{"name":"PostgresError","code":"22021"}}
```

r1: 3 × 500 lagi.

**A-03 A-10 · Satu baris yang tidak terbaca menggagalkan seluruh daftar** (`BUG_A03_oneStoredURLBlindsEveryGuardianScreen`, `BUG_A03_oneUnreadableRowHidesTheWholeActivity`)

```text
H2 A-03 screens | Home failed | Family Activity failed | Profile family list failed true | Member detail failed
H2 A-03 | status=reviewing | rows shown 0 of 1 readable | thrown decoding
H2 A-03 | verdict.value=unsure | rows shown 0 of 1 readable | thrown decoding
✘ Test BUG_A03_oneUnreadableRowHidesTheWholeActivity(_:) with 8 test cases failed after 0.342 seconds with 8 issues.
✘ Test cell_urlsTheBackendStoresDecode(_:) with 21 test cases failed after 0.243 seconds with 2 issues.
```

r2: sama, 8 dari 8 racun memberi 0 baris. P2 → P3 (pemicu = request buatan atau backend masa depan).

**A-04 · Hitung mundur kode mengikuti jam HP** (`BUG_A04_codeCountdownFollowsThePhoneClock`)

```text
H2 A-04 | phone clock +0 s | really left 360 s | shown 360 s (6:00) | pass
H2 A-04 | phone clock +600 s | really left 360 s | shown 1800 s (30:00) | FAIL
H2 A-04 | phone clock -600 s | really left 360 s | shown 960 s (16:00) | FAIL
H2 A-04 | phone clock +300 s | really left 360 s | shown 60 s (1:00) | FAIL
```

r2: 7 dari 8 sel berbeda dari 360 s. Desain diputuskan (D-alief-C09, #227): Q4, tanpa langkah kerja.

**A-06 · Home Pribadi bilang "belum terlindungi" sebelum status dibaca** (`BUG_A06_personalHomeClaimsOffBeforeTheFirstRead`)

```text
H2 A-06 | before the first read: isActive false (hero 'You're not protected yet') | has an 'unknown yet' state: false
```

r2: sama. Lama kilatan di layar tidak diukur.

**A-07 · Sheet hapus akun lupa menyebut keluarga** (`BUG_A07_deleteSheetForgetsTheFamilyWhenItsListFailed`)

```text
H2 A-07 | members on server 2 | list failed true | sheet: Everything in this app, including your profile, history and family links, is deleted for good and can't be recovered.
```

r2: baris sama; pemicu dipersempit (daftar keluarga belum pernah termuat di sesi Profile itu).

**A-08 · "active in 0s"** (`BUG_A08_memberLastSeenAheadOfThisPhoneReadsAsTheFuture`)

```text
H2 A-08 | english | heartbeat +3 s | 'active in 0s'
H2 A-08 | indonesian | heartbeat +3 s | 'active dlm 0 dtk'
```

r2: sama; asersi Indonesia yang diperlebar ikut gagal (issue ke-40 dari 40).

**A-14 · Bentuk jamak** (`python3 -I <salinan h2-l10n-audit.py.txt> ios/ShooApp`)

```text
source en keys 650 | missing id 0 | empty id 0 | id == en 10 | placeholder mismatch 0
keys with plural variations 0 | number and no plural rule 11 | extractionState stale 260 | stale but used 181
```

r2 (baris di atas dari jalan ulangnya). "Try again in 1 minutes" tidak bisa tampil (menit dipakai mulai 600 s).

**X-07 · `not_safe` di shared host menjangkau host lain** (`h3-chain.test.ts.txt`, DB `shoo_f28`)

```text
H3 shared | not_safe on https://forms.office.com/r/scam | same link -> not_safe | https://www.office.com/login -> not_safe
```

r3: `accounts.google.com → not_safe`, `www.office.com → not_safe`; 2 dari 6.

**U-09, U-11 · Catatan terpotong di Connect; tombol di bawah keyboard**

```text
A/connect-scan-tab.json       ('connect.copyNote', 773, 46.67) ('connect.skip', 802, 44)
A | sheet-safeReason-kb | … UNDERKB safeReason.submit
```

r2: dari pohon. Screenshot: [`U-09`](../qa/img/fase-28/U-09_connect-scan-note-clipped.jpg), [`U-11`](../qa/img/fase-28/U-11_safe-reason-submit-under-keyboard.jpg).

Ronde 6, angka U-11 dari pohon A: `safeReason.submit` y 557,3 sampai 613,3; `app.keyboards.firstMatch` (tipe 19) mulai y 590; baris saran `SystemInputAssistantView` / `inputView` mulai y 546. Test memakai tepi atas yang lebih kecil dari keduanya, supaya tombol yang berakhir antara y 546 dan 590 (masih tertutup baris saran) tidak lulus. Sel E (SE, EN) **tidak sah**: pohon menunjukkan tombol y 497,5 sampai 553,5 dengan keyboard y 451 (input view y 407), tetapi screenshot-nya tanpa keyboard, karena `dump()` mengambil screenshot sebelum pohon ([`h4-Fase28MatrixUITests.swift.txt`](fase-28-repro/h4-Fase28MatrixUITests.swift.txt) `:68-72`). Skrip cek menandainya (`UNDERKB safeReason.submit`, [`h4-check.py.txt`](fase-28-repro/h4-check.py.txt) `:45-47`), tetapi pembuat matriks memberi U-11 hanya untuk konfigurasi A ([`h4-gen-matrix.py.txt`](fase-28-repro/h4-gen-matrix.py.txt) `:53`) dan tidak membaca hasil cek. SE EN direkam ulang dulu di `main` (plan §28m U-11). B (Pro Max, EN) lulus: tombol berakhir y 594,3, input view mulai y 609.

**U-03 U-04, U-07 · Tata letak di AX5** (P3 di AX5; P2 kalau muncul di AX3)

```text
F | home-g-mixed | OFFX familyModeToggle x=-42 w=50 ; OFFX profileButton x=367 w=52 ; OFFX home.pending x=-50 w=472
F | home-g-three-end | OFFX home.recent.… x=-42 w=460 ; OFFX Penipuan terverifikasi x=62 w=330
F/home-g-figma-end.json       ('bca-verifikasi.site', w 35.5, h 186) ('Bayu · Hari ini, 10.40', w 40, h 208)
F | dt-g-blocked | OVERLAP 'Situs Berbahaya!' ~ 'Apakah situs ini berbahay' ; OVERLAP 'Diakses hari ini · 10.42 ' ~ 'Aman'
```

r2: nyata di AX5 (screenshot cocok); AX3 belum dijalankan. Screenshot: [`U-03`](../qa/img/fase-28/U-03_se-ax5-home-wider-than-screen.jpg), [`U-04`](../qa/img/fase-28/U-04_se-ax5-recent-row-domain-squeezed.jpg), [`U-07`](../qa/img/fase-28/U-07_se-ax5-detail-footer-overlaps.jpg).

**U-10 · Target sentuh** (baris SMALL dari `h4-check.py.txt`, konfigurasi A)

```text
A | act-loadmore-failed | SMALL activity.loadMoreRetry 210x18
A | dt-after-notsafe | SMALL detail.verdictChange 35x18
tap targets: 164 controls, 36 below 44 pt
```

r2: tidak dihitung ulang. Frame aksesibilitas bukan area sentuh: confidence "likely".

**U-13, U-14 · Halaman web** (`h4-pages.test.ts.txt`; HTML dibuka di Chrome headless, iframe 320 px dan 430 px)

```text
 Test Files  1 passed (1)
      Tests  1 passed (1)
```

Test itu hanya me-render dan menyimpan HTML. Buktinya gambar [`U-13`](../qa/img/fase-28/U-13_join-page-320-code-row.png) dan baris kode `terms.ts:36,65`. Tidak di-render ulang r2.

**H5-01, H5-02, H5-03:** lihat §Performa.

### Perlu pertanyaan (repro ada, tanpa langkah kerja)

**B-01 · Push pertama per situs ditahan → tidak ada push lagi (Q1)** (`h1-truth` "BUG B-01"; `h1-extra` "BUG B-01b", "BUG B-01c")

```text
H1 B-01 {"day":null,"other":null,"pushes":0}
expected 0 to be greater than or equal to 1
H1 B-01b {"again":null,"otherPage":null,"pushes":[]}
H1 B-01c pushes []
```

r1: sama. Perilakunya aturan tertulis (`backend/API.md:491-494`). Yang terjangkau klien asli: situs warning saja.

**B-03 · Scan dari HP dengan jam terlalu cepat (Q3)** (`h1-truth` "BUG B-03")

```text
H1 B-03 422 {"error":{"code":"invalid_body","message":"detectedAt: must not be in the future"}}
```

r1: sama. Sel batas: +4 menit 201, +6 menit 422, -400 hari 201.

**A-05 · Heartbeat dari masa depan dihitung Active (Q5)** (`BUG_A05_*`)

```text
H2 A-05 | heartbeat +60 s | active true | expected true | pass
H2 A-05 | heartbeat +301 s | active true | expected false | FAIL
H2 A-05 | heartbeat +31536000 s | active true | expected false | FAIL
```

r2: 5 dari 6 sel Active. Disengaja menurut komentar `ExtensionStatus.swift:70`.

**X-08 · Identitas di platform bersama (Q7a)** (`node h3-chain.mjs`)

```text
BUG X-08 | https://docs.google.com/forms/d/e/1FAIpQLSc/viewform | score 100 blocked | block screen chip: "google.com" | POST /scans domain (Home cards print scan.domain): "google.com" | page really on: docs.google.com
cells 7, named after the platform owner instead of the page: 4
```

r3: 4 dari 7 lagi.

### Milik Umar / Imelda: lapor saja

**X-04 · Island bilang "Aman" saat pill tidak** (`node h3-chain.mjs`)

```text
BUG X-04 | /analyze failed | state score 25 onlineChecked false | pill: "Cek online tidak tersedia" | POST /live body {"domain":"bca-promo.example","score":25,"status":"normal","analyzing":false,"open":true} | island text (ScoreLiveActivity.swift:116-125): "Aman" 25%
BUG X-04 | Guardian marked a 60% link safe (#369) | state score 0 onlineChecked true | pill: "Ditandai aman oleh Gita" | POST /live body {"domain":"bca-promo.example","score":0,"status":"normal","analyzing":false,"open":true} | island text (ScoreLiveActivity.swift:116-125): "Aman" 0%
```

r3: 2 baris lagi. Terbukti sampai body `POST /live`; teks island dari baca kode.

**X-05 · Tingkat warning 2: extension vs island**

```text
BUG X-05 | warnAt 55 blockAt 85 secondWarning 70 | scores where pill/popup and island disagree: 55–69
cells 160, disagreeing 48
```

**X-06 · Keluaran extension yang ditolak backend** (`h3-chain.test.ts.txt`)

```text
H3 scans | http://router/login | sent domain router | POST /scans 422 domain: must be a lowercase registrable domain without www. | GET /verdicts 422
H3 scans | https://www.com/x | sent domain www.com | POST /scans 422 domain: must be a lowercase registrable domain without www. | GET /verdicts 422
H3 scans | rows 15 | refused 6
```

r3: sama. Koreksi: `GET /verdicts` untuk `www.co.id` menjawab 200, bukan 422.

**X-09, X-10 · Jawaban 200 tanpa isi yang terpakai** (`node h3-fail.mjs <worktree>`)

```text
POST /analyze (layer 2 = 14) | 500 | score 14 normal, onlineChecked false, pill "Online check unavailable" | ok
POST /analyze (layer 2 = 14) | 200 {} | score 14 normal, onlineChecked true, pill "Low risk" | FAIL-WRONG
GET /blocklist full refresh (daily) 200 | {} | listed before: true, after: false | FAIL-WRONG (a body that is no list empties layer 1 and counts as fresh for 24 h)
cells run: 84; FAIL-WRONG: 10
```

r3: `cells run: 84; FAIL-WRONG: 10` (7 `/analyze` + 3 `/blocklist`).

**X-11 · Domain terdaftar: perkiraan `ai/` vs PSL** (`node h3-norm.mjs <worktree> backend-shared.txt`)

```text
rows 33, rows with a disagreement 12
PSL multi-label suffixes checked 8637; ai.rdap registrable domain differs from the extension's on 7607
shared hosts compared 99; rows where the three lists disagree 23 (only those are printed)
```

r3: angka terulang, tetapi dibaca ulang. `psl.js` tidak punya penanda bagian, jadi hitungan memuat aturan privat (`jp:1931 com:1083 no:758 it:412 …`). Yang berdiri: 6 suffix `.id`.

**Sudah diketahui, dijalankan lagi:** X-02 (#323) `cells 18, a flagged page that is not blocked: 9`; X-03 (#325) 4 baris BUG, contoh:

```text
BUG X-03 | blocked first: https://s.id/hadiah-bansos | then opens https://s.id/undangan-nikah-rina | blocked 92 (from memory, never scanned: /analyze called false) | backend: s.id subdomains
```

### Ditolak reviewer (repro gagal, tetapi harapannya salah)

**B-05** (`h1-extra` "BUG B-05")

```text
H1 B-05 {"notified":{"name":"Gita"},"push_log":["failed:config"]}
expected { name: 'Gita' } to be null
```

r1: test gagal seperti tertulis, tetapi #377 memutuskan `notified` dari keputusan yang **mengantre** push. Sisa: kata "got" di `contracts/api.md:51` → Q2.

A-11, A-16, PR-C-11: tanpa repro; ditolak dari baca kode dan issue (alasan di plan → "Ditolak reviewer").

### Cek yang lulus dan dicatat sebagai bukti "sudah aman"

```text
security definer without search_path: 0 rows (48 definer functions) · tables without RLS: 0 rows
shoo_api outside public: admin.public_config SELECT, admin.v_domain_lists_public SELECT
anon / authenticated / service_role / PUBLIC grants in public + admin: 0 rows
H1X join-page oracle answers before the IP budget ends: 20
```

Matriks h1 per grup (`cd backend/api && db_guard && VITE_H1_GROUP=<g> npx vitest run test/h1-matrix.test.ts`, satu perintah, satu grup per run):

```text
devices 300 passed · patch 261 passed · scans 324 passed · verdicts 93 passed · family 153 passed
query 3 failed | 273 passed (the three 500s) · auth 191 passed (213 cells)
```

Sel gagal di dalam 1.642: **B-06 1 sel, B-07 3 sel** (5 run: sel B-06 terlihat di dua file, `h1-matrix` dan `h1-extra`). 24 n-a = 429 dari rate limit miniflare. Di luar 1.642: 4 sel identitas URL gagal → **B-04** (`h1-identity`, matriks §3.4). Rincian per sel: matriks §3.3.

Run matriks UI per konfigurasi (h4):

```bash
TEST_RUNNER_F28_DIR=<scratch>/shots TEST_RUNNER_F28_TAG=<A|F|D|E|B> TEST_RUNNER_F28_LANG=<id|en> \
TEST_RUNNER_F28_SIZE=<''|UICTContentSizeCategoryAccessibilityXXXL> TEST_RUNNER_F28_THEME=<light|dark> TEST_RUNNER_F28_EXTRA=<''|bold,contrast> \
xcodebuild test-without-building -xctestrun <scratch>/dd/Build/Products/Shoo_iphonesimulator27.1-arm64.xctestrun \
  -destination id=<simulator sesi ini> -parallel-testing-enabled NO -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  -only-testing:ShooAppUITests/Fase28MatrixUITests[/<method>]
python3 -I h4-check.py <scratch>/shots ios/ShooApp/Resources/Localizable.xcstrings <tag>     # chk-<tag>.txt
python3 -I gen.py x                                                                          # matrix.json, total, baris
```

| Tag | Simulator | Baris hasil |
|---|---|---|
| A | Shoo F28 | `Executed 141 tests, with 0 failures (0 unexpected) in 2593.622 (2593.919) seconds` + satu putaran sebagian sebelumnya; 146 method berbeda lulus, `test005` tanpa hasil |
| F | Shoo F28 SE | 147 method: 144 lulus, 3 gagal (`test001_on_name`, `test002_on_name_rtl`, `test082_dt_safe_reason`: `Failed to synthesize event: Neither element nor any descendant has keyboard focus`) |
| D | Shoo F28 | `Executed 52 tests, with 1 failure (0 unexpected) in 727.964 (728.015) seconds` (`test082_dt_safe_reason`) |
| E | Shoo F28 SE | `Executed 52 tests, with 0 failures (0 unexpected) in 628.945 (629.005) seconds` |
| B | Shoo F28 Max | berhenti di 40 dari 52: 38 lulus; `test059_act_refresh_failed` (`Timed out while synthesizing event`, 385 s) dan `test071_dt_g_safe` (`Application … does not have a process ID`, 1.531 s) gagal karena infrastruktur |

Keluaran skrip pembuat matriks, lalu hitung ulang r2 dari `matrix.json` (640 key) dan file di `shots/`:

```text
gen.py: | **Total app** | 1020 | 611 | 469 | 142 | 27 | 382 |
gen.py: {'U-05': 15, 'U-09': 1, 'U-17': 7, 'U-01': 2, 'U-02': 2, 'U-11': 1, 'U-12': 33, 'U-08': 1, 'U-07': 40, 'U-04': 19, 'U-03': 8, 'U-06': 17}
```

| | Hunter | Hitung ulang r2 |
|---|---|---|
| Sel berbeda × 5 konfigurasi | 1.020 | **1.025** (205 sel berbeda) |
| Dijalankan | 611 | **613** (A 194, F 191, D 82, E 83, B 63) |
| Lulus | 469 | **470** |
| Gagal | 142 | **143** |
| Tidak valid | 27 | 27 |
| Tidak dijalankan | 382 | **385** |
| Dengan web (32 / 26 / 6, tidak dicek ulang) | 643 / 495 / 148 | **645 / 496 / 149** |

Penyebab selisih: `gen.py` mengelompokkan Home Pribadi dengan `^home-pb-`. Sel `home-pb` tanpa tanda hubung jatuh ke "Other" dan tidak tercetak (`A|home-pb` pass, `F|home-pb` fail U-04).

## Performa

Skrip: [`h5-seed.sql.txt`](fase-28-repro/h5-seed.sql.txt), [`h5-explain.sql.txt`](fase-28-repro/h5-explain.sql.txt), [`h5-explain-summary.out.txt`](fase-28-repro/h5-explain-summary.out.txt), [`h5-proto.sql.txt`](fase-28-repro/h5-proto.sql.txt), [`h5-route-bench.test.ts.txt`](fase-28-repro/h5-route-bench.test.ts.txt), [`h5-route-bench.out.txt`](fase-28-repro/h5-route-bench.out.txt), [`h5-detector-bench.mjs.txt`](fase-28-repro/h5-detector-bench.mjs.txt). Plan EXPLAIN lengkap (2,4 MB per run) tidak disimpan di repo; ringkasannya ada di `h5-explain-summary.out.txt`.

### Seed

```bash
docker exec -i supabase_db_shoo_hunt psql -U postgres -d shoo_f28_perf -X -v ON_ERROR_STOP=1 < h5-seed.sql   # 6:53 total
```

```text
INSERT 0 320000   Time: 320011.921 ms      (scans, trigger menyala)
      relname       | n_live_tup |  total  |    heap    |   idx
 scans              |     320000 | 683 MB  | 500 MB     | 183 MB
 scan_archive       |     320000 | 345 MB  | 215 MB     | 130 MB
 rate_limit_hits    |     346076 | 83 MB   | 32 MB      | 52 MB
 domain_intel       |      19985 | 77 MB   | 74 MB      | 3696 kB
 push_log           |      94978 | 32 MB   | 12 MB      | 20 MB
 db_size  1260 MB
```

| Isi seed | Jumlah |
|---|---|
| Device | 6.000 (2.000 Guardian keluarga, 3.000 anggota terhubung, 500 Guardian sendiri, 500 Protected tanpa link) |
| Link keluarga | 3.000 (keluarga tetap 2 anggota) |
| Scan | 320.000 (300.000 dalam 14 hari + 20.000 lebih tua untuk retensi), 4 sinyal per scan |
| Verdict | 9.472 |
| `push_log` / `rate_limit_hits` / tombstone / blocklist | 94.978 / 346.076 / 39.142 / 3.600 |
| Kemiringan | owner terberat 908 scan, median 45; keluarga terberat 986 scan dan 40 verdict di satu anggota; keluarga median 139 scan |

Statement dijalankan sebagai role `shoo_api` (RLS menyala, `statement_timeout` 10 s, `20261022120000_hardening.sql:5`), parameter literal, dua run; angka dari run kedua (hangat).

**Koreksi r1 atas ukuran (H5-01):** dibaca ulang 1.258 MB. Sekitar 150 MB adalah artefak seed: `domain_intel` 77 MB (satu transaksi tanpa vacuum) dan `rate_limit_hits` 83 MB (170 ribu baris per hari per bucket, padahal 320 ribu scan dalam 14 hari memberi sekitar 23 ribu per hari). Hasil: **≈ 3,3 KB per scan hidup, 500 MB di sekitar 150 ribu scan**. Angka hunter (3,9 KB, 128 ribu) dibuang. `backend/README.md:229-230` menulis ≈ 1,5 KB dan 300 ribu: ≈ 2× terlalu tinggi.

### EXPLAIN (ANALYZE, BUFFERS): sebelum

```bash
./pa.sh < h5-explain.sql > h5-explain.out        # pa.sh = psql sebagai shoo_api ke shoo_f28_perf
```

**S18 · `listScans owner=family`, keluarga terberat, halaman pertama (limit 21)** → OPT-01

```text
 Limit (actual time=1426.579..1426.583 rows=21 loops=1)
   Buffers: shared hit=5407 read=940 written=9
   ->  Sort (actual time=1426.579..1426.582 rows=21 loops=1)
         Sort Method: top-N heapsort  Memory: 97kB
         ->  Nested Loop Left Join (actual time=2.895..1426.217 rows=986 loops=1)
                     ->  Bitmap Heap Scan on scans s (actual time=0.123..5.519 rows=986 loops=1)
                           ->  Seq Scan on devices d (actual time=0.005..0.714 rows=6000 loops=1)
               ->  Limit (actual time=1.438..1.438 rows=0 loops=986)
                           ->  Index Scan using verdicts_pkey on verdicts v (actual time=1.366..1.437 rows=0 loops=986)
 Execution Time: 1426.820 ms
```

Bentuk plan: semua 986 baris keluarga diambil (Bitmap Heap Scan), lookup verdict lateral dijalankan 986 kali (1,44 ms sekali), baru top-N sort. `Seq Scan` pada `devices` (6.000 baris). Biaya = scan × verdict owner × ≈ 40 µs (`verdict_link`: 10.000 panggilan = 405 ms, P6).

**N04 · klaim ringkasan mingguan, 40 Guardian** → H5-02, OPT-03

```text
 Update on devices d (actual time=154.102..6100.498 rows=40 loops=1)
   Buffers: shared hit=275039 read=4846155 dirtied=45 written=32
   SubPlan 2
     ->  Aggregate (actual time=75.570..75.570 rows=1 loops=40)
           ->  Seq Scan on scans s (actual time=4.821..75.559 rows=21 loops=40)
                 Filter: ((detected_at > (now() - '7 days'::interval)) AND (status = 'blocked'::scan_status) AND ((owner_id = d.id) OR (ANY (owner_id = (hashed SubPlan 1).col1))))
                 Rows Removed by Filter: 319979
   SubPlan 4
     ->  Aggregate (actual time=76.882..76.882 rows=1 loops=40)
           ->  Seq Scan on scans s_1 (actual time=2.507..76.870 rows=50 loops=40)
                 Rows Removed by Filter: 319950
 Execution Time: 6100.631 ms
```

Bentuk plan: 80 `Seq Scan` pada `scans` (2 per Guardian), 4,85 juta buffer dibaca. Batas role 10.000 ms.

Ringkasan statement lain (dari `h5-explain-summary.out.txt`):

```text
S17 listScans owner=me, heavy owner, first page (limit 21) | exec_ms=43.188 | seq_scans=-
S17b listScans owner=me, median owner, first page (limit 21) | exec_ms=0.154 | seq_scans=-
S19 listScans owner=family, page 10 (keyset cursor after 180 rows) | exec_ms=1116.853 | seq_scans=devices
S20 listScans owner=family, status=blocked filter, first page | exec_ms=406.031 | seq_scans=devices
S21 listScans owner=me heavy, limit=50 (max page, limit 51) | exec_ms=108.104 | seq_scans=-
S01 auth findByTokenHash (http/auth.ts, every authenticated request) | exec_ms=0.014 | seq_scans=-
S27 findVerdict (GET /verdicts?url=&domain=, polled every 2-15 s by an open block/warning page) | exec_ms=0.015 | seq_scans=-
N01 notifications: clear off marks (hourly) | exec_ms=5.524 | seq_scans=devices,family_links
```

### Prototipe

```bash
./pa.sh < h5-proto.sql > h5-proto.out
```

| ID | Isi | Hunter | Ulang r1 |
|---|---|---|---|
| P1 | Daftar keluarga, halaman scan dipilih dulu (limit di dalam), link dihitung sekali per baris | 5,332 ms | - |
| P2 | P1 + top-N per owner dari `scans_owner_time` | 1,419 ms | **1,335 ms** |
| P3 | Owner tunggal terberat, limit 51 | 2,849 ms | - |
| P4 | Hitungan ringkasan mingguan 40 Guardian, owner sebagai daftar | 44,136 ms | **51,866 ms** |
| P5 | Chunk retensi `rate_limit_hits` lewat indeks `hit_at` | 216,219 ms (lebih lambat dari sekarang 55,7 ms: tidak diusulkan) | - |
| P6 | Biaya `verdict_link` saja, 10.000 panggilan | 405,276 ms | - |

Jalan ulang r1 (`pa.sh < r1-perf.sql`, SELECT / EXPLAIN saja):

```text
R-S18 heavy family   Execution Time: 1894.575 ms
R-S18 p90 family     Execution Time: 24.428 ms
R-P2 proto           Execution Time: 1.335 ms       md5 orig = md5 proto; 1013 rows, differ 0
R-N04                Execution Time: 6791.435 ms    Seq Scan on scans (loops=40) ×2
R-P4 proto           Execution Time: 51.866 ms
N04 vs P4 as one statement under shoo_api: "canceling statement due to statement timeout" (6.8 s + rest > 10 s)
guardians 40, differ 0, blocked 854, warnings 1993
```

Yang dicek r1 untuk kesetaraan: halaman pertama 21 baris, md5 atas baris berurutan identik; kolom verdict identik di 1.013 baris keluarga itu (93 baris dengan verdict, selisih 0); hitungan ringkasan 40 Guardian selisih 0. **Belum dicek siapa pun:** halaman bercursor dan filter `status` lewat bentuk top-N per owner.

Koreksi r1 atas pembacaan: keluarga terberat adalah 1 % teratas seed (scan anggota per keluarga p50 91, p90 104, p99 885, maks 968). Keluarga p90 (140 scan, 6 verdict) memakan 24 ms. Timeout N04 **mungkin**, tidak terbukti: di Supabase Free DB sudah penuh di sekitar 150 ribu scan, tempat statement ini ≈ 3 s di Mac ini.

### Bench rute (Worker asli di workerd, DB volume)

Hunter saja; **tidak dijalankan ulang r1** karena menulis ke DB performa. Jumlah statement dari `pg_stat_statements` untuk role `shoo_api`. Waktu dinding lokal (tanpa jaringan, tanpa Hyperdrive).

```text
route | n | status | statements/req | SQL ms/req | WAL bytes/req | wall p50 ms | wall max ms | response bytes
GET /devices/me (guardian) | 15 | 200 | 2 | 0.06 | 0 | 5 | 9 | 404
GET /family/members | 15 | 200 | 2 | 0.15 | 0 | 8 | 10 | 877
GET /scans owner=me, heaviest owner | 10 | 200 | 3 | 43.44 | 0 | 52 | 68 | 28334
GET /scans owner=me limit=50, heaviest owner | 6 | 200 | 3 | 109.48 | 0 | 117 | 141 | 70392
GET /scans owner=family, median family | 10 | 200 | 4 | 9.77 | 0 | 19 | 23 | 27722
GET /scans owner=family, heaviest family, page 1 | 5 | 200 | 4 | 1396.38 | 0 | 1393 | 1479 | 28752
GET /scans owner=<member>, heaviest family | 5 | 200 | 4 | 34.05 | 0 | 44 | 44 | 28727
GET /verdicts?url=&domain= (poll) | 15 | 200 | 2 | 0.04 | 0 | 6 | 9 | 16
POST /scans new link, protected member (no replica) | 15 | 201 | 13 | 2.41 | 26293 | 13 | 20 | 61
POST /scans new link + page replica + evidence fragments | 10 | 201 | 29 | 3.61 | 35045 | 24 | 26 | 61
POST /verdicts not_safe on a member scan | 10 | 200 | 18.1 | 5.18 | 68557 | 28 | 32 | 178
 ✓ test/zz-h5-perf.test.ts > h5 route bench on shoo_f28_perf 21382ms
```

Tabel lengkap 21 rute: [`h5-route-bench.out.txt`](fase-28-repro/h5-route-bench.out.txt).

### Ukuran bundle Worker (H5-03, OPT-05)

```text
$ node backend/ci/bundle-size.mjs
index.js 317017 B (limit 295000), gzip 103739 B (limit 97500)
  zod                          370313 B source
  (app)                        347744 B source
  postgres                     77717 B source
  hono                         64706 B source
FAIL: bundle over the limit
```

r1: sama. `grep -n bundle .github/workflows/*.yml`: tidak ada step ukuran bundle. Sumber app tumbuh dari 230.755 B (1 Nov, `log/fase-22.md:18`) ke 347.744 B.

### Ukuran lain yang dirujuk plan (O-01 sampai O-25, ringkas)

Laporan hunter 5 tidak ada di repo. Baris yang belum muncul di atas:

| ID | Yang diukur | Angka |
|---|---|---|
| O-04 | Satu panggilan `public.verdict_link()` | 40,5 µs |
| O-09 | `POST /scans` kunjungan ulang link yang dikenal | 13 statement, 1,41 ms SQL, 5.398 B WAL |
| O-11 | Trigger `admin.on_scan_insert` | 1,42 ms dari insert 3,44 ms (domain dikenal); 0,43 dari 0,56 ms (domain baru); 320.000 insert dalam 320 s |
| O-12 | Amplifikasi tulis per scan baru | 6 indeks di `scans` + 1 upsert `domain_intel` + 1 baris `scan_archive` dengan 8 indeks (2 GIN) + 1 update `devices` |
| O-14 | `DELETE /devices/me`, owner terberat (908 scan) | 69 ms total |
| O-15 | Retensi per chunk 2.000 scan | 36 sampai 45 ms, kunci baris saja, 0 AccessExclusive |
| O-16 | Langkah lain cron per jam | hapus tanda off 5,5 ms (trigger `family_links_check` 265 kali, 3,75 ms); kandidat protection-off 22,2 ms |
| O-18 | Payload daftar | 20 item = 27,7 sampai 28,8 KB; limit 50 = 70.392 B; Family Home sampai ≈ 280 KB per refresh |
| O-19 | Permintaan app per foreground (hitung dari kode) | Guardian Family: 5 sampai 14, 2 di antaranya `GET /devices/me` yang sama; Protected: 4 sampai 13 |
| O-20 | Permintaan app per layar (hitung dari kode) | Activity 2 sampai 3; Detail 2 sampai 3 (+ sampai 2 lagi saat scan baru belum punya salinan); Profile 2; kartu Family shield 1 + sampai 3 |
| O-21 | Timer polling app | `GET /family/members` tiap 5 s selama kartu undangan terbuka; tanpa timer di Home, Activity, Detail |
| O-22 | Aset app | 48 file, 10.098.580 B; terbesar `ConnectedBackground@2x.jpg` 2.297.706 B → 657.475 B pada JPEG q80 (`sips`, diukur dua kali: hunter dan r1) |
| O-23 | Extension per halaman | 15 content script, 192.673 B sumber, 57.001 B gzip; 1 `POST /analyze` per halaman + sampai 6 cek ulang |
| O-24 | Detektor layer 1 dan 2 di Node (`node h5-detector-bench.mjs <repo>`) | `analyzeLocal` p50 0,08 sampai 0,37 ms, p95 ≤ 0,65 ms, maks 2,0 ms; kompilasi p50 1,8 ms |
| O-25 | Panggilan latar extension (konstanta) | PATCH last-seen ≤ 1 per 60 menit; poll verdict halaman blokir 156 permintaan di 10 menit pertama, lalu 240 per jam |

Yang tidak diukur (CPU Worker di Cloudflare, Hyperdrive, permintaan per HP per hari, rebutan baris panas, waktu launch, frame rate, biaya extension di Safari iPhone): daftar di plan → "Batas audit".

## Query pemakaian (kategori 9, UQ-01 sampai UQ-13)

**Status semua 13 query: belum dijalankan di produksi; hanya parse-check di DB lokal.** Hunter 6 menjalankannya sekali di `shoo_f28` untuk mengecek parse dan nama kolom; r3 menjalankan `explain` untuk masing-masing di `shoo_f28_perf` (13 OK). Teks di bawah di-parse ulang 14 Nov dengan `EXPLAIN` di `shoo_f28_perf`: 14 statement OK (13 UQ + `stats_reset`); UQ-05 dan UQ-06 dengan `count(distinct …)` dicek reviewer plan ronde 2. Angka dari seed test tidak berarti dan tidak dicatat.

- Semua query **hitungan saja**. Tidak ada yang mengembalikan id, nama, URL, atau baris. UQ-11 mengembalikan nama indeks (skema, bukan data pengguna).
- `scans`, `push_log`, dan `join_attempts` menyimpan 14 hari / 1 hari, jadi tiap jawaban adalah jendela, bukan total.
- **Kelompok minimum (aturan r3):** kelompok dengan kurang dari 5 device tidak dicetak (`having`); laporan menulis "kelompok < 5 disembunyikan". UQ-01, UQ-02, UQ-12: `having count(*) >= 5` (satu baris = satu device atau satu Guardian). UQ-05, UQ-06: `having count(distinct …device_id) >= 5`, karena di sana satu baris = satu push atau satu device-hari, dan satu device bisa mengisi kelompok sendiri (review plan ronde 2). Di-parse ulang 14 Nov dengan `EXPLAIN` di `shoo_f28_perf`: 14 statement OK. Query tanpa `group by` mengembalikan satu baris total: angka di bawah 5 ditulis "< 5" saat dilaporkan. Kolom terakhir tabel di bawah menyebut query mana yang diminta r3.
- Dijalankan hanya setelah Alief setuju (plan → LANGKAH MANUAL). Hasilnya ditulis di file ini, hitungan saja.

| Query | Menjawab | Status | Kelompok minimum |
|---|---|---|---|
| UQ-01 | Jumlah device per peran (Q29, sebagian PR-C-02) | belum dijalankan di produksi; hanya parse-check di DB lokal | ya: peran dengan kurang dari 5 device tidak dicetak (`having`); laporan menulis "kelompok < 5 disembunyikan" |
| UQ-02 | Ukuran keluarga. **Hanya sebagian menjawab PR-C-02**: yang dibutuhkan adalah distribusi jumlah scan keluarga per Guardian dalam 14 hari (query itu belum ditulis) | belum dijalankan di produksi; hanya parse-check di DB lokal | ya: ukuran keluarga dengan kurang dari 5 Guardian tidak dicetak (`having`); laporan menulis "kelompok < 5 disembunyikan" |
| UQ-03 | Saklar notifikasi yang berbeda dari default (PR-C-06) | belum dijalankan di produksi; hanya parse-check di DB lokal | ya: satu baris total tanpa `group by`; nilai 1 sampai 4 (mis. `weekly_summary_on`) ditulis "< 5" saat dilaporkan |
| UQ-04 | "Kabari saya" mati per anggota; "Ingatkan" pernah dipakai | belum dijalankan di produksi; hanya parse-check di DB lokal | tidak diminta |
| UQ-05 | Push 14 hari: milik sendiri vs ke Guardian, per kelas hasil (PR-C-07) | belum dijalankan di produksi; hanya parse-check di DB lokal | ya: kelas hasil dari kurang dari 5 device penerima tidak dicetak (`having count(distinct …)`); laporan menulis "kelompok < 5 disembunyikan" |
| UQ-06 | **Label dikoreksi r3:** push per **device** per hari (push milik sendiri dan HP Protected ikut terhitung), **bukan** per Guardian. Untuk per Guardian: join `family_links` pada `guardian_id`, atau pakai `kind = 'guardian'` dari UQ-05 | belum dijalankan di produksi; hanya parse-check di DB lokal | ya: bucket dari kurang dari 5 device tidak dicetak (`having count(distinct …)`); laporan menulis "kelompok < 5 disembunyikan" |
| UQ-07 | Apakah Guardian bertindak. Batas: hanya menghitung scan blocked (warning juga bisa diputuskan sejak #241) | belum dijalankan di produksi; hanya parse-check di DB lokal | tidak diminta |
| UQ-08 | Gesekan pairing: percobaan join dan yang berhasil | belum dijalankan di produksi; hanya parse-check di DB lokal | tidak diminta |
| UQ-09 | Kode dibuat vs link dibuat di hari yang sama | belum dijalankan di produksi; hanya parse-check di DB lokal | tidak diminta |
| UQ-10 | HP Protected yang extension-nya diam. Batas: kurang hitung HP dengan akses dipersempit (X-01) | belum dijalankan di produksi; hanya parse-check di DB lokal | tidak diminta |
| UQ-11 | Indeks tanpa pembaca sejak reset statistik terakhir (PR-R-05, OPT-09). **Tambah** query `stats_reset` di bawah: `idx_scan = 0` tidak berarti apa-apa tepat setelah reset | belum dijalankan di produksi; hanya parse-check di DB lokal | bukan data pengguna |
| UQ-12 | Bahasa, dan device tanpa `device_model` | belum dijalankan di produksi; hanya parse-check di DB lokal | ya: bahasa dengan kurang dari 5 device tidak dicetak (`having`); laporan menulis "kelompok < 5 disembunyikan" |
| UQ-13 | Arsip: baris lewat 14 hari, dan baris yang sudah di-strip (PR-C-13) | belum dijalankan di produksi; hanya parse-check di DB lokal | tidak diminta |

Teks query (dari hunter 6; komentar UQ-06 diubah sesuai r3; `having` ditambahkan ke setiap query berkelompok, untuk UQ-05 dan UQ-06 dengan `count(distinct …)`):

```sql
-- UQ-01 roles: how many devices per role (Pribadi = guardian with no member)
select case when d.mode = 'protected' and l.protected_id is not null then 'protected_paired'
            when d.mode = 'protected' then 'protected_unpaired'
            when exists (select 1 from family_links g where g.guardian_id = d.id) then 'guardian_with_members'
            else 'pribadi' end as role, count(*) as devices
from devices d left join family_links l on l.protected_id = d.id group by 1 having count(*) >= 5 order by 1;
-- UQ-02 family size
select members, count(*) as guardians from (select guardian_id, count(*) as members from family_links group by 1) f group by 1 having count(*) >= 5 order by 1;
-- UQ-03 notification switches away from the default
select count(*) as devices,
       count(*) filter (where not notify_blocked) as blocked_off,
       count(*) filter (where not notify_warning) as warning_off,
       count(*) filter (where not notify_family) as family_off,
       count(*) filter (where not notify_protection_off) as protection_off_off,
       count(*) filter (where weekly_summary) as weekly_summary_on,
       count(*) filter (where not quiet_hours) as quiet_hours_off,
       count(*) filter (where quiet_hours and (quiet_start <> 1320 or quiet_end <> 360)) as quiet_window_changed,
       count(*) filter (where apns_token is null) as no_push_token
from devices;
-- UQ-04 per-member "Kabari saya" off, and "Ingatkan" ever used
select count(*) as links, count(*) filter (where not notify) as notify_off,
       count(*) filter (where reminded_at is not null) as reminded_once_or_more from family_links;
-- UQ-05 pushes of the last 14 days: to the scan's owner (own push) or to someone else (guardian push), by result class
select case when s.owner_id = p.to_device_id then 'own' when p.scan_id is null then 'no_scan' else 'guardian' end as kind,
       split_part(p.result, ':', 1) as result, count(*) as pushes
from push_log p left join scans s on s.id = p.scan_id group by 1, 2 having count(distinct p.to_device_id) >= 5 order by 1, 2;
-- UQ-06 pushes per DEVICE per day (own pushes and Protected phones included; NOT per guardian): distribution
select width_bucket(n, 0, 10, 5) as bucket_of_2, count(*) as device_days
from (select to_device_id, date_trunc('day', created_at) as day, count(*) as n from push_log group by 1, 2) x group by 1 having count(distinct to_device_id) >= 5 order by 1;
-- UQ-07 does the Guardian act? blocked scans of paired members in the last 14 days, with / without a verdict
select count(*) as blocked_scans, count(v.scan_id) as with_verdict,
       count(*) filter (where v.decided_at - s.detected_at <= interval '1 hour') as within_1h
from scans s join family_links l on l.protected_id = s.owner_id
left join verdicts v on v.scan_id = s.id where s.status = 'blocked';
-- UQ-08 pairing friction: join attempts and how many succeed (rows live 1 day)
select count(*) as attempts, count(*) filter (where success) as succeeded,
       count(distinct device_id) as devices_trying from join_attempts;
-- UQ-09 codes made vs links made on the same day (codes live 1 day)
select (select count(*) from family_codes) as codes_alive,
       (select count(*) from family_links where created_at > now() - interval '1 day') as links_last_day;
-- UQ-10 protected phones whose extension is silent (Guardian sees "off")
select count(*) as paired_protected,
       count(*) filter (where d.ext_last_seen_at is null) as never_reported,
       count(*) filter (where d.ext_last_seen_at < now() - interval '1 day') as silent_over_1_day
from devices d join family_links l on l.protected_id = d.id;
-- UQ-11 indexes no statement used since the last stats reset
select indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) as size
from pg_stat_user_indexes where schemaname = 'public' and idx_scan = 0 order by pg_relation_size(indexrelid) desc;
-- UQ-11 tambahan r3: kapan statistik terakhir di-reset
select stats_reset from pg_stat_database where datname = current_database();
-- UQ-12 language and "members' phones" facts the Guardian screen shows
select language, count(*) as devices, count(*) filter (where device_model is null) as no_model from devices group by 1 having count(*) >= 5;
-- UQ-13 archive: rows kept past the 14 days, and rows already stripped (account deleted)
select count(*) as archive_rows, count(*) filter (where created_at < now() - interval '14 days') as older_than_14d,
       count(*) filter (where stripped_at is not null) as stripped from admin.scan_archive;
```

Tiga perubahan terhadap teks hunter: komentar dan alias kolom UQ-06 (`guardian_days` → `device_days`, mengikuti koreksi label r3), baris `stats_reset` tambahan untuk UQ-11, dan `having` di query berkelompok (`count(*) >= 5` di UQ-01, UQ-02, UQ-12; `count(distinct …device_id) >= 5` di UQ-05, UQ-06). Di-parse dengan `EXPLAIN` di `shoo_f28_perf` (lokal, baca saja): 14 statement OK. Tidak dijalankan di produksi.

Butir mana butuh query mana: PR-A-01 semua · PR-C-02 UQ-01, UQ-02 · PR-C-06 UQ-03 · PR-C-07 UQ-05, UQ-06 · PR-C-13 UQ-13 · PR-R-05 UQ-11 · Q29 UQ-01, UQ-10. Saklar Tema / Aksesibilitas (Q20) tidak bisa dijawab SQL: disimpan di `UserDefaults` HP dan app tidak punya analytics. PR-C-12 butuh hitungan permintaan shoo-ai, bukan DB ini.

Cek tambahan r3 untuk PR-R-05 (lokal): statement batas antrean 24 jam (`verdicts.ts:78-81`) memilih `Index Scan using verdicts_eligible_domain`, bukan `verdicts_not_safe`.

Angka yang belum disepakati dua laporan: key katalog yang tidak dipakai dan tidak `stale` = "sekitar 22" (hunter 2) vs 20 dari 81 (hunter 6). r3 membuktikan 81 dari 81 tidak dipakai (`python3 -I l10n_check.py`: `keys parsed 81, in catalog 81, keys with any hit 11 (0 real uses)`) tetapi tidak menghitung ulang pembagian itu.

## Indeks file repro (`fase-28-repro/`)

49 file: 25 skrip / test / keluaran dan 24 pohon aksesibilitas `h4-tree-*.json.txt`. Semua `.txt` karena folder `plan/` hanya dokumen; jangan commit salinannya ke `backend/api/test/` atau `ios/ShooApp/Tests/` di branch docs. Kolom terakhir mengikuti plan → "Test repro → test permanen".

| File | Membuktikan | Menjadi test permanen di (sub-fase) |
|---|---|---|
| [`h1-truth.test.ts.txt`](fase-28-repro/h1-truth.test.ts.txt) | B-02 ("BUG B-02a", "BUG B-02b"); B-01, B-03 (pertanyaan); kebenaran rute baca | B-02 → `backend/api/test/scans.test.ts`, `test/push-notify.test.ts` (28l). B-01 dan B-03 tidak dipindah: menunggu Q1, Q3 |
| [`h1-extra.test.ts.txt`](fase-28-repro/h1-extra.test.ts.txt) | B-06, B-07; B-01b, B-01c (pertanyaan); B-05 (ditolak) | B-06 → `test/verdicts.test.ts`, B-07 → `test/family.test.ts` (28m). Sisanya tidak dipindah |
| [`h1-identity.test.ts.txt`](fase-28-repro/h1-identity.test.ts.txt) | B-04 (dot segment, empty port, unicode path) | `test/scans.test.ts`, `test/verdicts.test.ts` (28j) |
| [`h1-matrix.test.ts.txt`](fase-28-repro/h1-matrix.test.ts.txt) | 1.642 sel API; sel gagal B-06, B-07 | Tidak dipindah (matriks, bukan test perilaku). Tidak dijalankan ulang reviewer |
| [`h1-concurrency.test.ts.txt`](fase-28-repro/h1-concurrency.test.ts.txt) | Empat balapan lulus ("sudah aman") | Tidak dipindah. Tidak dijalankan ulang reviewer |
| [`h2-H2TruthTests.swift.txt`](fase-28-repro/h2-H2TruthTests.swift.txt) | A-01, A-02, A-03, A-04, A-05, A-06, A-07, A-08, A-10; 160 sel logika | `BUG_A01_guardian…` + sel `guardianHome.*` → `ios/ShooApp/Tests/GuardianHomeModelTests.swift` (28a) · `BUG_A06_…` → `GuardianHomeModelTests.swift` (28a) · `BUG_A01_protected…` + sel `protectedHome` → `Tests/ShieldModelTests.swift` (28b) · `BUG_A02_…` → `Tests/DetailModelTests.swift` (28c) · `BUG_A08_…` → `Tests/FormatterTests.swift` atau `Tests/ProfileModelTests.swift`, `BUG_A03_oneStoredURL…` bagian teks → `Tests/APIClientTests.swift` (28m). Tidak dipindah: `BUG_A04_*`, `BUG_A05_*`, `BUG_A07_*`, `BUG_A03_oneUnreadableRow…` (menunggu Q4, Q5, Q17, Q11) |
| [`h2-poison.test.ts.txt`](fase-28-repro/h2-poison.test.ts.txt) | Paruh backend A-03, A-09 (probe: menegaskan 201 untuk semua sel) | **Ditulis ulang** → `backend/api/test/scans.test.ts`, `test/verdicts.test.ts` (28j) |
| [`h2-l10n-audit.py.txt`](fase-28-repro/h2-l10n-audit.py.txt) | A-14; katalog 650 key bersih | `Tests/LocalizationTests.swift` (28m) |
| [`h3-chain.mjs.txt`](fase-28-repro/h3-chain.mjs.txt) | X-01, X-02, X-03, X-04, X-05, X-08 | X-01 paruh app → test **baru** di `Tests/AppEnvironmentSessionTests.swift` (28d). Sisanya milik Umar / sudah diketahui: tidak dipindah |
| [`h3-chain.test.ts.txt`](fase-28-repro/h3-chain.test.ts.txt) | X-06, X-07 | Tidak dipindah: menunggu Q7a (X-07) dan Q7b (X-06) |
| [`h3-fail.mjs.txt`](fase-28-repro/h3-fail.mjs.txt) | X-09, X-10; 84 sel jaringan | Tidak dipindah (milik Umar; lapor saja) |
| [`h3-norm.mjs.txt`](fase-28-repro/h3-norm.mjs.txt) | X-11; 33 baris normalisasi; hitungan X-03 | Tidak dipindah (milik Imelda / Umar) |
| [`h3-gen-backend-cases.mjs.txt`](fase-28-repro/h3-gen-backend-cases.mjs.txt) | Pembuat 15 kasus untuk `h3-chain.test.ts` | Tidak dipindah (alat bantu) |
| [`h4-Fase28MatrixUITests.swift.txt`](fase-28-repro/h4-Fase28MatrixUITests.swift.txt) | U-01 sampai U-12, U-17, U-18; 1.025 sel UI (merekam, tidak menegaskan) | `test022_home_g_loading` → `ios/ShooApp/UITests/GuardianUITests.swift` (28a; ID, ukuran default, iPhone 17 + SE) · `test025_home_g_verdict_failed` → `UITests/QALayoutUITests.swift` (28e; merah iPhone 17 ID ukuran default, penjaga SE EN ukuran default) · `test046_act_g_edge`, `test114_member_edge_long` → tidak dipindah sebagai UITest (label aksesibilitas = judul penuh, `ActivityView.swift:484-486`); dasar skenario mock domain terdaftar panjang untuk screenshot SE 28f; test merah 28f = unit `ActivityRow.titleParts` di `ios/ShooApp/Tests/ActivityModelTests.swift` · `test003_on_ext`, `test008_on_safariDefault` → `UITests/QALayoutUITests.swift` (28h; merah SE EN ukuran default, penjaga iPhone 17 ID ukuran default) · `test011_consent_question`, `test001_on_name` → ukur ulang di AX3 (28n); jadi test permanen hanya kalau rusak di AX3 |
| [`h4-check.py.txt`](fase-28-repro/h4-check.py.txt) | Baris OVERLAP / OFFX / UNDERKB / SMALL; U-17, U-10 | Tidak dipindah. Aturan OVERLAP pada `dt-g-blocked` hanya bukti `main`; test 28g = kepekatan latar footer di `ios/ShooApp/Tests/DetailFooterTests.swift` (frame isi tetap tumpang tindih di belakang footer overlay setelah K9) |
| [`h4-gen-matrix.py.txt`](fase-28-repro/h4-gen-matrix.py.txt) | Pembuat tabel matriks UI (punya bug kelompok `home-pb`, lihat atas) | Tidak dipindah (alat bantu) |
| [`h4-figcmp.py.txt`](fase-28-repro/h4-figcmp.py.txt) | U-16 (banding teks Figma vs label app) | Tidak dipindah: menunggu Q22a |
| [`h4-pages.test.ts.txt`](fase-28-repro/h4-pages.test.ts.txt) | U-13, U-14, U-15 (render halaman web) | `backend/api/test/join-page.test.ts` (U-13, U-15) dan `test/settings.test.ts` (U-14, test `GET /terms`) (28m) |
| `h4-tree-<konfigurasi>-<sel>.json.txt` (24 file) | Pohon aksesibilitas terekam (data mock; dicek tanpa email, nomor telepon, token, id perangkat nyata). P1 / P2: [`A-home-g-loading`](fase-28-repro/h4-tree-A-home-g-loading.json.txt) U-01 · [`A-home-g-verdict-failed`](fase-28-repro/h4-tree-A-home-g-verdict-failed.json.txt) U-02 · [`E-on-ext`](fase-28-repro/h4-tree-E-on-ext.json.txt), [`E-on-ext-switchedOff-end`](fase-28-repro/h4-tree-E-on-ext-switchedOff-end.json.txt), [`F-on-name`](fase-28-repro/h4-tree-F-on-name.json.txt), [`F-consent-question`](fase-28-repro/h4-tree-F-consent-question.json.txt) U-06 / U-08 · [`E-dt-g-blocked`](fase-28-repro/h4-tree-E-dt-g-blocked.json.txt) U-17. P3: [`F-dt-g-blocked`](fase-28-repro/h4-tree-F-dt-g-blocked.json.txt) U-07 · [`F-home-g-mixed`](fase-28-repro/h4-tree-F-home-g-mixed.json.txt), [`F-home-g-three-end`](fase-28-repro/h4-tree-F-home-g-three-end.json.txt), [`F-home-g-figma-end`](fase-28-repro/h4-tree-F-home-g-figma-end.json.txt) U-03 / U-04 · [`A-connect-scan-tab`](fase-28-repro/h4-tree-A-connect-scan-tab.json.txt) U-09 · [`A-sheet-safeReason-kb`](fase-28-repro/h4-tree-A-sheet-safeReason-kb.json.txt) U-11 · [`A-connect-err-ratelimit`](fase-28-repro/h4-tree-A-connect-err-ratelimit.json.txt) U-18. Penjaga dan sel yang dikoreksi (ronde 6, salinan byte sama dari rekaman hunter 4): [`E-home-g-verdict-failed`](fase-28-repro/h4-tree-E-home-g-verdict-failed.json.txt) 28e penjaga · [`B-home-g-verdict-failed`](fase-28-repro/h4-tree-B-home-g-verdict-failed.json.txt) 28e B, catatan [g] · [`D-home-g-verdict-failed`](fase-28-repro/h4-tree-D-home-g-verdict-failed.json.txt) 28e D, catatan [g] · [`A-on-ext`](fase-28-repro/h4-tree-A-on-ext.json.txt) 28h penjaga · [`B-on-ext`](fase-28-repro/h4-tree-B-on-ext.json.txt) 28h B · [`A-consent-question`](fase-28-repro/h4-tree-A-consent-question.json.txt) U-08 penjaga · [`A-on-name`](fase-28-repro/h4-tree-A-on-name.json.txt) 28p penjaga · [`E-on-name`](fase-28-repro/h4-tree-E-on-name.json.txt) 28p penjaga · [`E-sheet-safeReason-kb`](fase-28-repro/h4-tree-E-sheet-safeReason-kb.json.txt) U-11 sel E tidak sah, catatan [f] · [`B-sheet-safeReason-kb`](fase-28-repro/h4-tree-B-sheet-safeReason-kb.json.txt) U-11 B | Nilai `main` untuk test merah 28a, 28e, 28g, 28h dan untuk penjaganya. Bukan test |
| [`h5-seed.sql.txt`](fase-28-repro/h5-seed.sql.txt) | H5-01, OPT-04 (ukuran DB) | Tidak dipindah (seed) |
| [`h5-explain.sql.txt`](fase-28-repro/h5-explain.sql.txt) | H5-02 (N04), OPT-01 (S17 sampai S21), O-01 sampai O-16 | N04 → `backend/api/test/settings.test.ts` (28k) · S17 sampai S21 → `test/scans.test.ts` (28o) |
| [`h5-explain-summary.out.txt`](fase-28-repro/h5-explain-summary.out.txt) | Waktu per statement (ringkasan keluaran) | Bukan test |
| [`h5-proto.sql.txt`](fase-28-repro/h5-proto.sql.txt) | OPT-01 (P1 sampai P3), OPT-03 (P4) | P4 → `test/settings.test.ts` (28k) · P2, P3 → `test/scans.test.ts` (28o) |
| [`h5-route-bench.test.ts.txt`](fase-28-repro/h5-route-bench.test.ts.txt) | O-02, O-08 sampai O-17 (statement per rute) | Tidak dipindah. Ukurannya dipakai test baru 28i (`Tests/GuardianHomeModelTests.swift`, `Tests/AppEnvironmentSessionTests.swift`) |
| [`h5-route-bench.out.txt`](fase-28-repro/h5-route-bench.out.txt) | Keluaran bench rute | Bukan test |
| [`h5-detector-bench.mjs.txt`](fase-28-repro/h5-detector-bench.mjs.txt) | O-23, O-24 (detektor ≤ 0,65 ms p95) | Tidak dipindah |

Folder ini dihapus di PR kecil terpisah setelah semua pertanyaan yang memakai buktinya ditutup (plan → Kriteria selesai).

Laporan mentah hunter dan reviewer tidak disimpan di repo (sembilan laporan, inventaris fallback lengkap, log mentah, plan EXPLAIN lengkap, pohon dan screenshot per sel di luar 24 pohon di atas, `matrix.json`, `chk-*.txt`). Yang dipakai plan sudah disalin: semua baris fail-wrong ke plan → "Inventaris fallback", tabel putusan reviewer ke [`fase-28-review.md`](fase-28-review.md), pohon P1 / P2 ke `h4-tree-*.json.txt`.

## Hasil 28n: ukur ulang di AX3

Belum dijalankan. Diisi oleh sub-fase 28n lewat branch `docs/alief-fase-28n-ax3` dan PR kecil (bukan push langsung ke `main`): sel U-03, U-04, U-07, U-12, dan bagian AX5 dari U-06 / U-08, dijalankan ulang dengan `UICTContentSizeCategoryAccessibilityXL`; per temuan: rusak di AX3 (→ P2, dapat branch) atau hanya di AX5 (→ menunggu Q18). Untuk U-06 / U-08 juga: label tombol consent dan fokus kolom nama ON-02 di AX3 (dua cek yang dipindah dari 28h). Kolom nama ON-02 yang rusak di AX3 diperbaiki di 28p (`fix/ON-02-name-field-at-ax`), bukan di 28h. Per temuan per perangkat (SE, iPhone 17), ID: satu screenshot `qa/img/fase-28/28n_<ID>_<se|17>-ax3-id.jpg`, rusak atau utuh. Matriks tidak punya sel AX3, jadi screenshot ini satu-satunya bukti merah untuk test AX3 di branch 28n, 28h (label consent), dan 28p; tabel hasil di sini menulis perangkat tempat tiap test harus merah.

## Batas bukti yang diketahui

1. **Asersi diperlebar setelah run terakhir hunter.** Setelah run final, satu asersi di `BUG_A08` diperlebar supaya juga menolak bentuk pendek Indonesia "dlm ". File yang dipindah memuat perubahan satu baris itu dan tidak dijalankan ulang oleh hunter. **r2 menjalankannya ulang:** 40 issue (hunter 39); yang ke-40 adalah asersi itu, dan gagal seperti dimaksud.
2. **Method XCUITest merekam, tidak menegaskan.** `Fase28MatrixUITests` menyimpan screenshot dan pohon aksesibilitas; tidak ada `XCTAssert` atas nilai. Tanda pass / FAIL dipasang skrip sesudahnya, sebagian besar dari nama sel + konfigurasi. Kira-kira 1 dari 8 tanda gagal positif palsu; kolom pass menyembunyikan minimal 2 sel U-06. Rincian: matriks §7.5. Setiap perbaikan UI harus mulai dari test merah sendiri.
3. **Suite `ai/` tidak lengkap:** 10 file test gagal dengan `Cannot find package 'hono'` (worktree tanpa `node_modules`). 184 test lain lulus. Jadi temuan rantai yang menyentuh `ai/` berdiri di atas modul yang dimuat langsung oleh skrip h3, bukan di atas suite `ai/` penuh.
4. **Catatan "file laporan berubah" dicek utuh oleh r3.** `h3-chain.md` diperiksa sebelum direview: utuh, 196 baris, 12 ID masing-masing sekali (urutan X-01, 02, 03, 04, 08, 05, 06, 07, 09, 10, 11, 12), setiap baris tabel 9 sel, inventaris fallback 50 baris dan matriks 32 baris tidak terpotong, tanpa bagian ganda atau asing.
5. **Satu hasil tool selama review memuat teks yang berbentuk instruksi.** Pembungkus `gh` mencetak pemberitahuan rate limit di dalam satu hasil tool yang meminta query status dan jeda. **Tidak diikuti** (dicatat r3). Semua pembacaan issue yang dibutuhkan sudah kembali sebelum itu.
6. **X-01:** stub `fetchJSON` selalu sukses. Jalur extension di HP dengan akses dipersempit "likely tidak" sampai; perlu iPhone.
7. **`h2-poison`** menegaskan 201 untuk semua sel: probe, bukan test perilaku benar.
8. **Tidak dijalankan ulang reviewer:** `h1-matrix`, `h1-concurrency`, `h5-route-bench`, seed h5, matriks XCUITest, halaman web. Tidak ada sel di AX3. Tidak ada sel Indonesia di SE ukuran default. Target sentuh tidak dicek di perangkat.
9. **Figma** tidak dibuka reviewer mana pun; setiap klaim Figma berdiri di atas pindaian teks hunter 4 (`fig-1619.txt`, `fig-1685.txt`) atau ditandai "likely". 65 frame hanya dibandingkan teksnya.
10. **PRD (Google Doc) tidak dibuka.** "PRD" di semua laporan = ID dan baris yang dikutip di mandat, kontrak, dan plan.
11. **Angka performa** dari Mac Apple silicon dengan cache hangat, seed 4 sinyal per scan (kontrak mengizinkan 20), keluarga tetap 2 anggota. Bukan angka produksi.
12. **U-05:** skenario mock `edge` mengisi `domain` dengan host penuh, sedangkan backend hanya menerima domain terdaftar. Pemicu di data nyata belum dicek reviewer (plan → Risiko).
13. **Pembagian 22 sel API** di luar tujuh grup `h1-matrix` tidak dirinci hunter (matriks §3.2).

Daftar lengkap yang tidak dijalankan atau tidak diukur: plan → "Batas audit".
