# Fase 13 — ApiRepository + sesi App Group

| Field | Nilai |
|---|---|
| Track | c · repo utama |
| Branch | `feat/APP-api-repository` |
| Prasyarat | 06Q dan 12 `[x]` = semua PR track app dan be MERGED (G5, G6; dicek `gh pr view <no> --json state -q .state`) |
| Requirement | Mandat Fase C butir 1–2; ON-02/03 dengan server asli |
| Model | Opus 5.5 · `ecc:swift-concurrency-6-2`, `ecc:swift-protocol-di-testing`, `ecc:api-design` |
| Fase berikutnya | 14 |

## Tujuan

App memakai backend asli tanpa mengubah view: `ApiRepository` menggantikan `MockRepository`, onboarding mendaftarkan device, dan sesi ditulis ke App Group supaya extension Umar bisa memanggil API.

## Bacaan wajib

- `contracts/api.md`, `contracts/app-group-keys.md`, `ShooShared/AppGroup.swift`
- `ref/R3` §1–§4, `ref/R5` §6, `SECURITY.md` T3, `log/DECISIONS.md` D-alief-21, jawaban TODO C12 (kalau ada)

## Output

- `Data/APIClient.swift` (URLSession, Bearer, `JSONDecoder.shoo`/`JSONEncoder.shoo`, decode `{ error: { code, message } }` → `RepositoryError`)
- `Data/ApiRepository.swift` (semua operasi protocol)
- `Data/SessionStore.swift` (Keychain untuk app + tulis key App Group lewat konstanta `AppGroup.Key` di `ShooShared`: `device.id`, `device.token`, `device.mode`, `device.name`, `guardian.name`, `api.baseURL`, `ai.baseURL`). Menyimpan juga guardian (nama + `avatarId`) untuk PR-04/PF-01. Aturan: tulis ulang `device.name` setelah `updateMe(name:)`; hapus `guardian.name` setelah `leaveGuardian()`, 404/`not_found` di endpoint keluarga, atau `GET /devices/me` → `guardian: null` (kalau C12 disetujui)
- `App/AppConfig.swift`: base URL `#if DEBUG` = `http://localhost:8787` (simulator) / `#else` = URL Worker cloud (R5 §6, bukan Info.plist); `ai.baseURL` dari Imelda (placeholder `TODO(sync:imelda)` sampai ada)
- Test: `APIClient` dengan `URLProtocol` stub (sukses, error kontrak, 401 → sesi rusak), `SessionStore` menulis semua key App Group (pakai suite uji), tulis ulang `device.name`, hapus `guardian.name` di tiga kondisi, pemilihan repository lewat `AppEnvironment`

## Langkah kerja

1. `APIClient` + test stub untuk setiap endpoint.
2. `ApiRepository` memenuhi protocol; `MockRepository` tetap untuk preview dan test UI (`-UITestMock` launch argument).
3. Onboarding (fase 02) memanggil `registerDevice` asli → `SessionStore.save` → App Group. Kalau bahasa app = ID, langsung `PATCH /devices/me { language: "id" }` (POST tidak membawa `language`). `guardian.name` diisi setelah join (fase 14).
4. 401 dari server → tampilkan layar "Session expired" dengan tombol mulai ulang onboarding (P1, cukup pesan jelas untuk MVP).
5. Uji manual melawan `wrangler dev` lokal dari simulator: onboarding Guardian + Protected, Activity kosong, Profile ganti nama/bahasa.
6. `ecc:security-reviewer` fokus T3 (token tidak di-log, tidak di UserDefaults standar).

## Verifikasi

```bash
source plan/alief/ref/sim.sh
(cd ios && xcodegen)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,name=$SIM"
# simulator + backend lokal
(cd backend/db && supabase start) && (pnpm -C backend/api dev > /tmp/shoo-dev.log 2>&1 &) && npx wait-on tcp:8787
# cek App Group (AppGroup.id = group.com.shoo.app): container data app di simulator
find "$(xcrun simctl get_app_container booted com.shoo.app groups 2>/dev/null | awk '{print $2}')" -name "group.com.shoo.app.plist" 2>/dev/null | head -1 | xargs -I{} plutil -p {}
```

## Kriteria selesai (DoD)

- [ ] Tidak ada view yang berubah karena pergantian repository (diff `Features/` hanya injeksi).
- [ ] Semua key App Group terisi setelah onboarding (test + cek di simulator); `device.name` ikut berubah setelah ganti nama; `guardian.name` hilang setelah disconnect (test).
- [ ] Alur onboarding → Shield berjalan melawan backend lokal (screenshot).
