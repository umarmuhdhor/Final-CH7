# Layer 5: database feedback Guardian

Status: **usulan, menunggu jawaban #241**. Jangan dikoding sebelum issue itu terjawab. · Disepakati Imelda, 3 Nov 2026 (D-imelda-51)

Layer 5 bukan lagi hoaks. Hoaks tetap di luar MVP, nomornya ditentukan nanti. Layer 5 tidak memunculkan `Signal`: isinya database di `backend/` untuk mencatat keputusan Guardian dan menyediakan data belajar.

## Alur

1. Domain ada di blocklist: layer 1 memblokir untuk semua user. Block screen menampilkan teks statis: sumber list (`shoo`/`public`) dan tanggal masuk.
2. Hanya Guardian yang bisa melapor, di Detail app (scan miliknya atau milik Protected yang terhubung). Protected menunggu.
3. Y: link terbuka lagi. Block screen membuka ulang di Safari lewat polling yang sudah ada, tanpa WebView baru.
4. N: tetap diblokir, `notes` wajib.
5. Job mingguan menjalankan LLM atas laporan baru. Hasilnya hanya disimpan.

## Aturan Y/N

- Y = Guardian setuju link ini aman. N = setuju tetap diblokir. Sama dengan `safe` / `not_safe` di `POST /verdicts`.
- `notes` (di catatan awal bernama `verification`) = catatan Guardian. Wajib saat N, opsional saat Y.
- Berlaku per link: `origin + path` (`shareableUrl`), bukan per domain.
- Tanpa masa berlaku. Semua layer di-skip untuk link yang diberi Y (perilaku `safe` sekarang, `pipeline.js`). Risikonya diterima: link yang nanti diretas tidak terdeteksi.
- Guardian bisa mengubah keputusan (Ubah). Blokir mengikuti keputusan terakhir.
- Hanya scan `blocked` dan `warning`. Skor di bawah 30 tidak pernah sampai ke backend, jadi scam yang lolos tidak bisa dilaporkan lewat sini (fitur terpisah).
- Chrome di luar scope: belum ada app, pairing, dan verdict.

## ID

Ikut skema Alief: `devices.id` (text uuid), dipakai sebagai `owner_id` (pemilik scan) dan `by_device_id` (Guardian yang memutuskan). `by_name` hanya nama tampilan: tidak unik, tidak diverifikasi, jangan dipakai sebagai penanda orang.

"Orang ini acc atau tidak" dijawab dari `verdicts` (`by_device_id` + `url`): `safe` = acc, `not_safe` = tidak, tidak ada baris = belum memutuskan.

## Data

### Tabel user: `verdicts` yang diperluas

| Kolom | Isi | Retensi |
|---|---|---|
| `owner_id`, `url` | Primary key baru (sekarang `owner_id`, `domain`) | Sampai device dihapus atau family link putus |
| `domain` | Tetap ada, untuk antrean global | Sama |
| `value` | `safe` / `not_safe` | Sama (D-alief-14: tidak ikut 14 hari) |
| `scan_id`, `by_device_id`, `by_name`, `decided_at` | Sudah ada | Sama |
| `notes` | Catatan Guardian, teks bebas | **Dihapus setelah 14 hari** |

Baris Y/N sengaja tidak terhapus 14 hari. Kalau terhapus, link terblokir lagi di hari ke-15.

### Tabel sistem: data belajar, permanen

| Kolom | Isi |
|---|---|
| `url` | `origin + path`. Kalau path punya segmen panjang atau acak (kemungkinan token), simpan domain saja |
| `domain` | Registrable domain |
| `signals` | L1–L4: `id`, `layer`, `weight` saja, tanpa `evidence` |
| `yes_count`, `no_count` | Guardian unik yang memberi Y / N |
| `result_llm` | Hasil job mingguan terbaru |
| `candidate` | `true` kalau LLM menilai `legit` untuk domain di blocklist |

Tanpa `device_id`, `by_name`, `notes`, `evidence`.

