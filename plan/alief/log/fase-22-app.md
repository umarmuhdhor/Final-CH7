# Log fase 22 — Snapshot salinan halaman (app, 22b)

- **Model:** Claude Opus 5.5. Sesi track app fase 19–26 (D-alief-C29), 1 Nov 2026.
- **Plan:** `fase-22-performance.md` (PR #207, branch `docs/alief-plan-19-26`). Sisi backend (22a) ada di `log/fase-22.md` (track be, PR #212/#215); file ini terpisah supaya tidak bentrok.
- **Keputusan K:** rekomendasi R8 §c / file fase (D-alief-C29): K7 (a) lebar gambar 390 pt, jendela 1800 pt; K8 (a) satu frame (lihat S7); K9 (a) hapus kode mati. D-alief-A46.
- **Stacked** di 23a (#214): `PageCopyTests` (`ReplicaSnapshotTests`) ada di dalam `extension WebKitTests` dari 23a.

## Status

| Sub-fase | Branch | PR | Status |
|---|---|---|---|
| 22b | `fix/DT-04-snapshot-perf` | lihat PR | [r] PR terbuka |
| 22c favicon cache | – | – | opsional, tidak dikerjakan sesi ini |

## Spike (simulator sendiri: "Shoo Track App SE" iPhone SE 3 iOS 26.5, "Shoo Track App Pro Max" iPhone 17 Pro Max iOS 26.5)

Simulator milik sesi ini (bukan "Shoo QA SE" / Pro Max bersama di plan, supaya tidak bentrok dengan sesi lain). Angka dari `Tests/DetailPerfTests.swift` (opt-in `TEST_RUNNER_SHOO_PERF=1`), 5 pengulangan, HTML 3 MB (batas loader). "Sebelum" = branch ini dengan `imageWidth` 200 / `windowHeight` 3000 dipasang sementara.

| Ukur | Sebelum (200 pt × 3000 pt) | Sesudah (390 pt × 1800 pt) |
|---|---|---|
| S6 `render` 3 MB: puncak memori fisik proses app | 67,6 MB | 67,8 MB |
| S6 `render` 3 MB: waktu | 1,25 s | 1,26 s |
| `prepare` 3 MB (lock + meta, di luar main actor) | 3,3 ms | 3,2 ms |
| S8 loader 3 MB (stub `URLProtocol`) | 109 ms, puncak 47,5 MB | 109 ms, puncak 44,3 MB (tanpa salinan `Data`) |
| S7 WebContent (RSS maks proses `com.apple.WebKit.WebContent` baru, `ps`) | 261 MB | 261 MB |

- Gerbang K7 ("puncak footprint ≤ baseline + 60 MB di SE"): lulus (+0,2 MB). Bitmap snapshot lebih besar (SE @2x: 780 × 3600 px ≈ 11 MB vs 400 × 6000 px ≈ 10 MB) tetapi tidak terlihat di puncak proses app.
- S7: RSS di simulator memakai memori Mac dan menghitung pustaka bersama, jadi bukan footprint perangkat; angkanya sama sebelum/sesudah dan bisa tercampur proses WebContent sesi lain. Tidak ada `webViewWebContentProcessDidTerminate` selama uji. K8 tetap (a); ukur ulang di iPhone fisik (LANGKAH MANUAL 7 fase 22).
- S8: 109 ms sedikit di atas ambang 100 ms (simulator di CPU Mac; SE asli lebih lambat). Langkah plan: satu buffer tanpa `Data` perantara (`String(bytes:encoding:)`): puncak −3 MB, waktu sama (biaya utamanya iterasi `AsyncBytes` per byte). Membaca per potongan butuh delegate `URLSession` sendiri; tidak dikerjakan (lihat Catatan handoff).
- S5 (`SWIFT_STRICT_CONCURRENCY=complete`, tanpa ubah `project.yml`): 3 peringatan di `Features/Detail`, semua diperbaiki: `ReplicaMeta.leakedToken` (`Regex` konstan → `nonisolated(unsafe)`), `ReplicaSnapshot.first`/`Race` (`T: Sendable`). Hasil ulang: 0 peringatan di `Features/Detail`.

## Perubahan

- `Features/Detail/ReplicaSnapshot.swift`: `imageWidth = renderWidth` (390 pt), `windowHeight = 1800` (K7 a). `Race<T: Sendable>`.
- `Features/Detail/ReplicaWebView.swift`: hapus `struct ReplicaWebView` (tanpa pemakai), `scrollsToFocusOnFinish`, `scrollToFocus`, `focusOffset`, parameter `focusY` di `ReplicaWebController` (K9 a). `ReplicaRules`, `LockedWebView`, `ReplicaWebController` tetap. `import SwiftUI` → `UIKit`.
- `Features/Detail/DetailView.swift`: `nonisolated static func prepare(_:) async` menggantikan `Task.detached` (C14, bug d6): pembatalan Detail sampai ke `prepare`; batal sebelum/di antara dua pindai → `(nil, nil)`, tanpa `render`.
- `Features/Detail/ReplicaLoader.swift`: `String(bytes:encoding:)` langsung dari buffer.
- `Features/Detail/ReplicaMeta.swift`: `leakedToken` `nonisolated(unsafe)`.

## Test

- `PageCopyTests` (`ReplicaSnapshotTests`): `windowKeepsLeadInAboveTheFocus` / `windowStaysInsideThePage` ke 1800; baru `longPageIsKeptAtFullWidthAroundTheFocus` (halaman 5000 pt, fokus 2500: gambar 390 × 1800, mark di `leadIn`, warna di atas/bawah fokus). `rendersTheLockedPage` otomatis memakai `imageWidth` baru.
- `ReplicaViewTests`: `focusOffsetStaysInsideThePage` dihapus bersama `focusOffset`; navigasi tetap ditolak.
- Baru `DetailPrepareTests` (di `ReplicaMetaTests.swift`): `prepare` memberi HTML terkunci + meta; `prepare` yang dibatalkan memberi `(nil, nil)`.
- Baru `Tests/DetailPerfTests.swift` (XCTest, opt-in, skip tanpa `SHOO_PERF=1`): render, prepare, loader 3 MB dengan `XCTMemoryMetric`/`XCTClockMetric`/`XCTCPUMetric`.

## Verifikasi

Simulator "Shoo Track App 19-26" (iPhone 17, iOS 26.5), build `fix/DT-04-snapshot-perf` setelah perbaikan S5:

| Perintah | Hasil |
|---|---|
| `xcodebuild build … SWIFT_STRICT_CONCURRENCY=complete` | sukses; 0 peringatan di `Features/Detail` (sebelumnya 3) |
| `xcodebuild test-without-building -only-testing:ShooAppTests` | 467 test di 45 suite lulus; `DetailPerfTests` 3 skip (tanpa `SHOO_PERF`) |
| `-only-testing:ShooAppUITests/DetailUITests` | 8/8 lulus |
| `TEST_RUNNER_SHOO_PERF=1 … DetailPerfTests` (SE) | angka di tabel Spike |

## Review (satu per satu)

| Reviewer | Hasil | Tindak lanjut |
|---|---|---|
| `ecc:swift-reviewer` | Tidak ada yang memblokir. `prepare` `nonisolated async` berjalan di luar main actor (Swift 5, SE-0338); tidak ada sisa referensi ke API yang dihapus. 5 catatan rendah | Komentar loader dilunakkan (`String(bytes:)` bisa tetap menyalin di dalam Foundation). Tidak diubah: `ReplicaMeta.read` setelah cek batal terakhir (murah); `@concurrent` saat pindah Swift 6.2 (catatan handoff); test batal di tengah jalan (kode tidak menjanjikannya); `DetailPerfTests` smoke test tanpa baseline (sesuai tujuannya) |
| `ecc:security-reviewer` | Bersih terhadap SECURITY §3: JS mati, rule list jaringan, batas 3 MB, host/redirect, token bocor, log, tanpa tulis disk tidak berubah | Bitmap ≈ 25 MB @3x dibatasi lebar tetap 390 pt + jendela 1800 pt (halaman jahat tidak bisa memperbesar); `DetailPerfTests` memakai stub `URLProtocol`, tanpa jaringan/disk |

## Screenshot (UI gate)

`plan/alief/qa/img/fase-22/`: kartu bukti, layar penuh 1×, double-tap zoom, sebelum (`origin/main` aa976af) / sesudah, SE + Pro Max; plus potongan zoom Pro Max ukuran asli (`detail-zoomcrop-*`). Sesudah: teks salinan tajam di zoom (sebelum buram karena 200 pt diperbesar). Di SE, test screenshot menggulir ke kartu kedua dan "zoom" berisi layar penuh 1× (zoom 2,5× SE tidak tertangkap); Pro Max lengkap. Detail selalu tampilan terang untuk salinan halaman; satu bahasa (EN) karena gambar salinan tidak bergantung bahasa.

## Privasi Apple (D-alief-40, SECURITY §3 P9/P13)

| Butir | Hasil |
|---|---|
| Gambar | Tetap hanya di memori selama Detail terbuka; lebih besar (≈ 25 MB @3x maksimum), tidak ditulis ke disk |
| Web view | Tetap tersembunyi, tanpa JS, tanpa jaringan (rule list), dibuang setelah snapshot |
| Pembatalan | `prepare` sekarang ikut batal saat Detail ditutup (tidak ada pindai sisa) |
| Log | Tidak ada log baru |

## Catatan handoff

- Loader per potongan (delegate `URLSessionDataDelegate` dengan batas 3 MB) kalau iPhone fisik menunjukkan > 100 ms; test batas `ReplicaLoaderTests` sudah ada.
- Ukur S6/S7 di iPhone fisik dengan Instruments (Allocations + VM Tracker, "All Processes") sebelum menyimpulkan K8.
- `DetailView.prepare` bergantung pada `nonisolated async` = global executor (Swift 5). Saat proyek menyalakan `NonisolatedNonsendingByDefault` / Swift 6.2, tandai `@concurrent` supaya tidak pindah ke main.
- `DetailPerfTests`: `TEST_RUNNER_SHOO_PERF=1 xcodebuild test -only-testing:ShooAppTests/DetailPerfTests …`.
