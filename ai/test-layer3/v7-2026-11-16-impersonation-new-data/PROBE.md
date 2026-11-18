# PROBE: apakah halaman mengirim input user ke pihak lain? (tanpa mengetik, tanpa LLM)

Pertanyaan awal: scam tidak punya database, jadi menerima input apa saja. Bisa sistem kita "input duluan" untuk tahu halaman itu legit atau tidak?

Jawaban singkat: input duluan sebagai sinyal utama rapuh (situs legit juga menerima apa saja di langkah awal, kit scam sering menolak percobaan pertama, ada cloaking, dan percobaan kirim bisa membuat efek samping di pihak ketiga). Yang bisa diukur murah dan aman: **ke mana halaman mengirim apa yang diketik user**, dibaca dari HTML mentah. Tidak ada yang diketik atau diklik.

## Kasus pemicu: `simgratisonine[.]blogspot[.]com/?m=1`

Dibaca dari DOM hasil render (Chrome headless, UA iPhone):

- Tidak ada `<form>`. Input nomor, OTP, dan password dikirim oleh JS.
- JS memanggil `fetch` ke `api.telegram.org/bot…/sendMessage`. Token bot dan chat id tertanam di sumber halaman (tidak dicatat di sini).
- Validasi OTP hanya `o.length < 5`, password hanya `!w`. Tidak ada pengecekan ke server mana pun, sesuai dugaan.
- Blogspot tidak punya backend. Form kredensial di sana pasti mengirim ke pihak ketiga.

## Cara ukur

`probe_static.mjs`: satu GET statis per halaman (tanpa JavaScript, tanpa cookie, redirect dicek `assertPublicUrl`, maksimal 500 kB). Halaman adalah data penyerang: tidak dijalankan. Yang disimpan hanya id dan boolean; URL, host, token tidak dicetak.

Flag utama:

- `collector`: HTML menyebut endpoint penampung data (Telegram bot, Discord webhook, Slack, Google Apps Script, Google Forms `formResponse`, Formspree/formsubmit/getform/web3forms/emailjs, Firebase).
- `offsiteAction`: `<form action>` menuju situs lain.
- `scriptOnlyCollect`: ada input sensitif (password, tel, email, otp, pin, nik) tapi tidak ada `<form>`.

## Hasil

Phishing Indonesia terbaru (`fresh`, feed Shoo 2026-11-09 + manual): 1.099 scam, 1.084 bisa diambil.

| Flag | Scam | Persen |
|---|---|---|
| `collector` | 87 | 8,0% |
| `collector` + input sensitif | 78 | 7,2% |
| dari itu: formservice | 69 | |
| dari itu: telegram / gas / discord / firebase | 13 / 3 / 1 / 1 | |
| `offsiteAction` | 74 | 6,8% |
| `scriptOnlyCollect` | 14 | 1,3% |

Legit pembanding (sangat kecil, jujur saja):

| Set | Bisa diambil | `collector` | `offsiteAction` |
|---|---|---|---|
| `fresh` manual_link_aman | 17 | 0 | 0 |
| Kaggle normal (sampel 800) | 68 | 0 | 5 (7,4%) |
| Kaggle scam (sampel 800) | 65 | 1 | 2 |

Kaggle hampir semua sudah mati (68 dan 65 dari 800 yang hidup), jadi pembanding ini lemah.

Tumpang tindih dengan deteksi yang ada (857 scam `fresh` yang cocok dengan `results.jsonl`): 59 lolos dari aturan Imelda dan Alief sekaligus. Dari 59 itu, 22 (37%) punya `collector`. Semua 22 itu formservice atau form ke luar situs. Telegram/Discord/GAS dan `scriptOnlyCollect` tidak menambah apa pun: 0 dari 59, karena sudah tertangkap.

## Kesimpulan

1. `offsiteAction` tidak membedakan: legit 7,4% vs scam 6,8%. Jangan dipakai.
2. `collector` presisi tinggi di data yang ada (0 dari 85 legit), tapi recall hanya sekitar 8%. Itu sinyal pelengkap, bukan pengganti model. Batas atas false positive yang bisa diklaim: dengan 0 dari 85, sekitar 3,5% (rule of three), terlalu longgar untuk keputusan.
3. Telegram/Discord/GAS (sekitar 1,6% dari scam) hampir pasti jarang di legit, tapi sudah tertangkap sinyal lain. Halaman seperti blogspot tadi (lolos dari aturan, skor model tipis) adalah tempat sinyal ini bisa menambah, tapi itu belum terbukti di angka: di `fresh`, 0 dari 59 yang lolos punya Telegram.
4. Risiko false positive nyata: formservice (Formspree, emailjs, Google Forms) dipakai form kontak usaha kecil yang sah. Ini kelas FP yang sama dengan `LATIH-ULANG-smallbiz.md`. Firebase dipakai banyak aplikasi legit, jadi lemah.

## Belum diukur

- Pembanding legit hidup dalam jumlah besar (ribuan halaman bernilai form). Tanpa itu, FP `collector` formservice tidak bisa diklaim kecil.
- Tumpang tindih dengan pipeline tanpa LLM terbaru (model v2 + v3g + umur domain). Yang dipakai di atas hanya aturan Imelda dan Alief lama.
- Skrip eksternal (`<script src>`) tidak dibaca. Halaman JS-only yang menaruh pengirim data di file terpisah lolos.
- Sisi on-device: snapshot ekstensi hanya membaca teks tampak, bukan teks `<script>`. Perlu diubah dulu kalau sinyal ini dipakai.

## Menjalankan ulang

```bash
node probe_static.mjs                                   # fresh -> .hasil/probe/static.jsonl
node probe_static.mjs --in <pages.jsonl> --out kaggle --sample 800
```