Counter hanya menghitung keputusan pertama tiap Guardian. Tidak berubah saat Guardian ganti pilihan, device dihapus, atau family link putus. Akibatnya counter bisa tertinggal dari keputusan terbaru: baca sebagai "berapa orang pernah melapor", bukan status sekarang.

## LLM

- Job mingguan di backend. Jalan kalau ada minimal 10 laporan baru **total** dalam batch. Kurang dari itu, laporan terbawa ke minggu berikutnya.
- `notes` dan replica hanya ada 14 hari. Laporan yang tertahan lebih lama dinilai dari signals saja.
- Backend memanggil `POST /review` di `ai/`:
  - Auth: secret server, bukan token device (AI service tidak punya tabel device).
  - Input: `url`, `domain`, `signals`, `notes`, teks replica dengan batas ukuran. Teks halaman dan `notes` ditandai sebagai data tidak tepercaya di prompt.
  - Output: `{ result: "scam" | "legit" | "unsure", confidence, reason }`, tanpa `Signal`.
  - Stateless, tanpa log, seperti `/analyze`. Kuota sendiri, tidak memakai `LLM_DAILY_CAP` layer 4.
  - Gagal: retry maksimal 3 kali, lalu `result_llm` tetap kosong.
- **Hasil LLM tidak mengubah blokir apa pun.** Tidak ada reviewer L5 dan tidak ada penghapusan otomatis dari daftar global. Daftar device tanpa login, jadi 10 device palsu plus prompt injection bisa mengeluarkan domain scam untuk semua user kalau LLM diberi hak itu. User tidak terjebak, karena Y dari Guardian sudah membuka link untuk keluarganya.
- "Train" = Imelda memakai hasil mingguan untuk tuning bobot dan prompt lewat PR ke `ai/`, dengan laporan precision/recall (`ai/eval/`). Tidak ada contoh yang otomatis masuk prompt L4.

### Terbuka: data ke penyedia LLM

Input `/review` bertentangan dengan pembatas yang berlaku. D-imelda-27 hanya mengizinkan host, title, label field, dan id aturan ke LLM. Penyedia sekarang (D-imelda-36, A6) belum punya kebijakan retensi yang bisa diverifikasi. `notes` bisa berisi data pribadi dan replica berisi teks halaman. Usulan: `notes` dan replica baru dikirim setelah ada penyedia dengan zero data retention tertulis. Sebelum itu `/review` hanya menerima `domain` dan `signals`. Keputusan di #241.

## Tidak berubah

Antrean `not_safe` ke `blocklist_entries` tetap jalan dan tetap butuh persetujuan Alief atau Umar (`contracts/api.md`). Trigger dari jumlah Y tidak dibuat.

## Yang perlu dikerjakan per pemilik

| Pemilik | Pekerjaan |
|---|---|
| Umar | `contracts/`: arti layer 5, `verdicts` per link, `notes`, `GET /verdicts?url=`. Extension: lookup per link, block memory (`block-memory.js`: `safe` sekarang membersihkan semua halaman di domain). Privasi: tabel permanen vs aturan 14 hari, privacy policy, label App Store |
| Alief | Migrasi `verdicts` (termasuk baris lama yang per domain), tabel sistem, hapus `notes` 14 hari, job mingguan, input `notes` di Detail |
| Imelda | `POST /review`, prompt, kuota, fixture, tes di `ai/` |

## Kriteria tes

Simulator saja, jangan iPhone pribadi.

1. Block L1, Guardian memberi Y, link terbuka ulang.
2. Path lain di domain yang sama tetap terblokir.
3. N tanpa `notes` ditolak.
4. `notes` terhapus setelah 14 hari, Y/N tetap ada.
5. Hapus device tidak mengubah tabel sistem, dan tidak ada identitas di dalamnya.
6. Batch di bawah 10 laporan tidak jalan.
7. Halaman berisi prompt injection tidak mengubah status blokir.
