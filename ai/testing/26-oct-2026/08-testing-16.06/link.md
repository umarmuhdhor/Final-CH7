# Link yang diuji (testing 08, 26 Okt 2026, 16.06)

> **Jangan dibuka di browser.** Ini halaman phishing/scam. Halaman hanya diambil sekali lewat `ai/eval/tools/capture.mjs` (GET statis, tanpa JavaScript, tanpa cookie, host publik saja). Link ditulis *defanged*; untuk mengembalikannya ganti `hxxp` → `http` dan `[.]` → `.`.

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://bantuannbansos2026[.]blogspot[.]com/` |
| Domain (defanged) | `bantuannbansos2026[.]blogspot[.]com` |
| Waktu pengambilan | 2026-10-26T08:06:28.976Z |
| Cara ambil | `capture.mjs` (GET statis, UA iPhone Safari) |
| Ukuran HTML | 19880 byte |
| Catatan penguji | - |
| Status redaksi | `redacted: false`. Email dimasking `[email]` oleh capture; **belum dicek manual** untuk data pribadi |

## Yang diambil dari halaman (snapshot, sama dengan yang dikirim extension)

| Field | Isi |
|---|---|
| `title` | CEK STATUS PENDAFTARAN |
| `lang` | id |
| `text` | 1216 karakter: `🛡️ MOHON TUNGGU SEBENTAR Menghubungi server Telegram... MASUKKAN DATA ANDA DENGAN BENAR MASUKKAN DATA ANDA DENGAN BENAR MASUKKAN DATA ANDA DENGAN BENAR Pilih P…` |
| `forms` | 1 form, 5 field |
| `imageAlts` | `Banner` |

Field form:

| type | name | id | label | placeholder | autocomplete |
|---|---|---|---|---|---|
| select |  | provinsi |  |  |  |
| tel |  | nomor |  | 123456789 |  |
| checkbox |  | checkTerms |  |  |  |
| tel |  | otp |  | ••••• |  |
| password |  | pw |  | KATA SANDI |  |

## Hasil layer 1 sampai 3 (tanpa LLM)

| Layer | Hasil | Waktu |
|---|---|---|
| 1–2 (detector di extension, disimulasikan; blocklist layer 1 tidak ikut) | 0 sinyal | 1,35 ms |
| 3 (aturan form + isi; RDAP dimatikan) | `asks_otp:25` (evidence `otp`), `asks_password:15` (evidence `pw`) | 94,2 µs/panggilan |
| Skor layer 3 | **40** (peringatan ≥ 30, tinggi ≥ 50, blokir ≥ 80) | |
| Lolos gerbang LLM (bukan resmi, form ≥ 1 field, skor ≥ 15) | **ya** | |

## Yang dikirim ke LLM (setelah disanitasi, sebelum dikirim)

```json
{
  "site": "blogspot.com",
  "title": "CEK STATUS PENDAFTARAN",
  "fields": [
    {
      "type": "select",
      "label": "provinsi"
    },
    {
      "type": "tel",
      "label": "[number]"
    },
    {
      "type": "checkbox",
      "label": "checkTerms"
    },
    {
      "type": "tel",
      "label": "•••••"
    },
    {
      "type": "password",
      "label": "KATA SANDI"
    }
  ],
  "brands": [],
  "rules": [
    "asks_otp",
    "asks_password"
  ]
}
```

