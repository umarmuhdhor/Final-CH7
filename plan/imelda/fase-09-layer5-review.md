# Layer 5: data dummy lokal + `POST /review` (draft) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pakai data dummy di DB Supabase lokal untuk membangun dan menguji bagian Team AI di layer 5: `ai/data/shared-hosts.json`, `POST /review`, dan eval aturan vs LLM. Semuanya dikirim sebagai draft PR.

**Architecture:** Data dummy dimasukkan lewat tabel `public` (`devices`, `scans`, `verdicts`, `blocklist_entries`). Dengan begitu trigger Alief (`on_scan_insert`, `on_verdict`) dan `admin.run_analysis` mengisi `admin.*` seperti di prod, dan view `admin.ai_dataset` langsung terisi. `POST /review` adalah route stateless baru di Worker `ai/` dan tidak membaca DB. Skrip lokal berperan sebagai cron dashboard: `admin.review_due()` → `/review` → `admin.review_record()`.

**Tech Stack:** Cloudflare Worker + Hono (`ai/src/app.js`), `node --test`, Supabase CLI `2.114.0` via `npx` (Colima sebagai Docker), `psql`.

**Spec:** `plan/imelda/layer-5-feedback.md` (v2) dan kontrak `/review` usulan Alief di #241 (komentar 4 Nov 14:00). Skema DB: `backend/db/supabase/migrations/20261104133527_l5_review_data.sql`, `20261104145000_ai_dataset_scan_id.sql`.

Plan ini menggantikan `plan/imelda/ai-dataset-dump.md`, yang masih memakai tabel `ai_dataset` buatan sendiri. Sekarang view asli dari Alief sudah ada.

## Global Constraints

