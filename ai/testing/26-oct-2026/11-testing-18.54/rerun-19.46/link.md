# Link yang diuji (testing 15, 26 Okt 2026, 19.46)

> **Jangan dibuka di browser.** Ini halaman phishing/scam. Halaman hanya diambil sekali lewat `ai/eval/tools/capture.mjs` (GET statis, tanpa JavaScript, tanpa cookie, host publik saja). Link ditulis *defanged*; untuk mengembalikannya ganti `hxxp` → `http` dan `[.]` → `.`.

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://d33wubrfki0l68[.]cloudfront[.]net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123[.]html` |
| Domain | `d33wubrfki0l68.cloudfront.net` |
| Waktu pengambilan | 2026-10-26T11:46:03.306Z |
| Cara ambil | `capture.mjs` (GET statis, UA iPhone Safari) |
| Ukuran HTML | 6984 byte |
| Catatan penguji | ulang testing 11: glm-5.3-flash via env override (ai/.env tidak diubah) |
| Status redaksi | `redacted: false`. Email dimasking `[email]` oleh capture; **belum dicek manual** untuk data pribadi |

## Yang diambil dari halaman (snapshot, sama dengan yang dikirim extension)

| Field | Isi |
|---|---|
| `title` | DHL EXpress |
| `lang` | en |
| `text` | 87 karakter: `DHL Express Enter your credentials to proceed email Email address lock Password Sign In` |
| `forms` | 1 form, 2 field |
| `imageAlts` | - |

Field form:

| type | name | id | label | placeholder | autocomplete |
|---|---|---|---|---|---|
| email | email | email | Email address | Email address | email |
| password | password | password | Password | Password | current-password |

## Hasil layer 1 sampai 3 (tanpa LLM)

| Layer | Hasil | Waktu |
|---|---|---|
| 1–2 (detector di extension, disimulasikan; blocklist layer 1 tidak ikut) | 0 sinyal | 0,81 ms |
| 3 (aturan form + isi; RDAP dimatikan) | `asks_password:15` (evidence `password`) | 14,9 µs/panggilan |
| Skor layer 3 | **15** (peringatan ≥ 30, tinggi ≥ 50, blokir ≥ 80) | |
| Lolos gerbang LLM (bukan resmi, form ≥ 1 field, skor ≥ 15) | **ya** | |

## Yang dikirim ke LLM (setelah disanitasi, sebelum dikirim)

```json
{
  "site": "cloudfront.net",
  "title": "DHL EXpress",
  "fields": [
    {
      "type": "email",
      "label": "Email address"
    },
    {
      "type": "password",
      "label": "Password"
    }
  ],
  "brands": [],
  "rules": [
    "asks_password"
  ]
}
```

