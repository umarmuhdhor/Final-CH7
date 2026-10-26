# Link yang diuji (testing 09, 26 Okt 2026, 16.24)

> **Jangan dibuka di browser.** Ini halaman phishing/scam. Halaman hanya diambil sekali lewat `ai/eval/tools/capture.mjs` (GET statis, tanpa JavaScript, tanpa cookie, host publik saja). Link ditulis *defanged*; untuk mengembalikannya ganti `hxxp` → `http` dan `[.]` → `.`.

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://ibank[.]klikbca[.]com/` |
| Domain | `klikbca.com` |
| Waktu pengambilan | 2026-10-26T08:24:20.886Z |
| Cara ambil | `capture.mjs` (GET statis, UA iPhone Safari) |
| Ukuran HTML | 17744 byte |
| Catatan penguji | - |
| Status redaksi | `redacted: false`. Email dimasking `[email]` oleh capture; **belum dicek manual** untuk data pribadi |

## Yang diambil dari halaman (snapshot, sama dengan yang dikirim extension)

| Field | Isi |
|---|---|
| `title` | klikBCA Individual |
| `lang` | - |
| `text` | 1109 karakter: `[ HOME ] USER ID dan PIN Internet Banking dapat diperoleh pada saat Anda melakukan Registrasi Internet melalui ATM BCA. Untuk informasi lebih lanjut hubungi Hal…` |
| `forms` | 2 form, 2 field |
| `imageAlts` | - |

Field form:

| type | name | id | label | placeholder | autocomplete |
|---|---|---|---|---|---|
| text | txt_user_id | txt_user_id |  |  | off |
| password | txt_pswd | txt_pswd |  |  | off |

## Hasil layer 1 sampai 3 (tanpa LLM)

| Layer | Hasil | Waktu |
|---|---|---|
| 1–2 (detector di extension, disimulasikan; blocklist layer 1 tidak ikut) | 0 sinyal | 0,28 ms |
| 3 (aturan form + isi; RDAP dimatikan) | 0 sinyal | 80,7 µs/panggilan |
| Skor layer 3 | **0** (peringatan ≥ 30, tinggi ≥ 50, blokir ≥ 80) | |
| Lolos gerbang LLM (bukan resmi, form ≥ 1 field, skor ≥ 15) | **tidak** | |

## Yang dikirim ke LLM (setelah disanitasi, sebelum dikirim)

```json
{
  "site": "klikbca.com",
  "title": "klikBCA Individual",
  "fields": [
    {
      "type": "text",
      "label": "txt_user_id"
    },
    {
      "type": "password",
      "label": "txt_pswd"
    }
  ],
  "brands": [
    "BCA"
  ],
  "rules": []
}
```