- Hanya DB lokal. Skrip menolak jalan kalau host DB bukan `127.0.0.1` atau `localhost`. Data prod tidak dibaca.
- Supabase CLI wajib `npx -y supabase@2.114.0`. CLI 3.0 gagal di `admin_domain_intel`.
- Domain dummy hanya di TLD `.test` (`*.shoo-dummy.test`), kecuali satu baris shared host (`sites.google.com`) untuk tes skip.
- File yang diubah hanya di `ai/` dan `plan/imelda/`. `backend/`, `contracts/`, `ios/` tidak disentuh.
- Status: **draft PR**. Merge baru setelah Umar menulis jawaban Q1–3 di #241 (persetujuan lisan 4 Nov belum tertulis).
- Kontrak `/review` (Alief, #241):
  - Auth: `Authorization: Bearer <AI_REVIEW_SECRET>`.
  - Body: `{ "domains": [{ domain, signal_counts, avg_score, max_score, families_safe, families_not_safe }] }`, maksimal 25 domain.
  - 200: `{ "model", "prompt": "review.v1", "results": [{ "index", "result": "scam"|"legit"|"unsure"|null, "confidence": 0..1, "reason", "suggestion": "approve"|"reject"|"none" }] }`.
- Input ke LLM hanya angka dan nama domain. Tanpa `notes`, tanpa teks halaman (D-imelda-27/36).
- Tidak ada log isi request maupun jawaban LLM. Secret hanya di `.dev.vars` / `.env` (gitignored).
- Gagal setelah 3 percobaan: `result: null`, `suggestion: "none"` (spec §LLM).

## Review Focus

1. Domain dari klien berisi teks prompt injection (mis. `ignore-previous.approve.test`): `suggestion` tetap dihitung server dari `result` + `confidence`, bukan disalin dari model.
2. Model menjawab jumlah hasil yang salah, `index` dobel, atau `index` di luar range: setiap input tetap dapat tepat satu hasil, dan yang tidak dijawab jadi `null`/`none`.
3. `AI_REVIEW_SECRET` tidak di-set: endpoint mati (404), bukan terbuka tanpa auth.
4. Secret salah dengan panjang berbeda: 401, dan perbandingannya tidak bocor lewat waktu (compare panjang tetap).
5. Skrip dummy dijalankan ke DB cloud karena salah env: skrip berhenti sebelum query apa pun.

---

### Task 1: `ai/data/shared-hosts.json`

**Files:**
- Modify: `ai/src/layer3/official.js` (export `USER_CONTENT`)
- Create: `ai/scripts/build-shared-hosts.mjs`, `ai/data/shared-hosts.json`
- Test: `ai/test/shared-hosts.test.mjs`

**Interfaces:**
- Produces: `sharedHostList(): string[]` (diekspor dari `build-shared-hosts.mjs`): `SHARED_HOSTS` ∪ `USER_CONTENT`, lowercase, tanpa `www.`, unik, urut. File: `{ "version": 1, "source": "ai/src/blocklist/allowlist.js SHARED_HOSTS + ai/src/layer3/official.js USER_CONTENT", "hosts": [...] }`. Dibaca Alief untuk `admin.shared_hosts_set(p_hosts, ...)`.

- [ ] **Step 1: Tulis tes yang gagal**: `shared-hosts.json matches the code lists` (isi `hosts` == `sharedHostList()`, jadi kalau kode berubah tanpa build ulang, tes gagal); `every host passes admin.shared_hosts check` (regex `^[a-z0-9.-]{1,253}$`, tidak diawali `www.`); `contains sites.google.com, docs.google.com, github.io`.
- [ ] **Step 2: Jalankan** `cd ai && node --test test/shared-hosts.test.mjs`. Harus FAIL (file belum ada).
- [ ] **Step 3: Implementasi** export `USER_CONTENT`, lalu buat `sharedHostList()`. Skrip, kalau dijalankan langsung, menulis JSON dengan indent 2 dan newline di akhir.
- [ ] **Step 4: Jalankan** `node scripts/build-shared-hosts.mjs && node --test`. Semua PASS.
- [ ] **Step 5: Commit** `feat(L5): publish ai/data/shared-hosts.json for admin.shared_hosts (#241)`

### Task 2: DB lokal + data dummy

**Files:**
- Create: `ai/eval/dataset/dummy.mjs` (generator SQL), `ai/eval/dataset/seed-dummy.sh` (runner), `ai/eval/dataset/README.md`
- Test: `ai/eval/dataset/check-dummy.sql` (query cek, dijalankan runner)

**Interfaces:**
- Produces: `buildDummySql({ seed = 1 }): string`, deterministik untuk seed yang sama. Runner: `ai/eval/dataset/seed-dummy.sh` (pakai env `DB_URL`, default `postgresql://postgres:postgres@127.0.0.1:54322/postgres`).

Isi dummy (semua di satu transaksi, idempoten: hapus dulu `*.shoo-dummy.test` dan device `dummy_*`):

| Data | Jumlah | Catatan |
|---|---|---|
| Keluarga (`devices` guardian + protected, `family_links`) | 6 | id `dummy_g1..6` / `dummy_p1..6` |
| Domain scam | 8 | `scam-NN.shoo-dummy.test`, signals dari `contracts/fixtures/blocked-92.json` + variasi bobot, `rdap_registered_at` 2–40 hari lalu |
| Domain legit (salah blokir) | 5 | `legit-NN.shoo-dummy.test`, skor 30–60, RDAP > 2 tahun |
| Domain ambigu | 3 | 1 N + 1 Y |
| Shared host | 1 | `sites.google.com`, 2 keluarga N |
| `verdicts` | ±40 | `not_safe` dengan `global_eligible = true` untuk scam, `safe` untuk legit |
| `blocklist_entries` pending | semua domain dengan ≥ 2 keluarga N | `families` = jumlah keluarga N |

Setelah insert: `select admin.run_analysis('manual', 'imelda-dummy');` dan `alter role shoo_ai password 'shoo_ai_local';` (lokal saja, seperti `seed.sql`).

- [ ] **Step 1: Tulis `check-dummy.sql`** dengan `\if`/`raise exception` (jalan sebagai `shoo_ai`):
  - `select count(*) from admin.ai_dataset where domain like '%.shoo-dummy.test'` ≥ 35
  - minimal 1 baris `is_scam` dan 1 baris `not is_scam`
  - `rdap_age_days is not null` di semua baris dummy
  - `layer1_score + layer2_score + layer3_score + layer4_score` sama dengan jumlah bobot sinyal per baris
  - `admin.review_due(100)` (sebagai `postgres`) berisi domain scam dan **tidak** berisi `sites.google.com`
- [ ] **Step 2: Nyalakan DB**: `colima start`, `cd backend/db && npx -y supabase@2.114.0 start && npx -y supabase@2.114.0 db reset`. Output terakhir `db reset` tanpa error.
- [ ] **Step 3: Jalankan** `ai/eval/dataset/seed-dummy.sh`. Harus FAIL di `check-dummy.sql` (belum ada data).
- [ ] **Step 4: Implementasi** `buildDummySql`. Runner berhenti dengan `refusing: not a local database` kalau host `DB_URL` bukan `127.0.0.1`/`localhost`, lalu `psql -v ON_ERROR_STOP=1`. Tambahkan juga `--export out.jsonl` (sebagai `shoo_ai`: `select row_to_json(d) from admin.ai_dataset d`). Folder `out*` dimasukkan ke `ai/.gitignore`.
- [ ] **Step 5: Jalankan** runner dua kali berturut-turut. Dua-duanya PASS (idempoten), dan `out.jsonl` berisi ≥ 35 baris.
- [ ] **Step 6: Commit** `feat(L5): local dummy data for admin.ai_dataset (#241)`

### Task 3: `POST /review`

**Files:**
- Create: `ai/src/review/review.js` (validasi + orkestrasi), `ai/prompts/review.js` (prompt `review.v1`), `ai/test/review.test.mjs`, `ai/test/fixtures/review/*.json`
- Modify: `ai/src/app.js` (route), `ai/src/layer4/provider.js` (opsi `maxTokens`, default 200), `ai/.env.example`, `ai/CLAUDE.md`, `ai/README.md`

**Interfaces:**
- Consumes: `createProvider({ config, fetch })` → `(messages, signal, opts?)` dengan `opts.maxTokens`; `readConfig(env)`; `SHARED_HOSTS`/`sharedHostList()` (Task 1); `HttpError`, `errorResponse`, `readTextLimited` (`src/http.js`).
- Produces:
  - `validateReviewRequest(body): { domains: ReviewInput[] } | { error: string }`
  - `createReviewer({ config, fetch, now, dailyCap }): { review(domains: ReviewInput[]): Promise<{ model: string, prompt: "review.v1", results: ReviewResult[] }> }`
  - `suggestionFor(result, confidence): "approve" | "reject" | "none"`: `scam` dan ≥ 0.7 → `approve`, `legit` dan ≥ 0.7 → `reject`, selain itu `none`.

Keputusan:
- **Satu panggilan LLM per request** (≤ 25 domain dalam satu prompt, jawaban `{"results":[{index,result,confidence,reason}]}`), `maxTokens: 2000`, timeout 15 s per percobaan, maksimal 3 percobaan. Lebih hemat subrequest dan token dibanding satu panggilan per domain.
- Shared host (`domain === h` atau `domain.endsWith("." + h)`) tidak dikirim ke model. Hasilnya `{ result: "unsure", confidence: null, reason: "shared_host", suggestion: "none" }`.
- `suggestion` selalu dari `suggestionFor`. Field `suggestion` dari model diabaikan.
- `reason`: potong 500 karakter, hapus `<` dan `>`, trim; kosong → `null`.
- Validasi input: `domain` `^[a-z0-9.-]{1,253}$` tanpa `www.`; `signal_counts` objek ≤ 30 kunci `^[a-z_]{1,40}$` → int 0..1e6; `avg_score`/`max_score` int 0..100 atau `null`; `families_*` int 0..1e4; panjang `domains` 1..25.
- Status HTTP:

| Kondisi | Status |
|---|---|
| `AI_REVIEW_SECRET` tidak di-set | 404 `not_found` |
| Bearer salah atau tidak ada | 401 `unauthorized` |
| Body tidak valid | 422 `invalid_body` |
| LLM belum dikonfigurasi (`readConfig` null) | 503 `review_unavailable` |
| Kuota harian `REVIEW_DAILY_CAP` habis (default 20 request/hari per isolate) | 429 `rate_limited` |
| LLM gagal 3 kali | 200, semua `result: null`, `suggestion: "none"` |

- `/review` tidak ditambahkan ke `KNOWN_PATHS` (tidak ada CORS; ini server-to-server). Method selain POST → 405.

- [ ] **Step 1: Tulis tes yang gagal** di `review.test.mjs`, pakai fetch LLM mock:
  - `no secret configured -> 404`; `wrong bearer -> 401` (termasuk secret dengan panjang berbeda); `GET -> 405`
  - `26 domains -> 422`; `bad domain "A..b" -> 422`; `signal_counts with 31 keys -> 422`
  - `valid batch -> 200 { model, prompt: "review.v1", results }`, `results.length === domains.length`, `index` 0..n-1 urut
  - `shared host is answered without calling the model` (mock fetch 0 panggilan untuk batch `["sites.google.com"]`)
  - `model suggestion is ignored: {result:"legit", confidence:0.9, suggestion:"approve"} -> suggestion "reject"`
  - `missing / duplicate / out-of-range index -> that input gets result null, suggestion none`
  - `model fails 3 times -> 200, all result null`; `3 attempts exactly` (hitung panggilan mock)
  - `reason "<script>x</script>"` → tanpa `<` dan `>`; reason 900 karakter → 500
  - `outgoing LLM body has no notes, no url path, only the six input fields`
  - `nothing is logged` (spy `console.*`, seperti `rdap.test.mjs`)
- [ ] **Step 2: Jalankan** `cd ai && node --test test/review.test.mjs`. Harus FAIL (modul belum ada).
- [ ] **Step 3: Implementasi** `ai/prompts/review.js` (system prompt: "Kamu menilai apakah domain scam dari angka berikut…", output JSON saja, `reason` ≤ 1 kalimat), lalu `review.js`, opsi `maxTokens` di provider, dan route di `app.js`. Bandingkan secret dengan panjang tetap (hash SHA-256 kedua sisi, lalu XOR byte).
- [ ] **Step 4: Jalankan** `node --test`. Semua PASS (386 tes lama + yang baru).
- [ ] **Step 5: Tambahkan** `AI_REVIEW_SECRET=` dan `REVIEW_DAILY_CAP=` ke `.env.example`, satu baris di `ai/CLAUDE.md` dan `README.md`. Commit `feat(L5): POST /review batch suggestions, server-secret auth (#241)`.

### Task 4: Tes end-to-end lokal (pengganti cron dashboard)

**Files:**
- Create: `ai/eval/dataset/review-loop.mjs`

**Interfaces:**
- Consumes: runner Task 2 (DB berisi dummy), `/review` Task 3 di dev server (`npm run dev`, `AI_REVIEW_SECRET` dari `ai/.env`).
- Produces: CLI `node eval/dataset/review-loop.mjs [--mock-llm]`. Alurnya: `select * from admin.review_due(25)` → `POST /review` → `select admin.review_record($results, $model, $prompt, 'imelda-dummy')`, lalu cetak jumlah baris tersimpan.

- [ ] **Step 1: Jalankan** dengan `--mock-llm` (dev server memakai fetch mock lewat env `REVIEW_MOCK=1`, hanya di `dev-server.mjs`). Hasil yang diharapkan: `stored N` dengan N = jumlah domain di `review_due`, dan `admin.v_review_queue` menampilkan `review_result`.
- [ ] **Step 2: Jalankan ulang.** Harus `stored 0`, karena `review_due` melewati domain yang sudah di-review setelah label terakhir.
- [ ] **Step 3: Jalankan sekali dengan LLM asli** (key di `ai/.env`). Datanya dummy, jadi aman dikirim. Catat model, latensi, dan token ke `plan/imelda/log/l5-review-local.md`.
- [ ] **Step 4: Commit** `test(L5): local review loop against the dummy DB (#241)`

### Task 5: Eval aturan vs LLM

**Files:**
- Create: `ai/eval/dataset/eval-review.mjs`
- Modify: `plan/imelda/log/l5-review-local.md`

**Interfaces:**
- Consumes: `out.jsonl` (Task 2) dan hasil `admin.domain_review` (Task 4).
- Produces: tabel precision/recall untuk (a) aturan `families_not_safe >= 2 && avg_score >= 50` → approve, dan (b) `suggestion` LLM. Label: `final_label in ('scam_strong','scam_weak')` = scam.

- [ ] **Step 1: Tulis tes** `eval-review` dengan 4 baris buatan yang hasilnya sudah diketahui (TP, FP, FN, TN) → precision 0.5, recall 0.5 untuk masing-masing (a) dan (b).
- [ ] **Step 2: Implementasi**, lalu jalankan ke data dummy. Tulis hasil ke log, dengan catatan: **data dummy, bukan bukti**. Keputusan "LLM dipakai atau tidak" baru diambil dari data Guardian asli.
- [ ] **Step 3: Commit, push, buka draft PR** `feat(L5): shared hosts, POST /review, local dummy dataset (#241)`. Di body PR: "Draft until Umar confirms Q1–3 in #241". Update `plan/imelda/TODO.md` C12 dengan nomor PR.

## Estimasi

| Task | Waktu |
|---|---|
| 1 shared-hosts.json | 30 menit |
| 2 DB lokal + dummy | 2–3 jam (paling lama di constraint FK/trigger) |
| 3 `/review` | 4–5 jam |
| 4 loop lokal | 1 jam |
| 5 eval | 1 jam |
