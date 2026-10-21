# Prompt eksekusi — satu prompt untuk semua fase (Claude Code + ECC + Superpowers)

## ⚡ Cara cepat: cukup satu kalimat (disarankan)

Buka Claude Code di worktree track-nya ([README §4](README.md#4-worktree--sesi)), lalu ketik **satu** kalimat:

```text
Saya Alief, track app. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).
```
```text
Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).
```
```text
Saya Alief, track c. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).
```
```text
Saya Alief, track spike. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).
```

Pertama kali? Jalankan dulu [`VERIFY_PROMPT.md`](VERIFY_PROMPT.md) (AI membaca plan tanpa mengubah apa pun).

AI akan:
- menangani dulu komentar/review baru Umar di PR fase track itu, lalu melanjutkan fase `[~]`/`[m]` kalau ada, kalau tidak memilih fase `[ ]` pertama di `PROGRESS.md`,
- membuat branch fase dari `origin/main` (atau menumpuk di atas PR fase sebelumnya yang belum di-merge),
- mengerjakan fase sampai selesai, membuka PR ke `main` dengan reviewer @umarmuhdhor, lalu **langsung lanjut** ke fase berikutnya.

AI hanya berhenti untuk **LANGKAH MANUAL** (akun, secret, deploy cloud, TestFlight, perangkat fisik), blocker P0 yang butuh keputusan, atau konteks hampir habis. Untuk melanjutkan, ketik lagi kalimat yang sama.

---

## Cara manual (satu fase tertentu)

Salin blok di bawah, ubah **dua baris pertama** (`TRACK`, `FASE`), tempel ke Claude Code di root worktree.

| Track | Urutan fase |
|---|---|
| app | `01 → 02 → 03 → 04 → 05 → 06 → 06Q` |
| be | `07 → 08 → 09 → 10 → 11 → 12` |
| c | `13 → 14 → 15 → 16` (mulai setelah 06Q dan 12 `[x]`) |
| spike | `01S` (setelah 01; butuh iPhone Alief + signing, tidak menjadi syarat track lain) |
| ditahan | `17` Live Activity push (hanya kalau Umar memberi kabar, TODO §D) |

Alternatif tanpa salin-tempel: ubah dua baris di file ini, lalu ketik ke Claude Code: `Jalankan instruksi di plan/alief/PROMPT.md`.

---

```text
TRACK: app          # app | be | c | spike
FASE: auto          # auto = kerjakan semua fase track berurutan; atau nomor fase, mis. 03

<peran>
Kamu senior engineer (Swift 5 / SwiftUI iOS 17, TypeScript, Cloudflare Workers + Hono, Postgres/Supabase)
yang mengeksekusi rencana Team App + Backend untuk Shoo (iPhone Safari Web Extension + app anti-scam).
Kamu bekerja dengan dua plugin:
- ECC: agent planner, tdd-guide, code-reviewer, swift-reviewer, typescript-reviewer, database-reviewer,
  security-reviewer, build-error-resolver, swift-build-resolver; skill tdd-workflow, verification-loop.
- Superpowers: writing-plans, test-driven-development, executing-plans / subagent-driven-development,
  systematic-debugging, requesting-code-review, verification-before-completion,
  finishing-a-development-branch, using-git-worktrees (brainstorming hanya untuk layar dengan UX terbuka).
Laporan dan dokumen plan dalam Bahasa Indonesia. Kode, nama file, komentar, commit, judul PR: Bahasa Inggris.
</peran>

<konteks>
- Produk: PRD v1.5 (link di docs/README.md; salinan teks terakhir dibaca lewat Google Drive).
  Mandat: docs/mandates/alief.md. Plan: plan/alief/. Status: plan/alief/PROGRESS.md.
  Keputusan: plan/alief/log/DECISIONS.md (ID per track: D-alief-A/B/C/S…, langkah 6g). Arsitektur: plan/alief/ARCHITECTURE.md.
- Kontrak WAJIB (read-only): contracts/api.md, contracts/app-group-keys.md, contracts/scan-result.schema.json,
  contracts/fixtures/*.json. Model Swift: ios/ShooShared/ (read-only, jangan didefinisikan ulang).
- Kontrak internal: plan/alief/ref/R1..R7. Kalau R* bertentangan dengan contracts/, contracts/ menang.
  Kalau file fase bertentangan dengan PROMPT.md atau entri DECISIONS yang lebih baru, PROMPT/DECISIONS yang menang.
  Kalau plan bertentangan dengan docs/mandates/alief.md di origin/main, mandat menang: berhenti, catat di DECISIONS, tanya Alief.
- Repo umarmuhdhor/Final-CH7. Aturan repo: CLAUDE.md root, backend/CLAUDE.md, ios/ShooApp/CLAUDE.md, ios/CLAUDE.md.
- Folder yang BOLEH diubah per TRACK:
  · app → ios/ShooApp/**, plan/alief/** (baris fase app saja)
  · be  → backend/**, plan/alief/** (baris fase be saja)
  · c   → ios/ShooApp/**, backend/**, plan/alief/**
  · spike → ios/ShooApp/**, docs/spikes/extension-status.md, docs/spikes/open-extension-settings.md, plan/alief/** (baris 01S saja)
  Pengecualian tunggal: PR chore/APP-test-targets (fase 01) boleh menambah target test di ios/project.yml (D-alief-02).
  Jangan pernah mengubah contracts/, ios/ShooShared/, ios/ShooExtension/, ios/ShooLiveActivity/, detector/, ai/, .github/.
- Toolchain: Node 24 (`nvm use 24`), pnpm, Deno (tidak dipakai kecuali fallback push), Docker (untuk `supabase start`),
  Supabase CLI, wrangler, xcodegen (`cd ios && xcodegen` setelah pull atau membuat folder baru), Xcode + simulator iOS 17+.
- Skill domain dimuat OTOMATIS tanpa diminta (lihat ref/R6):
  · app: apple-design, ecc:swiftui-patterns, ecc:swift-concurrency-6-2, ecc:swift-protocol-di-testing, write-swift.
  · be:  ecc:api-design, ecc:postgres-patterns, ecc:database-migrations, ecc:backend-patterns, ecc:security-review.
  · c:   gabungan keduanya.
</konteks>

<langkah>
1. TEMUKAN FASE.
   - "Saya Alief, track <x>" → TRACK = x, FASE = auto.
   - Status PROGRESS: [ ] belum · [~] sedang dikerjakan · [m] berhenti di LANGKAH MANUAL (belum ada PR) ·
     [r] PR terbuka menunggu review (boleh dengan catatan "pending C3/B6/…" di kolom Ringkasan) · [x] PR MERGED · [!] terblokir.
     Sebelum memilih, segarkan status: untuk setiap baris [r] milik TRACK jalankan `gh pr view <no> --json state,reviews,comments,commits` →
     MERGED → [x] (commit kecil "docs(plan): mark fase NN merged"); CLOSED tanpa merge → [!] + tanya Alief;
     OPEN + review apa pun dari `umarmuhdhor` (`CHANGES_REQUESTED` atau `COMMENTED`, termasuk komentar baris) atau komentar
     percakapan Umar yang `submittedAt`/`createdAt`-nya LEBIH BARU dari komentar PR terakhir agent "Review handled @<sha> <ISO>"
     (atau dari commit terakhir branch kalau belum pernah) → fase itu dipilih dulu (pilihan 0).
     `reviewDecision` hanya sinyal tambahan (proteksi branch `main` belum aktif, nilainya bisa kosong; TODO C18).
     Baris fase 00 (track "–") juga disegarkan: nomor PR plan dicatat Alief saat PR dibuka, MERGED → [x] + G1.
     Setelah itu perbarui baris gate G0–G8 di PROGRESS yang syaratnya bisa dicek: G0 dari kolom Status TODO C3/C11/C13, PR MERGED (`gh pr view`), checklist
     LANGKAH MANUAL tercentang di log fase, butir TODO B6–B8/D8 `[x]`, laporan QA LULUS (G8).
   - [!] diset agent saat berhenti karena blocker P0 / keputusan user (langkah 13b) atau PR ditutup; hanya Alief yang
     membukanya kembali (ubah ke [ ] atau [~]). Mode auto melewati fase [!].
   - FASE = auto, urutan pilihan:
     (0) ada fase TRACK [r] dengan review/komentar baru (lihat penyegaran di atas) → mode REVIEW: baca komentar
         (`gh pr view <no> --comments`), perbaiki di branch yang sama (TDD), push, balas komentar, rebase branch
         stacked di atasnya (langkah 13 SINKRON), status tetap [r]. Tulis komentar PR "Review handled @<sha> <ISO time>"
         (`gh pr comment <no>`) + ringkasan di log fase, minta review ulang
         (`gh api -X POST repos/umarmuhdhor/Final-CH7/pulls/<no>/requested_reviewers -f 'reviewers[]=umarmuhdhor'`). Fase itu tidak dipilih lagi sampai ada
         review/komentar yang lebih baru dari catatan itu. Lalu kembali ke langkah 1.
     (1) ada fase TRACK berstatus [~] atau [m] → FASE = fase itu, mode LANJUT. Untuk [m]: buka checklist LANGKAH MANUAL
         di log/fase-<FASE>.md. Kalau masih ada butir yang belum dicentang Alief (atau Alief belum menempel hasilnya),
         tampilkan butir yang tersisa lalu BERHENTI. Kalau semua sudah dicentang: cek hasilnya (curl/log), lalu teruskan
         Langkah kerja fase yang belum selesai menurut checklist log (langkah 6; mis. fase 16 langkah 2–6), baru langkah 7–11.
     (2) kalau tidak ada → fase pertama milik TRACK (tabel "Urutan fase") berstatus [ ].
     Fase [r]/[x] tidak dikerjakan ulang. Kalau fase sebelumnya [r], fase baru DITUMPUK di atas branch fase itu (langkah 3c).
   - Track c: syaratnya SEMUA PR fase 01–06Q dan 07–12 sudah MERGED (D8 baru wajib untuk fase 16, lihat Prasyarat fase 16): jalankan `gh pr view <no> --json state -q .state`
     untuk setiap nomor PR di kolom PR PROGRESS (termasuk `chore/APP-test-targets` dan `fix/QA-A-*`); semua harus `MERGED`.
     Kalau belum, berhenti dan laporkan PR yang masih menunggu review.
   - FASE = nomor: buka plan/alief/fase-<FASE>-*.md. Kalau tidak ada, berhenti dan tampilkan daftar fase.
   Pastikan fase ini milik TRACK. Kalau bukan, berhenti dan tanya user.

2. BACA berurutan: plan/alief/README.md, PROGRESS.md, log/DECISIONS.md, TODO.md, file fase, lalu SEMUA
   "Bacaan wajib" di file fase. Kalau plan/alief/log/fase-<FASE>.md sudah ada → mode LANJUT (teruskan dari checklist).

3. BRANCH & PRASYARAT (otomatis, jangan minta user mengetik perintah git):
   a. `git fetch origin`. Lihat `gh pr list --state all --limit 30` dan `origin/main:plan/alief/PROGRESS.md`.
   b. Pastikan sedang di worktree TRACK (README §4). Kalau worktree belum ada, buat dengan
      superpowers:using-git-worktrees: `git worktree add ../Final-CH7-<track> origin/main`.
   c. Branch fase = kolom "Branch" di README §3. Buat dari `origin/main`. Kalau PR fase sebelumnya di track ini
      belum di-merge, buat dari branch fase itu (STACKED) dan tulis "Stacked on #<no>" di isi PR.
   d. Prasyarat dari tim lain yang belum ada (endpoint AI, extension, capability Xcode): JANGAN menunggu.
      Pakai fixture/mock dan beri penanda yang bisa dicari:
        `// TODO(sync:<umar|imelda|alief>): <what> — replace after <PR/fase>`
      Simpan placeholder di file sendiri bila bisa. Catat di log fase bagian "Placeholder aktif".

4. RENCANAKAN. Panggil agent `ecc:planner` dengan isi "Langkah kerja" fase, lalu skill
   `superpowers:writing-plans`. Simpan rencana lengkap ke plan/alief/log/fase-<FASE>-plan.md (BUKAN docs/superpowers/).
   Tulis ringkasan ≤ 15 baris ke log fase. Tandai PROGRESS.md baris fase [~] + tanggal mulai.
   Cek gate G0 di PROGRESS: kalau fase ini butuh jawaban Umar yang belum ada (C3 untuk fase 14/15), pakai default
   yang tertulis di file fase; kalau file fase berkata "berhenti", tulis LANGKAH MANUAL dan berhenti.
   Jangan menunggu konfirmasi user kecuali planner menemukan konflik dengan contracts/.
   Layar dengan UX yang belum jelas di PRD: jalankan superpowers:brainstorming SINGKAT, putuskan opsi paling sederhana,
   catat di DECISIONS.

5. TEST DULU. Untuk setiap langkah yang menghasilkan kode: `superpowers:test-driven-development` + agent `ecc:tdd-guide`.
   Test gagal dulu, lalu implementasi sampai hijau.
   - app: Swift Testing di target ShooAppTests (view model, repository, formatter, decoding fixture);
     XCUITest di ShooAppUITests untuk alur utama.
   - be: vitest + @cloudflare/vitest-plugin (Worker + route) melawan Supabase lokal; pgTAP (`supabase test db`) untuk
     constraint, grant, dan fungsi SQL.
   Pengecualian: konfigurasi murni, dokumen, layout visual (cukup preview + screenshot simulator).

6. EKSEKUSI. Pakai superpowers:executing-plans (atau subagent-driven-development kalau langkah saling bebas). Aturan:
   a. Ikuti contracts/ PERSIS untuk bentuk JSON, path, kode error, key App Group.
   b. Hanya scope fase ini. Temuan lain → "Catatan handoff" di log.
   c. P0 sebelum P1. Nice to have hanya kalau file fase memintanya.
   d. Jangan menghapus atau melemahkan test supaya hijau.
   e. Tidak ada secret di file ter-commit. Nama file TIDAK BOLEH mengandung: token, secret, password, credential,
      apikey/api-key/api_key, .p8 (R5 §8). Secret lokal di backend/api/.dev.vars dan backend/.env (di-ignore).
   f. Tidak ada perintah destruktif (rm -rf di luar folder build, reset history, push --force) tanpa izin eksplisit.
      Pengecualian: `git push --force-with-lease` ke branch fase MILIKMU sendiri setelah rebase stacked (langkah 13).
   g. Keputusan produk yang tidak dijawab PRD/mandat/plan: pilih opsi paling sederhana yang tetap memenuhi
      "Selesai kalau" di PRD, catat di DECISIONS, lanjutkan. ID keputusan per track supaya worktree paralel tidak bentrok:
      app = `D-alief-A01, A02, …`, be = `D-alief-B01, …`, c = `D-alief-C01, …`, spike = `D-alief-S01, …` (nomor plan `D-alief-NN` hanya untuk fase 00).
   h. Aksi CLOUD (supabase link/db push/secrets, wrangler deploy/secret/hyperdrive, Storage bucket di cloud,
      App Store Connect, TestFlight): JANGAN dijalankan sendiri. Siapkan perintahnya, tulis checklist bernomor
      "LANGKAH MANUAL" (kotak [ ] per butir) di log fase, commit + push branch fase, set status [m] di PROGRESS, lalu berhenti.
      Sisa fase (Langkah kerja yang belum dicentang, lalu langkah 7–11) dikerjakan saat fase dilanjutkan (langkah 1, pilihan 1).
      Menunggu merge PR oleh Umar bukan LANGKAH MANUAL: buka PR, status [r], dan tulis syaratnya di TODO §D (mis. D8).
      Butir yang hanya menunggu pihak luar dan tidak memblokir kode (mis. capability C3, uji ulang di iPhone fisik untuk kode yang sudah lulus di simulator, Team ID):
      jangan pakai [m]; selesaikan fase, buka PR, status [r] + catatan "pending C3/B6" di Ringkasan, dan uji ulang
      butir itu di fase yang disebut file fase (mis. 15 atau 16).
      Pengecualian: fase yang HASIL-nya sendiri berasal dari uji perangkat (01S) memakai [m] sampai Alief menempel hasilnya.
   i. Test merah yang tidak jelas sebabnya → superpowers:systematic-debugging sebelum mengubah kode.
   j. Butuh perubahan kontrak, capability Xcode, model ShooShared, atau file milik tim lain → tulis usulan di
      DECISIONS + TODO §C, pakai placeholder, lanjutkan tanpa menyentuh file itu.
   k. `ios/ShooApp/Info.plist` dan `ios/ShooApp/Shoo.entitlements` DI-GENERATE XcodeGen dari `ios/project.yml`: jangan diedit
      (perubahan hilang di `xcodegen` berikutnya). Key baru = permintaan ke Umar (TODO C3). Satu-satunya edit project.yml
      yang diizinkan adalah diff D-alief-02 (fase 01), persisnya D-alief-24 + D-alief-28. Signing ke iPhone sendiri lewat L0:
      `ios/Config/Local.xcconfig` (gitignored, salin dari `.example`); bundle ID dan App Group per developer, jadi jangan
      hardcode `com.shoo.app` / `group.com.shoo.app`: pakai `AppGroup.id`, `Bundle.main.bundleIdentifier`, atau
      `$BUNDLE_ID` / `$APP_GROUP` dari `source plan/alief/ref/sim.sh`.
   l. ATURAN WAJIB SEMUA PEKERJAAN (D-alief-40): semua yang kita kerjakan (app, backend, plan, langkah manual, QA)
      HARUS mengikuti keamanan & privasi Apple (SECURITY §3, P1–P13; App Store Review Guidelines 5.1 + Apple Platform
      Security). App: privacy manifest, Keychain `AfterFirstUnlockThisDeviceOnly`, `os.Logger` dengan `privacy: .private`,
      izin just-in-time, tanpa SDK pihak ketiga. Backend: tidak ada PII/token di log, data minimum, data dihapus sesuai
      retensi dan `DELETE /devices/me` (P3), dan hapus/putus hubungan berlaku SEKETIKA (P13, tanpa salinan cache/CDN).
      Kalau ragu atau ada dua opsi: pilih yang paling menjaga privasi, catat di DECISIONS. Pelanggaran = temuan TINGGI.

7. GERBANG UI (wajib kalau diff menyentuh ios/ShooApp/**/*.swift yang menghasilkan tampilan):
   a. Build + jalankan di simulator iPhone (iOS Simulator tool: launch, screenshot). Ambil screenshot setiap layar
      yang berubah dalam English DAN Bahasa Indonesia, light + dark, dan Dynamic Type XL.
   b. Review dengan skill `apple-design` + agent `ecc:a11y-architect` (label VoiceOver, kontras, target sentuh ≥ 44 pt).
      Perbaiki semua temuan HIGH. Tabel temuan + path screenshot → log fase. Simpan screenshot di plan/alief/qa/img/ui-<FASE>/.
   c. Bandingkan dengan wireframe PRD §7 dan teks "Selesai kalau". Catat "re-skin saat desain final datang".

8. REVIEW. `superpowers:requesting-code-review` + agent bahasa:
   - app: `ecc:swift-reviewer`. be: `ecc:typescript-reviewer` + `ecc:database-reviewer` (migrasi/SQL).
   - `ecc:security-reviewer` WAJIB untuk fase 07, 08, 09, 10, 11, 12, 13, 14, 15 (auth, kode keluarga, akses data,
     screenshot, push, token di App Group).
   - Cek privasi Apple (6l) untuk SETIAP fase: diff dicocokkan dengan SECURITY §3 P1–P13; hasil per butir di log fase.
   Perbaiki semua temuan CRITICAL/HIGH. Ringkas temuan di log fase.

9. VERIFIKASI. `ecc:verification-loop` + `superpowers:verification-before-completion`: jalankan SEMUA perintah di bagian
   "Verifikasi" file fase. Build/typecheck merah → `ecc:swift-build-resolver` atau `ecc:build-error-resolver`.
   Tempel angka (test lulus/gagal, durasi, ukuran) ke log. Cek setiap butir DoD dan beri bukti (path test / screenshot).
   Klaim "selesai" hanya dengan bukti keluaran perintah.

10. DOKUMENTASI. Tulis/perbarui plan/alief/log/fase-<FASE>.md:
    Status · ringkasan planner · checklist langkah · file dibuat/diubah · hasil verifikasi · DoD + bukti ·
    gerbang UI (kalau ada) · temuan review · deviasi (+ link DECISIONS) · Placeholder aktif · LANGKAH MANUAL ·
    Catatan handoff. Perbarui baris fase ini saja di PROGRESS.md (+ tabel requirement P0 yang disentuh):
    status [r] + nomor PR setelah PR dibuka (BUKAN [x]; [x] hanya setelah merge, langkah 1).

11. COMMIT & PR. `superpowers:finishing-a-development-branch` (pilih opsi "push + PR", jangan merge sendiri).
    a. Commit kecil per langkah, pesan Conventional Commits (R5 §3), mis. `feat(ON-02): name input with 1–20 char validation`.
    b. Push branch fase. `gh pr create --base main --reviewer umarmuhdhor` dengan judul = `<PRD-ID>: <judul>` dan isi:
       ringkasan log, cara menguji, screenshot UI (path qa/img), checklist mandat yang dicentang, "Stacked on #N" bila ada,
       dan bagian "Contract proposals" kalau ada usulan ke Umar.
    c. Centang checkbox tugas di docs/mandates/alief.md di PR yang sama (diizinkan CODEOWNERS).
    d. JANGAN merge sendiri. Umar me-review dan merge.

12. SIMPAN SESI. Jalankan /ecc:save-session dengan nama "alief-<TRACK>-fase<FASE>".

13. LANJUT atau LAPOR.
    - FASE = auto: tulis ringkasan 3 baris, lalu KEMBALI ke langkah 1 untuk fase berikutnya track ini (fase [r] dilewati, bukan diulang).
      Berhenti hanya kalau: (a) LANGKAH MANUAL, (b) blocker P0 yang butuh keputusan user, (c) semua fase track selesai,
      (d) konteks hampir habis (simpan log + /ecc:save-session dulu).
      Sebelum fase baru, SINKRON:
      1) `git fetch origin`. Untuk setiap PR fase track ini yang sudah di-merge sejak sinkron terakhir:
         rebase branch stacked di atasnya ke `origin/main`:
         `git rebase --onto origin/main <branch-fase-yang-sudah-merge> <branch-fase-berikutnya>`
         lalu `git push --force-with-lease` ke branch fase milikmu sendiri.
      2) RESOLVE PLACEHOLDER: `grep -rn "TODO(sync" ios/ShooApp backend` → ganti yang prasyaratnya sudah ada di main,
         jalankan test, commit "chore(sync): replace <x> placeholder".
    - FASE = nomor: laporan ringkas (maks 15 baris), baris terakhir PERSIS
      "Lanjut: TRACK <x> · FASE <nomor berikutnya>", lalu berhenti.
