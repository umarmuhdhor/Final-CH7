# Fase 18 — Page replica: bukti salinan halaman (EX-07 backend, DT-04 Detail)

| Field | Nilai |
|---|---|
| Track | c (backend dulu, lalu app) |
| Branch | 18a `feat/EX-07-replica-backend` (backend) · 18b `feat/DT-04-page-replica` (Detail, dari `main` setelah 18a merge, atau stacked di atas 18a) |
| Prasyarat | Issue #176 (Umar). Kontrak PR #177 `feat/EX-07-page-replica-contract` di-merge (aditif). 18b juga butuh `pageReplicaUrl` di `ios/ShooShared/ScanResult.swift` (file Lead, ditanyakan di issue #176, TODO C27) |
| Requirement | EX-07 (bukti scan, bagian backend), DT-04 (bukti di Detail), SECURITY §3 P2, P3, P6, P9, P13 |
| Model | Opus 5.5 · `ecc:security-reviewer`, `ecc:swift-reviewer`, `ecc:typescript-reviewer`, `ecc:database-reviewer` |
| Fase berikutnya | 18c (follow-up setelah 14 hari: hapus `screenshotBase64`/`screenshotUrl`, TODO C26 butir 5) |

## Tujuan

Bukti di Detail menjadi **salinan halaman** (DOM statis dari extension) menggantikan screenshot yang sering tidak sempat diambil. Alurnya tersambung ujung ke ujung: extension (PR #178 Umar) → `POST /scans` (`pageReplicaBase64`) → bucket privat → `GET /scans/{id}` (`pageReplicaUrl`, link Worker 1 jam) → Detail merender salinan tanpa JavaScript dan tanpa jaringan. Scan lama tetap menampilkan `screenshotUrl` sampai habis retensi 14 hari.

## Bacaan wajib

- Issue #176 (usulan + 4 pertanyaan), PR #177 (`contracts/api.md` "Page replica", `scan-result.schema.json`), PR #178 (`replica.js`, `replica-build.js`, `background.js`: kirim ulang tanpa replica saat 413)
- Fase 09 (screenshot, D-alief-B07/B08), fase 12 (retensi, tombstone, D-alief-B12), PR-05 favicon (migrasi `20261028120000_favicons.sql`, pola paling dekat)
- `backend/api/src/{app.ts, routes/scans.ts, routes/screenshots.ts, services/scans.ts, services/screenshots.ts, services/screenshotLinks.ts, cron/retention.ts, db/repo/scans.ts, db/repo/devices.ts, db/repo/tombstones.ts, http/rateLimit.ts, routes/privacy.ts}`
- `ios/ShooApp/Features/Detail/{DetailView, DetailModel, ScreenshotView, PrivacyCover}.swift`, `Data/MockRepository.swift`, `Data/Fixtures/*.json`
- `ARCHITECTURE.md` §3 (batas Free: CPU 10 ms, 50 subrequest, Storage 1 GB, egress 5 GB, ambang R2 700 MB / 3,5 GB), `SECURITY.md` §3 P1–P13

## Cek kelayakan (diverifikasi terhadap kode `main` af0d07b, 29 Okt 2026)

| # | Butir issue #176 | Bisa? | Temuan dari kode | Tindakan di fase ini |
|---|---|---|---|---|
| K1 | Body `/scans` 512 KB | Ya | Ada **dua** batas: `MAX_REQUEST_BYTES` global 256 KB (413 awal di `app.ts:35,47`, sebelum auth) dan `MAX_BODY` 256 KB di `routes/scans.ts:17`. Menaikkan satu saja tetap 413 | Batas 512 KB khusus `POST /scans` di kedua tempat; route lain tetap 256 KB / 16 KB. Komentar `app.ts:33-34` diperbarui |
| K2 | Validasi gzip + batas 3 MB terdekompresi | Ya, dengan risiko CPU | `DecompressionStream("gzip")` ada di workerd. Workers Free = **CPU 10 ms per invocation** (`waitUntil` ikut dihitung); parse JSON 512 KB + base64 400 KB + inflate 3 MB bisa mendekati batas. `wrangler dev` tidak menegakkan batas itu | Rencana A: inflate streaming dengan hitungan byte, berhenti di 3 MB (ISIZE tidak dipercaya). Ukur di cloud (uji asap, CPU dari dashboard/`wrangler tail`; field `cpuTime` belum diverifikasi). Rencana B kalau kasus terburuk > 8 ms: backend hanya cek magic `1f 8b 08` + ukuran + inflate 64 KB pertama (gzip sah, diawali HTML), batas 3 MB ditegakkan `ReplicaLoader` di app; usulan ke Umar lewat #176 |
| K3 | Simpan seperti screenshot | Ya | Bucket `screenshots`: 153 600 byte, hanya `image/*` (`20261021170000_screenshot_bucket.sql:6-7`, `20261028120000_favicons.sql:22`). Replica ≤ 400 KB base64 = ≤ 307 200 byte gzip, tipe bukan gambar | **Bucket baru `replicas`** (privat, 307 200 byte, hanya `application/gzip`) lewat migrasi (bucket `screenshots` juga dibuat lewat migrasi, `init.sql:212`); guard bucket screenshot tetap ketat. Jawaban Q2 |
| K4 | Kuota 50/hari/device + reuse 24 jam | Ya | Pola `reserveScreenshot`/`reserveFavicon` (lock per owner, tombstone sebelum upload) bisa dipakai ulang | `reserveReplica` dengan pola sama. Reuse owner + domain 24 jam dipertahankan (jawaban Q3); Detail menampilkan `meta.url` kalau berbeda dari `scan.url` (salinan dari halaman lain domain yang sama) |
| K5 | Anggaran Storage 1 GB + egress 5 GB | Perlu batas baru | Hari ini: screenshot 300/hari × 150 KB × 15 = 675 MB; favicon 200/hari × 64 KB × 15 ≈ 192 MB. Replica terburuk 300 KB × 300/hari = 1,35 GB. Ambang pindah R2 di ARCHITECTURE §3 = 700 MB | Kuota global replica: **≤ 300 upload dan ≤ 20 MB** (`sum(replica_bytes)`) per 24 jam → ≤ 300 MB. Kuota global screenshot 300 → 60/hari selama transisi → 135 MB. Total terburuk 300 + 135 + 192 = **627 MB** < 700 MB. Egress: `viewReplica` 10/menit + 100/hari per viewer, global 300 tampilan/hari (≤ 90 MB/hari, ≤ 2,7 GB/30 hari). Angka di `db/scripts/quota-estimate.sql` + ARCHITECTURE §3 |
| K6 | Hapus bersama scan (14 hari, `DELETE /devices/me`, disconnect) | Ya, **dengan dua celah** | (a) `dueTombstones` (`tombstones.ts:40-49`) hanya mengecualikan path yang dipakai di `screenshot_path`/`favicon_path`: tombstone replica dibuat saat reservasi, jadi cron akan **menghapus replica hidup** ±10 menit setelah upload. (b) Predikat retensi (`retention.ts:132,179,182`) belum mengenal kolom baru: scan yang hanya punya replica masuk jalur "plain" tanpa tombstone → objek yatim (P13). Tombstone hanya menyimpan path, tanpa bucket | Kolom `replica_path`; path `<owner>/<scan>-replica.html.gz`. `dueTombstones` + `not exists … replica_path = t.path`. `replica_path` di ketiga predikat retensi + `union` path (`retention.ts:140-153`) + index `scans_plain_created`/`scans_shot_created`. Bucket dipilih dari akhiran `.html.gz`; path dikelompokkan per bucket **sebelum** dibagi batch di tiga tempat (`retention.ts:85`, `:161`, `removeTombstoned`), satu batch = satu DELETE. Disconnect: akses dicek di DB setiap request, scan tetap milik Protected |
| K7 | `GET /scans/{id}` → `pageReplicaUrl` 1 jam, daftar `null` | Ya | `signedLink` punya `kind` di pesan HMAC dan path `/${kind}s/` (`screenshotLinks.ts:16,32`) | `kind = "replica"` → `/replicas/:id`; link tidak bisa dipakai lintas jenis (test) |
| K8 | Header `GET <pageReplicaUrl>` | Ya | Body sudah gzip di Storage. Workers mengompresi ulang kecuali `encodeBody: "manual"` (ada di `@cloudflare/workers-types`). Hono membungkus ulang `Response` kalau ada `c.header()` setelahnya, dan kalau Storage cloud mengirim `Content-Encoding` sendiri, fetch Worker mendekompresi otomatis | Route mengembalikan `Response` mentah (`encodeBody: "manual"`, semua header di dalamnya, tanpa `c.header()` sesudahnya). Guard: cek magic `1f 8b` pada chunk pertama sebelum mengirim `Content-Encoding: gzip`, selain itu 404. Test byte mentah lewat `app.fetch`; uji asap cloud membandingkan HTML |
| K9 | Tetap terima `screenshotBase64` 14 hari | Ya | Kode screenshot tetap, hanya kuota global turun (K5) | Hapus di 18c |
| K10 | Detail: ganti `ScreenshotView` | Ya, **terblokir model** | `ScanResult` ada di `ios/ShooShared/ScanResult.swift:13` (milik Lead, hard rule 2), belum punya `pageReplicaUrl`; PR #177/#178 tidak menambahkannya | Tanya Umar di issue #176 (topik sama, aturan 7; TODO C27). Alternatif yang ikut diusulkan di komentar itu: DTO kecil di `ShooApp/Data` yang men-decode `pageReplicaUrl` dari JSON yang sama, sampai ShooShared diperbarui |
| K11 | `WKWebView` JS mati, `loadHTMLString(_, baseURL: nil)` | Ya, **dengan celah** | Header CSP dari Worker **tidak berlaku** kalau HTML diambil URLSession lalu dimuat sebagai string. CSP `<meta>` di dokumen ditulis device, jadi device yang dimodifikasi bisa membuangnya → gambar/CSS jarak jauh memuat dan membocorkan IP Guardian. `<link rel=dns-prefetch/preconnect>` lolos CSP | App menyisipkan CSP-nya sendiri (`default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:`; beberapa CSP berlaku bersamaan) + `<meta http-equiv="x-dns-prefetch-control" content="off">` tepat **setelah `<!doctype …>`** kalau ada, selain itu di posisi pertama (sebelum doctype → quirks mode). `WKContentRuleList` memblokir semua URL selain `data:`/`about:`; compile ditunggu sebelum load, gagal compile → tidak dirender (placeholder) |
| K12 | Batalkan navigasi setelah load pertama | Ya | `<meta http-equiv=refresh>`, link, form juga navigasi. WKWebView juga mengizinkan seleksi teks, callout (Share, Translate, Look Up) dan long-press "Save image" → bukti bisa keluar dari app (P9) | `decidePolicyFor`: izinkan hanya load awal `about:blank`, sisanya `.cancel`. `allowsLinkPreview = false`, `dataDetectorTypes = []`, `javaScriptCanOpenWindowsAutomatically = false`, `isInspectable = false`, media tidak autoplay. App menyisipkan `<style>*{-webkit-user-select:none!important;-webkit-touch-callout:none!important}</style>`, `contextMenuConfigurationForElement` → `nil`, `.privacyCover()` di kartu dan layar penuh (pola `ScreenshotView.swift:254`) |
| K13 | Scroll ke `focusY` dari `<meta name="shoo-replica">` | Ya, tanpa JS | JS halaman mati, jadi tidak pakai `evaluateJavaScript`. Saat `didFinish` tata letak belum tentu final; halaman bisa meluber horizontal; `focusY` bisa melewati halaman terpotong | Swift membaca meta di 16 KB pertama (JSON di atribut, entitas HTML di-decode). Setelah `didFinish`, amati `scrollView.contentSize` (KVO) sampai stabil, lalu `y = focusY × scrollView.zoomScale`, di-clamp ke `0…contentSize.height − bounds.height`. Meta rusak → mulai dari atas |
| K14 | Label "Copy of the page · <capturedAt>" + "Page cut short" | Ya | String Catalog EN/ID sudah ada | Teks EN + ID baru, waktu format lokal; meta rusak → `detectedAt` scan |
| K15 | WKWebView di dalam `ScrollView` Detail | Ya | Scroll bersarang membingungkan | Kartu tinggi tetap (pratinjau) + ketuk → layar penuh (sama dengan zoom screenshot sekarang) |
| K16 | Extension kirim ulang tanpa replica saat 413 | Sudah (`background.js:153` di #178) | Body ≤ 256 KB diterima backend `main`, tetapi `pageReplicaBase64` dibuang diam-diam (`z.object` strip, `scans.ts:46`); body > 256 KB → 413 → kirim ulang tanpa replica. Tidak ada scan hilang, tetapi **tanpa 18a scan baru tidak punya bukti apa pun** (extension tidak lagi mengirim screenshot) | 18a harus **ter-deploy** sebelum Umar merge PR #178 (TODO C26, D10) |
| K17 | Halaman privasi + dokumen | Perlu update | `routes/privacy.ts:28,39,48,63` (ID `:82,93,102,117`) menyebut screenshot "area bukti". Replica = seluruh halaman yang tampil, cakupannya jauh lebih luas | Keempat paragraf EN/ID: "salinan seluruh halaman yang tampil (teks dan gambar kecil), tanpa isian yang diketik". SECURITY P2/P9 + `backend/API.md` sama |

Kesimpulan: **semua butir 1–8 bisa dikerjakan.** Tindakan di luar folder kita: K10 (ShooShared, Umar) dan K2 rencana B (kalau benchmark gagal). Batas baru: K5. Celah yang ditutup di fase ini: K6 (tombstone + retensi), K11/K12 (app tidak percaya isi replica).

## Output

**18a backend**
- Migrasi `20261029100000_page_replicas.sql`: bucket `replicas` (privat, 307 200 byte, `application/gzip`), kolom `scans.replica_path text check (char_length(replica_path) between 3 and 300)`, `scans.replica_bytes int`, index reuse/kuota (pola favicon), predikat index `scans_plain_created` / `scans_shot_created` diperluas dengan `replica_path`. Grant `scans` sudah di tingkat tabel (`init.sql:182-185`), tidak perlu grant kolom
- `services/replicas.ts`: `decodeReplica(base64)` (base64 ketat ≤ 400 KB, magic gzip, inflate streaming ≤ 3 MB, tolak data setelah member gzip) + `attachReplica` (pola `attachScreenshot`) + `replicaUrl`
- `db/repo/scans.ts`: `reserveReplica`, `clearReplicaPath`, `replicaPathForViewer`, `replica_path` di `selectScans`
- `db/repo/tombstones.ts`: `dueTombstones` mengecualikan path yang masih dipakai `replica_path`
- `services/screenshots.ts`: `SupabaseStorageStore` menerima nama bucket; `removeTombstoned` mengelompokkan path per bucket
- `routes/replicas.ts`: `GET /replicas/:id` (HMAC `replica`, cek akses DB, rate limit, header issue butir 4, `Response` mentah)
- `http/rateLimit.ts`: `viewReplica` 10/60 s + `viewReplicaDay` 100/86 400 s per viewer, `viewReplicaAll` 300/86 400 s global
- `routes/scans.ts`, `app.ts`: field `pageReplicaBase64`, batas 512 KB khusus `POST /scans`; `toScanResult` menambah `pageReplicaUrl`; `services/scans.ts` kuota global screenshot 60 + komentar anggaran (`:13-16`)
- `cron/retention.ts`, `db/repo/devices.ts`: `replica_path` ikut dihapus + di-tombstone
- `routes/privacy.ts`, `backend/API.md`, `db/scripts/quota-estimate.sql`; plan: `ARCHITECTURE.md` §3 (anggaran) + §4 butir 3 (`pageReplicaBase64`), `SECURITY.md` P2/P9, `ref/R2` (kolom + bucket), `ref/R3` §4 (`pageReplicaBase64`, `/replicas/{id}`)
- Test vitest + pgTAP (daftar di Langkah kerja). Test retensi memakai store palsu **per bucket** (`opts.store` sekarang satu store)

**18b app**
- `Features/Detail/ReplicaView.swift` (kartu + layar penuh), `ReplicaLoader.swift` (URLSession ephemeral tanpa cache, host Worker saja, `RedirectRefuser`, ≤ 3 MB terdekompresi), `ReplicaMeta.swift` (parse meta), `ReplicaHTML.swift` (sisip CSP + DNS prefetch off + style anti-seleksi setelah doctype)
- `DetailView`: `pageReplicaUrl` → `ReplicaView`; selain itu `screenshotUrl` → `ScreenshotView`; keduanya `nil` → placeholder "No copy of this page" (mengganti "blok disembunyikan" fase 03 DT-04)
- `DetailModel.refreshEvidenceLink()` (generalisasi `refreshScreenshotLink`, satu kali refresh per jenis link)
- Fixture app (`Data/Fixtures/*.json`) + `pageReplicaUrl: null`; fixture HTML replica untuk test (`Tests/Fixtures/replica-sample.html`, plus varian berisi `<img src="http://127.0.0.1:…">`, `<link rel=stylesheet>`, `<link rel=dns-prefetch>`, `<meta http-equiv=refresh>`, form, halaman lebar, `truncated`) + `MockRepository` yang menyajikannya
- String Catalog EN/ID: "Copy of the page · %@", "Copy of the page", "Page cut short", "Copied from %@", "No copy of this page"

## Langkah kerja

### 18a — backend (`feat/EX-07-replica-backend`)

1. **Test dulu** (`superpowers:test-driven-development`): `replicas.test.ts` — base64 rusak, bukan gzip, gzip > 400 KB base64, bom gzip (ISIZE palsu, > 3 MB setelah inflate), gzip terpotong, data sampah setelah member gzip → replica dibuang, scan tetap 201 + log `replica_dropped` dengan alasan saja (tanpa id/URL/path, P6; `log-hygiene.test.ts` diperluas).
2. Migrasi + pgTAP `storage.test.sql`: bucket `replicas` privat, batas 307 200, hanya `application/gzip`; `security_review.test.sql`: panjang `replica_path` dicek.
3. `POST /scans`: `pageReplicaBase64: z.string().nullish()`; batas 512 KB di `app.ts` (hanya `POST /scans`) dan `routes/scans.ts`. Replica diproses setelah scan tersimpan, kegagalan apa pun hanya membuang replica (pola screenshot).
4. `attachReplica`: decode → `reserveReplica` (lock per owner; reuse owner + domain 24 jam; kuota 50/24 jam per device; kuota global 300 upload **dan** 20 MB `sum(replica_bytes)` per 24 jam, hanya upload asli; tombstone sebelum upload) → `put` ke bucket `replicas` dengan `content-type: application/gzip`, `cache-control: no-store` → kalau scan sudah hilang, `abandonUpload`.
5. Kuota global screenshot 300 → 60/hari (`GLOBAL_DAILY_QUOTA`), komentar anggaran diperbarui (K5).
6. `GET /scans/{id}`: `pageReplicaUrl` = link Worker `replica` 1 jam; `GET /scans` selalu `null`. Respons divalidasi ajv terhadap `scan-result.schema.json` dari PR #177.
7. `GET /replicas/:id`: pola `routes/screenshots.ts`, rate limit K5; `Response` mentah dengan `Content-Type: text/html; charset=utf-8`, `Content-Encoding: gzip`, `Content-Security-Policy: sandbox; default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:`, `X-Content-Type-Options: nosniff`, `Cache-Control: private, no-store`, `Referrer-Policy: no-referrer`, `encodeBody: "manual"`; guard magic `1f 8b` (K8).
8. Hapus: `deleteDevice`, retensi (tiga predikat + `union` path), `dueTombstones`, pengelompokan per bucket. Test: replica scan hidup **tetap ada** setelah langkah tombstone cron; scan yang hanya punya replica masuk jalur stored-files; setelah `DELETE /devices/me`, retensi, dan disconnect → `GET /replicas/:id` 404 dan objek hilang dari bucket `replicas` di Storage lokal; batch campur dua bucket tetap ≤ anggaran `storageCalls`.
9. IDOR: Guardian B tidak bisa membuka replica Protected milik Guardian A (404); link `screenshot`/`favicon` tidak membuka `/replicas/` dan sebaliknya; link kedaluwarsa 404.
10. **Benchmark CPU**: fixture terburuk (400 KB base64, 3 MB HTML) dibuat dengan `gzipBase64` dari `replica-build.js` PR #178; angka lokal hanya indikasi, angka penentu dari cloud (LANGKAH MANUAL 3). > 8 ms → rencana B K2.
11. **Wire uji lokal** (`qa/replica-e2e.sh`): halaman contoh → `buildReplica` (Node, kode PR #178) → `POST /scans` ke `wrangler dev` → `GET /scans/{id}` → `GET pageReplicaUrl` (byte mentah: header + magic gzip, lalu HTML setelah gunzip = input).
12. Review berurutan (tidak paralel): `ecc:security-reviewer` (T1, T4, T6, P6, P13, K6, K8) → `ecc:typescript-reviewer` → `ecc:database-reviewer`. Lalu LANGKAH MANUAL, log, PR (reviewer @umarmuhdhor).

### 18b — app (`feat/DT-04-page-replica`)

1. Tunggu jawaban TODO C27 (`pageReplicaUrl` di `ShooShared/ScanResult.swift`, atau izin DTO sementara). Jangan mengedit `ios/ShooShared/` sendiri.
2. **Test dulu**: `ReplicaMetaTests` (meta valid, entitas HTML, JSON rusak, tanpa meta, `truncated`), `ReplicaHTMLTests` (doctype tetap token pertama, CSP + DNS-prefetch-off + style sebelum elemen lain, tanpa doctype → paling depan), `ReplicaLoaderTests` (host lain ditolak, redirect ditolak, 404 → unavailable, > 3 MB berhenti, `urlCache == nil`), `DetailModelTests` (replica dulu, lalu screenshot, lalu placeholder; refresh link sekali saat 404/expired).
3. `ReplicaView`: `WKWebViewConfiguration` dengan `defaultWebpagePreferences.allowsContentJavaScript = false`, `websiteDataStore = .nonPersistent()`, `WKContentRuleList` (compile ditunggu, gagal → placeholder), `mediaTypesRequiringUserActionForPlayback = .all`, `dataDetectorTypes = []`; `webView.isInspectable = false`, `allowsLinkPreview = false`; UI delegate `contextMenuConfigurationForElement` → `nil`; `loadHTMLString(ReplicaHTML.locked(html), baseURL: nil)`; navigation delegate: izinkan load pertama, `.cancel` untuk sisanya.
4. `ReplicaViewTests` dengan **listener lokal** (`NWListener` di 127.0.0.1; WKWebView tidak lewat `URLProtocol`): HTML berisi `img`/`link`/`dns-prefetch`/`meta refresh`/form ke listener itu → nol koneksi masuk, nol navigasi.
5. Scroll ke `focusY` (K13), label "Copy of the page · <capturedAt>" (meta rusak → `detectedAt`), "Copied from <host+path>" bila `meta.url` ≠ `scan.url`, catatan "Page cut short" bila `truncated`, `.privacyCover()` di kartu + layar penuh, aksesibilitas (label VoiceOver kartu, tombol layar penuh).
6. `DetailView`: urutan replica → screenshot → placeholder; HTML hanya di memori, dibuang saat Detail ditutup (P9, P13).
7. Gerbang UI: Detail dengan replica contoh × {Guardian, Protected} × {EN, ID}, layar SE + XL. UI test opt-in live (`SHOO_LIVE_REPLICA=1`) memakai `qa/replica-e2e.sh` untuk menyiapkan scan lokal.
8. Review berurutan: `ecc:security-reviewer` (fokus K11, K12) → `ecc:swift-reviewer`. Log, PR.

## LANGKAH MANUAL (Alief, setelah 18a hijau lokal)

1. `supabase db push` migrasi `20261029100000_page_replicas.sql` ke `shoo-demo` (bucket `replicas` dibuat lewat migrasi).
2. Deploy Worker dari branch 18a (`pnpm -C backend/api exec wrangler deploy`), tanpa secret baru (link replica memakai `SCREENSHOT_URL_SECRET`).
3. Uji asap cloud: `qa/replica-e2e.sh --cloud` dengan device uji → 201, `pageReplicaUrl` terisi, `GET` 200 dengan header persis dan HTML sama dengan input, 404 setelah `DELETE /devices/me`; CPU `POST /scans` kasus terburuk dari dashboard Workers / `wrangler tail`.
4. Kabari Umar di issue #176 bahwa backend sudah hidup → PR #178 boleh merge (TODO C26).

## Verifikasi

```bash
(cd backend/db && supabase start && supabase test db)
pnpm -C backend/api exec vitest run replicas scans screenshots retention devices-me security-headers log-hygiene privacy rateLimit
bash plan/alief/qa/replica-e2e.sh
source plan/alief/ref/sim.sh
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppTests/ReplicaMetaTests -only-testing:ShooAppTests/ReplicaHTMLTests -only-testing:ShooAppTests/ReplicaLoaderTests -only-testing:ShooAppTests/ReplicaViewTests -only-testing:ShooAppTests/DetailModelTests
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM" -only-testing:ShooAppUITests/DetailUITests
```

## Kriteria selesai (DoD)

- [ ] `POST /scans` dengan replica sah → 201 + `pageReplicaUrl` di `GET /scans/{id}`; `GET /scans` selalu `pageReplicaUrl: null`; replica rusak / bom gzip / terlalu besar → replica dibuang, scan tetap 201 (test).
- [ ] Body 400 KB replica + scan lolos; body > 512 KB → 413 (extension mengirim ulang tanpa replica) (test).
- [ ] `GET /replicas/:id` mengirim header persis issue butir 4, byte gzip apa adanya (test `app.fetch` byte mentah); 404 setelah hapus, retensi, disconnect, link kedaluwarsa, link jenis lain (test + uji asap cloud).
- [ ] Replica scan hidup tidak dihapus cron tombstone; scan yang hanya punya replica dihapus bersama objeknya pada hari 14 (test).
- [ ] Kuota per device 50/24 jam, reuse 24 jam, kuota global 300 upload + 20 MB, batas tampilan per viewer + global terbukti (test); anggaran Storage terburuk ≤ 700 MB dan egress tercatat (log + ARCHITECTURE §3).
- [ ] CPU `POST /scans` kasus terburuk < 10 ms di cloud, atau rencana B K2 dipakai dan dicatat di DECISIONS + #176.
- [ ] Wire lokal `qa/replica-e2e.sh` lulus: HTML yang dibaca app = HTML yang dikirim extension.
- [ ] Detail: replica tampil tanpa JS dan tanpa koneksi selain ke Worker (`ReplicaViewTests` dengan listener lokal → nol koneksi, nol navigasi); seleksi/callout/context menu mati; privacy cover; scroll ke `focusY` (halaman lebar + `truncated` di-clamp); label + "Copied from" + "Page cut short" EN/ID.
- [ ] Scan lama dengan `screenshotUrl` masih tampil; keduanya `null` → placeholder (test).
- [ ] Halaman privasi EN/ID menyebut salinan seluruh halaman tanpa isian ketik; review security tanpa temuan HIGH terbuka.

## Catatan handoff

- 18c (≥ 14 hari setelah PR #178 merge, paling cepat 12 Nov 2026): hapus `screenshotBase64` di `POST /scans`, `screenshotUrl`, `ScreenshotView`, route `/screenshots`, kuota screenshot; kosongkan lalu hapus bucket `screenshots` setelah tombstone 0. Kontrak dihapus oleh Umar.
- Re-skin kartu replica saat Figma Detail datang.
