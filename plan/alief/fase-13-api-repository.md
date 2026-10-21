# Fase 13 — ApiRepository + sesi App Group

| Field | Nilai |
|---|---|
| Track | c · repo utama |
| Branch | `feat/APP-api-repository` |
| Prasyarat | 06Q dan 12 `[x]` (G5, G6) |
| Requirement | Mandat Fase C butir 1–2; ON-02/03 dengan server asli |
| Model | Opus 5.5 · `ecc:swift-concurrency-6-2`, `ecc:swift-protocol-di-testing`, `ecc:api-design` |
| Fase berikutnya | 14 |

## Tujuan

App memakai backend asli tanpa mengubah view: `ApiRepository` menggantikan `MockRepository`, onboarding mendaftarkan device, dan sesi ditulis ke App Group supaya extension Umar bisa memanggil API.

## Bacaan wajib

- `contracts/api.md`, `contracts/app-group-keys.md`, `ShooShared/AppGroup.swift`
- `ref/R3` §1–§4, `ref/R5` §6, `SECURITY.md` T3

## Output

- `Data/APIClient.swift` (URLSession, Bearer, `JSONDecoder.shoo`/`JSONEncoder.shoo`, decode `{ error: { code, message } }` → `RepositoryError`)
- `Data/ApiRepository.swift` (semua operasi protocol)
- `Data/SessionStore.swift` (Keychain untuk app + tulis key App Group: `device.id`, `device.token`, `device.mode`, `device.name`, `guardian.name`, `api.baseURL`, `ai.baseURL`)
- Konfigurasi base URL (Debug lokal, Release cloud) sesuai R5 §6; `ai.baseURL` dari Imelda (placeholder `TODO(sync:imelda)` sampai ada)
- Test: `APIClient` dengan `URLProtocol` stub (sukses, error kontrak, 401 → sesi rusak), `SessionStore` menulis semua key App Group (pakai suite uji), pemilihan repository lewat `AppEnvironment`

## Langkah kerja

1. `APIClient` + test stub untuk setiap endpoint.
2. `ApiRepository` memenuhi protocol; `MockRepository` tetap untuk preview dan test UI (`-UITestMock` launch argument).
3. Onboarding (fase 02) memanggil `registerDevice` asli → `SessionStore.save` → App Group. `guardian.name` diisi setelah join (fase 14).
4. 401 dari server → tampilkan layar "Session expired" dengan tombol mulai ulang onboarding (P1, cukup pesan jelas untuk MVP).
5. Uji manual melawan `wrangler dev` lokal dari simulator: onboarding Guardian + Protected, Activity kosong, Profile ganti nama/bahasa.
6. `ecc:security-reviewer` fokus T3 (token tidak di-log, tidak di UserDefaults standar).

## Verifikasi

```bash
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM"
# simulator + backend lokal
(cd backend/db && supabase start) && (pnpm -C backend/api dev &)
```

## Kriteria selesai (DoD)

- [ ] Tidak ada view yang berubah karena pergantian repository (diff `Features/` hanya injeksi).
- [ ] Semua key App Group terisi setelah onboarding (test + cek `defaults` suite di simulator).
- [ ] Alur onboarding → Shield berjalan melawan backend lokal (screenshot).