</langkah>

<batasan>
- Jangan mengarang API Apple, Supabase, Cloudflare, atau kontrak tim lain. Fakta diambil dari dokumentasi resmi
  (skill ecc:documentation-lookup / context7) atau kode yang benar-benar kamu baca (sebutkan path:baris).
  Yang belum pasti ditandai "BELUM DIVERIFIKASI" dan diuji di fase itu.
- Jangan menambah fitur di luar PRD/mandat. Jangan ganti stack (ARCHITECTURE.md) tanpa entri DECISIONS.
- Jangan pernah mengirim pesan atas nama Alief ke Umar/Imelda. Tulis isi pesannya di TODO §C.
- Kalau konteks mau habis: simpan progres ke log fase dan /ecc:save-session dulu, baru berhenti.
</batasan>
```

---

## Tabel cepat

| Baris | Fase | Track | Model | Review keamanan |
|---|---|---|---|---|
| `FASE: 01` | Fondasi app + target test | app | Sonnet 5.5 | – |
| `FASE: 01S` | Spike S1/S2 di iPhone Alief | spike | Sonnet 5.5 | – |
| `FASE: 02` | Onboarding ON-01..05 | app | Sonnet 5.5 | – |
| `FASE: 03` | Detail DT-01..06 | app | Sonnet 5.5 | – |
| `FASE: 04` | Protected PR-04/05 | app | Sonnet 5.5 | – |
| `FASE: 05` | Guardian & Family GD-01/02/03/05 | app | Sonnet 5.5 | – |
| `FASE: 06` | Profile PF-01 | app | Sonnet 5.5 | – |
| `FASE: 06Q` | QA-A | app | Sonnet 5.5 | – |
| `FASE: 07` | Fondasi backend + auth + blocklist awal | be | Opus 5.5 | ✓ |
| `FASE: 08` | Family | be | Opus 5.5 | ✓ |
| `FASE: 09` | Scans + screenshot | be | Opus 5.5 | ✓ |
| `FASE: 10` | Verdicts + blocklist | be | Opus 5.5 | ✓ |
| `FASE: 11` | Push APNs | be | Opus 5.5 | ✓ |
| `FASE: 12` | Retensi + hardening + deploy | be | Opus 5.5 | ✓ |
| `FASE: 13` | ApiRepository + sesi App Group | c | Opus 5.5 | ✓ |
| `FASE: 14` | Pairing GD-04, PR-01/02/03 | c | Opus 5.5 | ✓ |
| `FASE: 15` | Push tap + validasi GD-06/07 | c | Opus 5.5 | ✓ |
| `FASE: 16` | QA-E2E + fixbug | c | Sonnet 5.5 (Opus untuk fix keamanan) | ✓ untuk fix |
