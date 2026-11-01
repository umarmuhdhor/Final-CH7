# QA report: does the iOS app match Figma, and does scam detection work?

Run on 2026-11-01 (first run 2026-10-31). Branch `feat/GD-01-home-figma`, PR #228.

## Short version

- **Screens vs Figma:** 73 Figma frames checked. 37 the same, 30 with small differences, 6 clearly different. Many small differences come from iOS itself (top bar position, glass buttons).
- **Test 1, unusual fake data:** the screens still work. 2 small issues: a 39% warning says "Risiko Tinggi", and big counters don't shorten to "999+".
- **Test 2a, scam detector on saved pages:** misses its targets. It blocks only 15 of 52 scam pages (29%, target 70%) and wrongly flags 4 of 56 normal pages (target 0).
- **Test 2b/2c, real websites on two phones:** one of the 2 live scam pages got a 76% warning and reached the Guardian's app. The Guardian only sees it after turning Family mode on by hand. Push can't be tested on a laptop setup.

## How to read this report

**Screen status:**

| Mark | Meaning |
|---|---|
| ✅ same | Looks like the Figma frame. |
| 🟡 small diff | Small visual difference, often caused by iOS itself. |
| 🟠 clear diff | Clearly different. Needs a design or product decision. |
| 🔴 missing | The screen is not built. |
| ⚪ not shot | No app screenshot for this frame. |

**Scam score** (from `contracts/README.md`):

| Score | What the user sees |
|---|---|
| 0 to 29 | Nothing. The page is treated as normal. |
| 30 to 79 | A warning. |
| 80 to 100 | The page is blocked. |

**The 4 detection layers** (from `contracts/detector-interface.md`):

| Layer | What it checks | Where it runs |
|---|---|---|
| L1 | Known scam sites list | On the phone |
| L2 | The link name (fake brand names, odd hosts) | On the phone |
| L3 | Page text and forms (asks for OTP, PIN, ID card) | Server |
| L4 | Reality check by an AI model (does this request make sense for this kind of page?) | Server |

## What was tested

| Test | What it checks | How |
|---|---|---|
| Screens | Every app screen next to its Figma frame. | Figma page *High Fidelity*: every iOS frame marked Ready for dev, plus HOME and the *AI vs Guardian* exploration. Fake data (scenario `figma`). |
| Test 1 | The same screens with unusual fake data. | 6 data sets from `Data/MockScenarios.swift`. No server. |
| Test 2a | Does the detector give the right score? | 108 saved web pages from Imelda's test set, sent through all 4 layers. No real website opened. |
| Test 2b/2c | Does it work end to end on real websites? | Two paired phones (Guardian + Protected). Safari opens the test-set pages that still exist. |

| | |
|---|---|
| Devices | Screens and Test 1: iPhone 17 Pro simulator, iOS 26.4. Test 2b/2c: "QA Guardian iPhone 17" (iOS 26.5) and "QA Protected iPhone 17" (iOS 26.4). |
| Settings | Bahasa Indonesia, light mode, Jakarta time (WIB). |
| App | `feat/GD-01-home-figma` @ f93e660 (with `main` merged in). |
| Figma | [High Fidelity](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=18-2), exported at 1x with the TalkToFigma plugin. |

## Problems found

Found outside the screen-by-screen tables. First seen on 2026-10-31, checked again on 2026-11-01.

### Still open

| # | Problem | Where to see it | How bad |
|---|---|---|---|
| 6 | The Guardian sees nothing from the family after pairing. Family mode must be switched on by hand on Home first. Figma always shows the family. | `live/guardian-activity.jpg` (off) vs `guardian-activity-family.jpg` (on) | 🟠 |
| 7 | Push can't be tested on the laptop setup. The local server can't use HTTP/2, which Apple's push service needs, so every push logs `failed:network`. Production uses the deployed server, so this is only a test setup limit. A cloud staging server is needed for a full push test. | Test 2b/2c, step 4 | 🟠 |
| 11 | The scam detector misses its targets: 4 normal pages flagged (target 0), 15 scam pages missed, only 29% of scams blocked (target 70%). | Test 2a | ⚪ Team AI |
| 4 | A 39% warning says "Risiko Tinggi", the same label as 72%. | `corpus-dt-real-lphone` | 🟡 |
| 5 | Counters don't shorten: Guardian Profile shows "3.000 Situs diblokir" (no "999+"). It fits, but the tile gets wider than in Figma. | `heavy-pf-guardian` | 🟡 |
| 9 | The Safari extension popup is in English while the app is in Bahasa Indonesia. It follows the phone's language. The extension is out of scope here; noted for the lead. | `live/safari-regs-apps14-code-php.jpg` | 🟡 |
| 10 | On a live scan, the page copy in Detail ("Salinan halaman") stays grey and the site icon circle is empty. | `live/guardian-detail-regnows.jpg` | 🟡 |

### Fixed since 2026-10-31

| # | Problem | Now |
|---|---|---|
| 1 | Emoji in a name showed as ⍰ boxes. | `Bayu 🧑‍💻` shows the emoji (`edge-home-guardian`, `edge-pf-guardian`). |
| 2 | An expired code showed a general error. | Shows "Kode kedaluwarsa, minta kode baru dan coba lagi." like Figma 205:1182. |
| 3 | A "Notifikasi mati" popup covered Home and Activity in every test run. | Gone in all Home and Activity screenshots. |

### Not checked again

| # | Problem | Why |
|---|---|---|
| 8 | Opening the same page twice made two rows in Activity (`regnows-dfg.com` at 22.40 and 22.41). | This run opened each page only once, and Activity showed one row. |

### Screens that differ from Figma

Worst first. Pictures are in the screen tables below.

| Status | Frame | What is different |
|---|---|---|
| 🟠 clear diff | [protected/Home](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=441-2736) | Different design: an older option for the Protected Home (status strip, Terblokir / Perlu Waspada tiles). The app builds frame 441:3800 instead. The designer has to say which one is final. |
| 🟠 clear diff | [protected/Home · Lihat semua di atas](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=441-3063) | Different design: another option for the Protected Home (wider card). The app builds frame 441:3800 instead. The designer has to say which one is final. |
| 🟠 clear diff | [Profile/Pribadi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-10338) | Different: the Perlindungan section shows "Ekstensi Safari · Aktif" as text. Figma has two switches (Ekstensi Safari, Blokir situs berbahaya). Needs a feature decision. |
| 🟠 clear diff | [Pengaturan/Kelola profil](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-12854) | Different: the "Akun · Perangkat terhubung" row is missing (not built yet). "Ubah foto" is extra in the app. The username has no arrow because it cannot be changed. |
| 🟠 clear diff | [Protected/Detail · Dibuka Guardian · Opsi 1](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-7897) | Different (design exploration, option 1): Figma shows the Protected person "Virellia menandai situs ini aman · Blokir dibuka", the AI's first score 92, and "Tetap hati-hati". The app shows the gauge with "Ditandai aman oleh Virellia" and the verified card. |
| 🟠 clear diff | [Protected/Detail · Dibuka Guardian · Opsi 2](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-8620) | Different (design exploration, option 2): same as 487:7897. |
| 🟡 small diff | [Pribadi/Home](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20058) | Same: hero, status strip, tiles and list (within 1 pt), hero gradient, dashed rings. Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. The switch button uses iOS 26 glass, so it is brighter than Figma's grey. The app spells RISIKO right (Figma has RESIKO). |
| 🟡 small diff | [Guardian/Home](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20373) | Same layout (screenshot `home-guardian-members`). Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. |
| 🟡 small diff | [Guardian/Home · Keluarga butuh konfirmasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20899) | Same: the "DIBUKA SYAHNAZ · HARI INI, 10.42" line, title, chip, gauge, and the Bahaya / Aman buttons with Figma's shadow. Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. |
| 🟡 small diff | [Guardian/Home · Belum ada orang](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20630) | Same: blue-teal hero, no rings, invite card, QR, code spacing. Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. The mock data gives a 6-digit code. |
| 🟡 small diff | [protected/Home · Kartu diblokir 92%](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=441-3800) | Same: glow-only hero (no shield, like Figma), spacing, blocked card with gauge and two-line note, count tiles. Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. |
| 🟡 small diff | [protected/Home · Kartu diblokir 92% (bawah)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=441-4414) | Same as 441:3800, scrolled down. |
| 🟡 small diff | [Splash Screen](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-3585) | Different: the Figma frame is empty white. The app shows its splash screen with the logo. |
| 🟡 small diff | [Atur Nama · nama terlalu panjang](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4271) | Same text. Different: the Selanjutnya button stays off until the name is 1 to 20 characters. Figma shows it on. |
| 🟡 small diff | [Choose Mode](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4345) | Same layout and colours. Different: the app adds "Pilihan ini tidak bisa diganti nanti." Figma makes the chosen card 2 pt bigger; the app keeps both cards the same size. |
| 🟡 small diff | [Connect with Guardian · Kode](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=141-5887) | Same: code box size, gaps, tab shadow. Different: the app has 6 boxes because the server sends 6 digits (Figma has 5). Figma's code font Geist needs a `project.yml` change, which only the lead can make. The 14-day note and the "Nanti saja" button are extra in the app. |
| 🟡 small diff | [Kode Kadaluarsa · QR](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=205-1081) | Same code-box differences as 141:5887. |
| 🟡 small diff | [Kode Kadaluarsa · Kode](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=205-1182) | Fixed: now shows "Kode kedaluwarsa, minta kode baru dan coba lagi." like Figma. Same code-box differences as 141:5887. |
| 🟡 small diff | [Aktifkan Ekstensi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4440) | Screenshot with the extension off. Same: "Aktifkan Ekstensi" and "Terkendala? Tonton Tutorial". Extra in the app: step text that changes per iOS version, and the "Shoo dimatikan" hint. |
| 🟡 small diff | [Kirim Undangan (sheet)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4817) | Same: spacing and QR size. Different: share buttons are WhatsApp / Pesan / Lainnya (Figma: Messages / Mail / Notes). The countdown is extra in the app. Figma's code has 4 digits; the app has 6. |
| 🟡 small diff | [Aktivitas - Profil Pribadi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-8541) | Older Figma version with an outlined Diblokir pill. The app follows the newer frame 450:8443 (solid pill). |
| 🟡 small diff | [Aktivitas - Profil Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-8768) | Same layout. Different: the person button uses real iOS 26 glass, so it is whiter than in Figma. |
| 🟡 small diff | [Guardian/Detail Aktivitas (Bahaya)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-9255) | Same: score card, chips, contribution bar, footer. Different: the header is about 26 pt lower because the Figma frame has no status bar. The "Salinan halaman" caption belongs to the page-copy feature, which Figma does not have. |
| 🟡 small diff | [Guardian/Detail Aktivitas, sebelum di cek](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-4221) | Same: the "Virellia belum melihat link ini" banner (screenshot `dt-protected`, the Protected person's view). Same header offset as 416:9255. |
| 🟡 small diff | [Guardian/Detail Aktivitas Setelah Validasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-9362) | Same verified card. Different: here Figma puts "Kontribusi" over the photo; the app puts it under the photo, like the newer frames. |
| 🟡 small diff | [Guardian/Detail Aktivitas Waspada](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-9469) | Same as 416:9362. |
| 🟡 small diff | [Guardian/Detail Aktivitas Waspada (v2, tanpa pemilik)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-5990) | Screenshot `dt-protected-warning` (no owner chip, no buttons). Same Kontribusi difference as 416:9362. If this frame shows a Guardian's own scan, hiding Aman / Bahaya there is a product decision (#190). |
| 🟡 small diff | [Profile/Pribadi (v2, terhubung Virellia)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-10275) | Same: pill, stats, Terhubung card. Different: Figma shows a letter avatar "U" for the Protected person; the app shows a memoji. The "Ekstensi Safari" row has no arrow because it does nothing. Figma's Akun spacing is not the same in its two versions of this screen. |
| 🟡 small diff | [Profile/Pribadi (v2, layar pertama)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-10571) | Same as 455:10275. |
| 🟡 small diff | [Pengaturan/Mode akun](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9515) | This frame is the Protected "Akun Tertaut" page (screenshot `pf-protected-connection`). Different: the switches say "Segera hadir" because they are behind feature flag #183. Figma uses the English word "You" in the Indonesian screen. |
| 🟡 small diff | [Pengaturan/Mode akun (pilihan lain)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=457-10896) | Same as 455:9515. |
| 🟡 small diff | [Pengaturan/Kelola profil (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=462-11043) | Screenshot `pf-protected-manage`. Same, except the letter-avatar question from 455:10275. |
| 🟡 small diff | [Pengaturan/Notifikasi (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9627) | Screenshot `pf-protected-notifications`. Different: "Akun Terhubung" is behind feature flag #183. |
| 🟡 small diff | [Pengaturan/Notifikasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-12916) | Same layout. The "Notifikasi mati" banner shows because the test does not answer the notification question. |
| 🟡 small diff | [Pengaturan/Tentang Shoo (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9858) | Same layout. The version number comes from the build, so it differs from Figma. |
| 🟡 small diff | [Pengaturan/Tentang Shoo](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-13147) | Same as 455:9858. |

## Screen by screen

Left: the app now. Right: the Figma frame. Figma frames show the whole scroll height; the app screenshot shows one screen. More screens of the same state are in `img/figma-parity/app/<name>-2.jpg` and `-3.jpg`.

### Screens: Home

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Pribadi/Home](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20058)<br>`435:20058` | <img src="img/figma-parity/app/home-pribadi.jpg" width="160"><br>`home-pribadi` | <img src="img/figma-parity/figma/435-20058.jpg" width="160"> | 🟡 small diff | Same: hero, status strip, tiles and list (within 1 pt), hero gradient, dashed rings. Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. The switch button uses iOS 26 glass, so it is brighter than Figma's grey. The app spells RISIKO right (Figma has RESIKO). |
| [Guardian/Home](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20373)<br>`435:20373` | <img src="img/figma-parity/app/home-guardian-members.jpg" width="160"><br>`home-guardian-members` | <img src="img/figma-parity/figma/435-20373.jpg" width="160"> | 🟡 small diff | Same layout (screenshot `home-guardian-members`). Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. |
| [Guardian/Home · Keluarga butuh konfirmasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20899)<br>`435:20899` | <img src="img/figma-parity/app/home-guardian-pending.jpg" width="160"><br>`home-guardian-pending` | <img src="img/figma-parity/figma/435-20899.jpg" width="160"> | 🟡 small diff | Same: the "DIBUKA SYAHNAZ · HARI INI, 10.42" line, title, chip, gauge, and the Bahaya / Aman buttons with Figma's shadow. Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. |
| [Guardian/Home · Belum ada orang](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20630)<br>`435:20630` | <img src="img/figma-parity/app/home-guardian-empty.jpg" width="160"><br>`home-guardian-empty` | <img src="img/figma-parity/figma/435-20630.jpg" width="160"> | 🟡 small diff | Same: blue-teal hero, no rings, invite card, QR, code spacing. Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. The mock data gives a 6-digit code. |
| [protected/Home](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=441-2736)<br>`441:2736` | <img src="img/figma-parity/app/home-protected.jpg" width="160"><br>`home-protected` | <img src="img/figma-parity/figma/441-2736.jpg" width="160"> | 🟠 clear diff | Different design: an older option for the Protected Home (status strip, Terblokir / Perlu Waspada tiles). The app builds frame 441:3800 instead. The designer has to say which one is final. |
| [protected/Home · Lihat semua di atas](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=441-3063)<br>`441:3063` | <img src="img/figma-parity/app/home-protected.jpg" width="160"><br>`home-protected` | <img src="img/figma-parity/figma/441-3063.jpg" width="160"> | 🟠 clear diff | Different design: another option for the Protected Home (wider card). The app builds frame 441:3800 instead. The designer has to say which one is final. |
| [protected/Home · Kartu diblokir 92%](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=441-3800)<br>`441:3800` | <img src="img/figma-parity/app/home-protected.jpg" width="160"><br>`home-protected` | <img src="img/figma-parity/figma/441-3800.jpg" width="160"> | 🟡 small diff | Same: glow-only hero (no shield, like Figma), spacing, blocked card with gauge and two-line note, count tiles. Different: the top bar is about 19 pt lower (iOS places it), and the tabs say Perisai / Aktivitas where Figma says Shield / Activity. |
| [protected/Home · Kartu diblokir 92% (bawah)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=441-4414)<br>`441:4414` | <img src="img/figma-parity/app/home-protected-2.jpg" width="160"><br>`home-protected-2` | <img src="img/figma-parity/figma/441-4414.jpg" width="160"> | 🟡 small diff | Same as 441:3800, scrolled down. |

### Screens: Onboarding and pairing

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Splash Screen](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-3585)<br>`110:3585` | no screenshot<br>`none` | <img src="img/figma-parity/figma/110-3585.jpg" width="160"> | 🟡 small diff | Different: the Figma frame is empty white. The app shows its splash screen with the logo. |
| [Onboarding 1](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-3692)<br>`110:3692` | <img src="img/figma-parity/app/on-splash-1.jpg" width="160"><br>`on-splash-1` | <img src="img/figma-parity/figma/110-3692.jpg" width="160"> | ✅ same | Same as Figma: arrow size, button position, no button shadow. |
| [Onboarding 2](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-3786)<br>`110:3786` | <img src="img/figma-parity/app/on-splash-2.jpg" width="160"><br>`on-splash-2` | <img src="img/figma-parity/figma/110-3786.jpg" width="160"> | ✅ same | Same as Figma. |
| [Atur Nama · kosong](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-3912)<br>`110:3912` | <img src="img/figma-parity/app/on-name.jpg" width="160"><br>`on-name` | <img src="img/figma-parity/figma/110-3912.jpg" width="160"> | ✅ same | Same as Figma: headline position, line heights, body text colour. |
| [Atur Nama · mengetik](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4023)<br>`110:4023` | <img src="img/figma-parity/app/on-name-typed.jpg" width="160"><br>`on-name-typed` | <img src="img/figma-parity/figma/110-4023.jpg" width="160"> | ✅ same | Same as Figma. |
| [Atur Nama · nama terlalu panjang](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4271)<br>`110:4271` | <img src="img/figma-parity/app/on-name-tooLong.jpg" width="160"><br>`on-name-tooLong` | <img src="img/figma-parity/figma/110-4271.jpg" width="160"> | 🟡 small diff | Same text. Different: the Selanjutnya button stays off until the name is 1 to 20 characters. Figma shows it on. |
| [Choose Mode](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4345)<br>`110:4345` | <img src="img/figma-parity/app/on-mode.jpg" width="160"><br>`on-mode` | <img src="img/figma-parity/figma/110-4345.jpg" width="160"> | 🟡 small diff | Same layout and colours. Different: the app adds "Pilihan ini tidak bisa diganti nanti." Figma makes the chosen card 2 pt bigger; the app keeps both cards the same size. |
| [Choose Mode - Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4558)<br>`110:4558` | <img src="img/figma-parity/app/on-mode-guardian.jpg" width="160"><br>`on-mode-guardian` | <img src="img/figma-parity/figma/110-4558.jpg" width="160"> | ✅ same | Same as Figma (2 pt blue border). |
| [Choose Mode - Protected](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4605)<br>`110:4605` | <img src="img/figma-parity/app/on-mode-protected.jpg" width="160"><br>`on-mode-protected` | <img src="img/figma-parity/figma/110-4605.jpg" width="160"> | ✅ same | Same as Figma (2 pt teal border). |
| [Connect with Guardian · Pindai QR](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=140-5762)<br>`140:5762` | <img src="img/figma-parity/app/on-connect-qr.jpg" width="160"><br>`on-connect-qr` | <img src="img/figma-parity/figma/140-5762.jpg" width="160"> | ✅ same | Same as Figma (QR tab). |
| [Connect with Guardian · Kode](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=141-5887)<br>`141:5887` | <img src="img/figma-parity/app/on-connect-typed.jpg" width="160"><br>`on-connect-typed` | <img src="img/figma-parity/figma/141-5887.jpg" width="160"> | 🟡 small diff | Same: code box size, gaps, tab shadow. Different: the app has 6 boxes because the server sends 6 digits (Figma has 5). Figma's code font Geist needs a `project.yml` change, which only the lead can make. The 14-day note and the "Nanti saja" button are extra in the app. |
| [Kode Kadaluarsa · QR](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=205-1081)<br>`205:1081` | <img src="img/figma-parity/app/on-connect-expired-qr.jpg" width="160"><br>`on-connect-expired-qr` | <img src="img/figma-parity/figma/205-1081.jpg" width="160"> | 🟡 small diff | Same code-box differences as 141:5887. |
| [Kode Kadaluarsa · Kode](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=205-1182)<br>`205:1182` | <img src="img/figma-parity/app/on-connect-expired.jpg" width="160"><br>`on-connect-expired` | <img src="img/figma-parity/figma/205-1182.jpg" width="160"> | 🟡 small diff | Fixed: now shows "Kode kedaluwarsa, minta kode baru dan coba lagi." like Figma. Same code-box differences as 141:5887. |
| [Aktifkan Ekstensi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4440)<br>`110:4440` | <img src="img/figma-parity/app/on-turnOnExtension.jpg" width="160"><br>`on-turnOnExtension` | <img src="img/figma-parity/figma/110-4440.jpg" width="160"> | 🟡 small diff | Screenshot with the extension off. Same: "Aktifkan Ekstensi" and "Terkendala? Tonton Tutorial". Extra in the app: step text that changes per iOS version, and the "Shoo dimatikan" hint. |
| [Ekstensi aktif](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=126-5678)<br>`126:5678` | <img src="img/figma-parity/app/on-extensionOn.jpg" width="160"><br>`on-extensionOn` | <img src="img/figma-parity/figma/126-5678.jpg" width="160"> | ✅ same | Same as Figma. |
| [Berhasil Terhubung](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=141-5945)<br>`141:5945` | <img src="img/figma-parity/app/on-connected.jpg" width="160"><br>`on-connected` | <img src="img/figma-parity/figma/141-5945.jpg" width="160"> | ✅ same | Same as Figma (scenario `unpaired`). |
| [Undang keluarga](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4779)<br>`110:4779` | <img src="img/figma-parity/app/on-invite.jpg" width="160"><br>`on-invite` | <img src="img/figma-parity/figma/110-4779.jpg" width="160"> | ✅ same | Same as Figma (80 pt avatars, rings). |
| [Kirim Undangan (sheet)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4817)<br>`110:4817` | <img src="img/figma-parity/app/on-invite-sheet.jpg" width="160"><br>`on-invite-sheet` | <img src="img/figma-parity/figma/110-4817.jpg" width="160"> | 🟡 small diff | Same: spacing and QR size. Different: share buttons are WhatsApp / Pesan / Lainnya (Figma: Messages / Mail / Notes). The countdown is extra in the app. Figma's code has 4 digits; the app has 6. |

### Screens: Activity and Detail

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Aktivitas - Profil Pribadi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-8541)<br>`416:8541` | <img src="img/figma-parity/app/act-pribadi.jpg" width="160"><br>`act-pribadi` | <img src="img/figma-parity/figma/416-8541.jpg" width="160"> | 🟡 small diff | Older Figma version with an outlined Diblokir pill. The app follows the newer frame 450:8443 (solid pill). |
| [Aktivitas - Profil Pribadi : Filtered](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-8669)<br>`416:8669` | <img src="img/figma-parity/app/act-pribadi-warning.jpg" width="160"><br>`act-pribadi-warning` | <img src="img/figma-parity/figma/416-8669.jpg" width="160"> | ✅ same | Same as Figma. |
| [Aktivitas - Profil Pribadi (v2, catatan Guardian)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=450-8443)<br>`450:8443` | <img src="img/figma-parity/app/act-protected.jpg" width="160"><br>`act-protected` | <img src="img/figma-parity/figma/450-8443.jpg" width="160"> | ✅ same | Same as Figma: solid Diblokir pill without icon, note card. |
| [Aktivitas - Profil Pribadi : Filtered (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=450-8574)<br>`450:8574` | <img src="img/figma-parity/app/act-protected-warning.jpg" width="160"><br>`act-protected-warning` | <img src="img/figma-parity/figma/450-8574.jpg" width="160"> | ✅ same | Same as Figma (screenshot `act-protected-warning`). |
| [Aktivitas - Profil Pribadi : Filtered (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=450-8657)<br>`450:8657` | <img src="img/figma-parity/app/act-protected-blocked.jpg" width="160"><br>`act-protected-blocked` | <img src="img/figma-parity/figma/450-8657.jpg" width="160"> | ✅ same | Same as Figma (screenshot `act-protected-blocked`). |
| [Aktivitas - Profil Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-8768)<br>`416:8768` | <img src="img/figma-parity/app/act-guardian.jpg" width="160"><br>`act-guardian` | <img src="img/figma-parity/figma/416-8768.jpg" width="160"> | 🟡 small diff | Same layout. Different: the person button uses real iOS 26 glass, so it is whiter than in Figma. |
| [Aktivitas - Profil Guardian / Only one selected](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-8989)<br>`416:8989` | <img src="img/figma-parity/app/act-guardian-one.jpg" width="160"><br>`act-guardian-one` | <img src="img/figma-parity/figma/416-8989.jpg" width="160"> | ✅ same | Same as Figma. |
| [Picker](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-9208)<br>`416:9208` | <img src="img/figma-parity/app/act-guardian-picker.jpg" width="160"><br>`act-guardian-picker` | <img src="img/figma-parity/figma/416-9208.jpg" width="160"> | ✅ same | Same as Figma, including the menu padding and shadow. |
| [Aktivitas · Semua · Belum ada aktivitas](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5490)<br>`480:5490` | <img src="img/figma-parity/app/act-empty-all.jpg" width="160"><br>`act-empty-all` | <img src="img/figma-parity/figma/480-5490.jpg" width="160"> | ✅ same | Same as Figma (text spacing, width). |
| [Aktivitas · Waspada · Kosong](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5520)<br>`480:5520` | <img src="img/figma-parity/app/act-empty-warning.jpg" width="160"><br>`act-empty-warning` | <img src="img/figma-parity/figma/480-5520.jpg" width="160"> | ✅ same | Same as Figma. |
| [Aktivitas · Diblokir · Kosong](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5550)<br>`480:5550` | <img src="img/figma-parity/app/act-empty-blocked.jpg" width="160"><br>`act-empty-blocked` | <img src="img/figma-parity/figma/480-5550.jpg" width="160"> | ✅ same | Same as Figma. |
| [Aktivitas · Semua · Perlindungan mati](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5580)<br>`480:5580` | <img src="img/figma-parity/app/act-off.jpg" width="160"><br>`act-off` | <img src="img/figma-parity/figma/480-5580.jpg" width="160"> | ✅ same | Same as Figma. |
| [Guardian/Detail Aktivitas (Bahaya)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-9255)<br>`416:9255` | <img src="img/figma-parity/app/dt-blocked.jpg" width="160"><br>`dt-blocked` | <img src="img/figma-parity/figma/416-9255.jpg" width="160"> | 🟡 small diff | Same: score card, chips, contribution bar, footer. Different: the header is about 26 pt lower because the Figma frame has no status bar. The "Salinan halaman" caption belongs to the page-copy feature, which Figma does not have. |
| [Guardian/Detail Aktivitas, sebelum di cek](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-4221)<br>`487:4221` | <img src="img/figma-parity/app/dt-protected.jpg" width="160"><br>`dt-protected` | <img src="img/figma-parity/figma/487-4221.jpg" width="160"> | 🟡 small diff | Same: the "Virellia belum melihat link ini" banner (screenshot `dt-protected`, the Protected person's view). Same header offset as 416:9255. |
| [Guardian/Detail Aktivitas Setelah Validasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-9362)<br>`416:9362` | <img src="img/figma-parity/app/dt-validated.jpg" width="160"><br>`dt-validated` | <img src="img/figma-parity/figma/416-9362.jpg" width="160"> | 🟡 small diff | Same verified card. Different: here Figma puts "Kontribusi" over the photo; the app puts it under the photo, like the newer frames. |
| [Guardian/Detail Aktivitas Waspada](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-9469)<br>`416:9469` | <img src="img/figma-parity/app/dt-warning.jpg" width="160"><br>`dt-warning` | <img src="img/figma-parity/figma/416-9469.jpg" width="160"> | 🟡 small diff | Same as 416:9362. |
| [Guardian/Detail Aktivitas Waspada (v2, tanpa pemilik)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-5990)<br>`487:5990` | <img src="img/figma-parity/app/dt-protected-warning.jpg" width="160"><br>`dt-protected-warning` | <img src="img/figma-parity/figma/487-5990.jpg" width="160"> | 🟡 small diff | Screenshot `dt-protected-warning` (no owner chip, no buttons). Same Kontribusi difference as 416:9362. If this frame shows a Guardian's own scan, hiding Aman / Bahaya there is a product decision (#190). |
| [Guardian/Detail Aktivitas · Ditandai Aman](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5768)<br>`480:5768` | <img src="img/figma-parity/app/dt-safe.jpg" width="160"><br>`dt-safe` | <img src="img/figma-parity/figma/480-5768.jpg" width="160"> | ✅ same | Same as Figma: chip spacing, blue chip, centred owner note. |
| [Catatan/Guardian memilih Aman](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5924)<br>`480:5924` | <img src="img/figma-parity/app/dt-protected-safe.jpg" width="160"><br>`dt-protected-safe` | <img src="img/figma-parity/figma/480-5924.jpg" width="160"> | ✅ same | Same as Figma. |
| [Bukti Foto — Highlight](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-10831)<br>`416:10831` | <img src="img/figma-parity/app/dt-blocked-2.jpg" width="160"><br>`dt-blocked-2` | <img src="img/figma-parity/figma/416-10831.jpg" width="160"> | ✅ same | Same as Figma. |
| [Catatan · sudah dicek, bahaya](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=450-8734)<br>`450:8734` | <img src="img/figma-parity/app/act-protected.jpg" width="160"><br>`act-protected` | <img src="img/figma-parity/figma/450-8734.jpg" width="160"> | ✅ same | Same as Figma. |
| [Catatan · belum dicek](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=450-8739)<br>`450:8739` | <img src="img/figma-parity/app/act-protected.jpg" width="160"><br>`act-protected` | <img src="img/figma-parity/figma/450-8739.jpg" width="160"> | ✅ same | Same as Figma. |
| [Catatan · sudah dicek, aman](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=450-8744)<br>`450:8744` | <img src="img/figma-parity/app/act-protected-2.jpg" width="160"><br>`act-protected-2` | <img src="img/figma-parity/figma/450-8744.jpg" width="160"> | ✅ same | Same as Figma. |

### Screens: Profile

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Profile/Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-10447)<br>`416:10447` | <img src="img/figma-parity/app/pf-guardian.jpg" width="160"><br>`pf-guardian` | <img src="img/figma-parity/figma/416-10447.jpg" width="160"> | ✅ same | Same as Figma: spacing under the header card, pills, Renatta faded when her extension is off. |
| [Profile/Guardian · Belum ada orang](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5353)<br>`480:5353` | <img src="img/figma-parity/app/pf-guardian-empty.jpg" width="160"><br>`pf-guardian-empty` | <img src="img/figma-parity/figma/480-5353.jpg" width="160"> | ✅ same | Same as Figma. |
| [Profile/Pribadi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-10338)<br>`416:10338` | <img src="img/figma-parity/app/pf-pribadi.jpg" width="160"><br>`pf-pribadi` | <img src="img/figma-parity/figma/416-10338.jpg" width="160"> | 🟠 clear diff | Different: the Perlindungan section shows "Ekstensi Safari · Aktif" as text. Figma has two switches (Ekstensi Safari, Blokir situs berbahaya). Needs a feature decision. |
| [Profile/Pribadi · Ajak jadi Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5227)<br>`480:5227` | <img src="img/figma-parity/app/pf-pribadi-2.jpg" width="160"><br>`pf-pribadi-2` | <img src="img/figma-parity/figma/480-5227.jpg" width="160"> | ✅ same | Same as Figma (card shadow added). |
| [Profile/Pribadi (v2, terhubung Virellia)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-10275)<br>`455:10275` | <img src="img/figma-parity/app/pf-protected.jpg" width="160"><br>`pf-protected` | <img src="img/figma-parity/figma/455-10275.jpg" width="160"> | 🟡 small diff | Same: pill, stats, Terhubung card. Different: Figma shows a letter avatar "U" for the Protected person; the app shows a memoji. The "Ekstensi Safari" row has no arrow because it does nothing. Figma's Akun spacing is not the same in its two versions of this screen. |
| [Profile/Pribadi (v2, layar pertama)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-10571)<br>`455:10571` | <img src="img/figma-parity/app/pf-protected.jpg" width="160"><br>`pf-protected` | <img src="img/figma-parity/figma/455-10571.jpg" width="160"> | 🟡 small diff | Same as 455:10275. |
| [Guardian/Detail Orang Dilindungi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-10574)<br>`416:10574` | <img src="img/figma-parity/app/pf-member.jpg" width="160"><br>`pf-member` | <img src="img/figma-parity/figma/416-10574.jpg" width="160"> | ✅ same | Same as Figma: no avatar shadow, status pill, chips, "Aktivitas terbaru · Lihat semua". |
| [Guardian/Detail Orang Dilindungi · Putuskan](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-10676)<br>`416:10676` | <img src="img/figma-parity/app/pf-member-disconnect.jpg" width="160"><br>`pf-member-disconnect` | <img src="img/figma-parity/figma/416-10676.jpg" width="160"> | ✅ same | Same as Figma (the floating sheet is drawn by iOS). |
| [Pengaturan/Mode akun](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9515)<br>`455:9515` | <img src="img/figma-parity/app/pf-protected-connection.jpg" width="160"><br>`pf-protected-connection` | <img src="img/figma-parity/figma/455-9515.jpg" width="160"> | 🟡 small diff | This frame is the Protected "Akun Tertaut" page (screenshot `pf-protected-connection`). Different: the switches say "Segera hadir" because they are behind feature flag #183. Figma uses the English word "You" in the Indonesian screen. |
| [Pengaturan/Mode akun (pilihan lain)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=457-10896)<br>`457:10896` | <img src="img/figma-parity/app/pf-protected-connection.jpg" width="160"><br>`pf-protected-connection` | <img src="img/figma-parity/figma/457-10896.jpg" width="160"> | 🟡 small diff | Same as 455:9515. |
| [Pengaturan/Kelola profil (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=462-11043)<br>`462:11043` | <img src="img/figma-parity/app/pf-protected-manage.jpg" width="160"><br>`pf-protected-manage` | <img src="img/figma-parity/figma/462-11043.jpg" width="160"> | 🟡 small diff | Screenshot `pf-protected-manage`. Same, except the letter-avatar question from 455:10275. |
| [Pengaturan/Kelola profil](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-12854)<br>`416:12854` | <img src="img/figma-parity/app/pf-manage.jpg" width="160"><br>`pf-manage` | <img src="img/figma-parity/figma/416-12854.jpg" width="160"> | 🟠 clear diff | Different: the "Akun · Perangkat terhubung" row is missing (not built yet). "Ubah foto" is extra in the app. The username has no arrow because it cannot be changed. |
| [Pengaturan/Notifikasi (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9627)<br>`455:9627` | <img src="img/figma-parity/app/pf-protected-notifications.jpg" width="160"><br>`pf-protected-notifications` | <img src="img/figma-parity/figma/455-9627.jpg" width="160"> | 🟡 small diff | Screenshot `pf-protected-notifications`. Different: "Akun Terhubung" is behind feature flag #183. |
| [Pengaturan/Notifikasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-12916)<br>`416:12916` | <img src="img/figma-parity/app/pf-notifications.jpg" width="160"><br>`pf-notifications` | <img src="img/figma-parity/figma/416-12916.jpg" width="160"> | 🟡 small diff | Same layout. The "Notifikasi mati" banner shows because the test does not answer the notification question. |
| [Pengaturan/Bahasa (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9697)<br>`455:9697` | <img src="img/figma-parity/app/pf-language.jpg" width="160"><br>`pf-language` | <img src="img/figma-parity/figma/455-9697.jpg" width="160"> | ✅ same | Same as Figma (Bahasa Indonesia listed first). |
| [Pengaturan/Bahasa](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-12986)<br>`416:12986` | <img src="img/figma-parity/app/pf-language.jpg" width="160"><br>`pf-language` | <img src="img/figma-parity/figma/416-12986.jpg" width="160"> | ✅ same | Same as Figma. |
| [Pengaturan/Tema (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9718)<br>`455:9718` | <img src="img/figma-parity/app/pf-theme.jpg" width="160"><br>`pf-theme` | <img src="img/figma-parity/figma/455-9718.jpg" width="160"> | ✅ same | Same as Figma: theme previews, Efek section. |
| [Pengaturan/Tema](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-13007)<br>`416:13007` | <img src="img/figma-parity/app/pf-theme.jpg" width="160"><br>`pf-theme` | <img src="img/figma-parity/figma/416-13007.jpg" width="160"> | ✅ same | Same as Figma. |
| [Pengaturan/Aksesibilitas (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9785)<br>`455:9785` | <img src="img/figma-parity/app/pf-accessibility.jpg" width="160"><br>`pf-accessibility` | <img src="img/figma-parity/figma/455-9785.jpg" width="160"> | ✅ same | Same as Figma: slider and settings rows. |
| [Pengaturan/Aksesibilitas](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-13074)<br>`416:13074` | <img src="img/figma-parity/app/pf-accessibility.jpg" width="160"><br>`pf-accessibility` | <img src="img/figma-parity/figma/416-13074.jpg" width="160"> | ✅ same | Same as Figma. |
| [Pengaturan/Tentang Shoo (v2)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9858)<br>`455:9858` | <img src="img/figma-parity/app/pf-about.jpg" width="160"><br>`pf-about` | <img src="img/figma-parity/figma/455-9858.jpg" width="160"> | 🟡 small diff | Same layout. The version number comes from the build, so it differs from Figma. |
| [Pengaturan/Tentang Shoo](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-13147)<br>`416:13147` | <img src="img/figma-parity/app/pf-about.jpg" width="160"><br>`pf-about` | <img src="img/figma-parity/figma/416-13147.jpg" width="160"> | 🟡 small diff | Same as 455:9858. |

### Screens: AI vs Guardian (design exploration)

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Protected/Detail · Dibuka Guardian · Opsi 1](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-7897)<br>`487:7897` | <img src="img/figma-parity/app/dt-protected-safe.jpg" width="160"><br>`dt-protected-safe` | <img src="img/figma-parity/figma/487-7897.jpg" width="160"> | 🟠 clear diff | Different (design exploration, option 1): Figma shows the Protected person "Virellia menandai situs ini aman · Blokir dibuka", the AI's first score 92, and "Tetap hati-hati". The app shows the gauge with "Ditandai aman oleh Virellia" and the verified card. |
| [Protected/Detail · Dibuka Guardian · Opsi 2](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-8620)<br>`487:8620` | <img src="img/figma-parity/app/dt-protected-safe.jpg" width="160"><br>`dt-protected-safe` | <img src="img/figma-parity/figma/487-8620.jpg" width="160"> | 🟠 clear diff | Different (design exploration, option 2): same as 487:7897. |

## Test 1: the same screens with unusual fake data

**What it checks:** the screens still look right when the data is extreme: long names, emoji, many scans, only safe, only blocked. The data is fake (`MockRepository`), so no server is involved.

**Result:** the screens hold up. Problems 4 and 5 above come from this test.

**How to read it:** one row of screenshots per data set. The label above each picture is the screen: `home` = Home, `act` = Activity, `pf` = Profile, `dt` = Detail; `guardian` / `protected` = whose phone.

### `mixedVerdicts`: every kind of result: blocked or warning, and not reviewed, marked safe, or marked not safe by the Guardian

| `home-guardian` | `home-protected` | `act-guardian` | `act-protected` | `pf-guardian` |
|---|---|---|---|---|
| <img src="img/figma-parity/app/mixedVerdicts-home-guardian.jpg" width="140"> | <img src="img/figma-parity/app/mixedVerdicts-home-protected.jpg" width="140"> | <img src="img/figma-parity/app/mixedVerdicts-act-guardian.jpg" width="140"> | <img src="img/figma-parity/app/mixedVerdicts-act-protected.jpg" width="140"> | <img src="img/figma-parity/app/mixedVerdicts-pf-guardian.jpg" width="140"> |

### `heavy`: a lot of data: 3 family members, 60 scans over 30 days, counters over 999

| `home-guardian` | `home-protected` | `act-guardian` | `act-protected` | `pf-guardian` | `dt-first` |
|---|---|---|---|---|---|
| <img src="img/figma-parity/app/heavy-home-guardian.jpg" width="140"> | <img src="img/figma-parity/app/heavy-home-protected.jpg" width="140"> | <img src="img/figma-parity/app/heavy-act-guardian.jpg" width="140"> | <img src="img/figma-parity/app/heavy-act-protected.jpg" width="140"> | <img src="img/figma-parity/app/heavy-pf-guardian.jpg" width="140"> | <img src="img/figma-parity/app/heavy-dt-first.jpg" width="140"> |

### `edge`: awkward data: 20-character names, emoji, an 87-character web address, no title, icon or screenshot, only one reason

| `home-guardian` | `home-protected` | `act-guardian` | `act-protected` | `pf-guardian` | `dt-long` | `dt-one-signal` |
|---|---|---|---|---|---|---|
| <img src="img/figma-parity/app/edge-home-guardian.jpg" width="140"> | <img src="img/figma-parity/app/edge-home-protected.jpg" width="140"> | <img src="img/figma-parity/app/edge-act-guardian.jpg" width="140"> | <img src="img/figma-parity/app/edge-act-protected.jpg" width="140"> | <img src="img/figma-parity/app/edge-pf-guardian.jpg" width="140"> | <img src="img/figma-parity/app/edge-dt-long.jpg" width="140"> | <img src="img/figma-parity/app/edge-dt-one-signal.jpg" width="140"> |

### `allSafe`: every scan marked safe by the Guardian

| `home-guardian` | `home-protected` | `act-guardian` | `act-protected` | `pf-guardian` | `dt-safe` |
|---|---|---|---|---|---|
| <img src="img/figma-parity/app/allSafe-home-guardian.jpg" width="140"> | <img src="img/figma-parity/app/allSafe-home-protected.jpg" width="140"> | <img src="img/figma-parity/app/allSafe-act-guardian.jpg" width="140"> | <img src="img/figma-parity/app/allSafe-act-protected.jpg" width="140"> | <img src="img/figma-parity/app/allSafe-pf-guardian.jpg" width="140"> | <img src="img/figma-parity/app/allSafe-dt-safe.jpg" width="140"> |

### `allBlocked`: only blocked scans

| `home-guardian` | `home-protected` | `act-guardian` | `act-protected` | `pf-guardian` |
|---|---|---|---|---|
| <img src="img/figma-parity/app/allBlocked-home-guardian.jpg" width="140"> | <img src="img/figma-parity/app/allBlocked-home-protected.jpg" width="140"> | <img src="img/figma-parity/app/allBlocked-act-guardian.jpg" width="140"> | <img src="img/figma-parity/app/allBlocked-act-protected.jpg" width="140"> | <img src="img/figma-parity/app/allBlocked-pf-guardian.jpg" width="140"> |

### `corpus`: the scores and reasons the real detector gave in Test 2a (41 scans of 30 or more)

| `home-guardian` | `home-protected` | `act-guardian` | `act-protected` | `pf-guardian` | `dt-top` | `dt-real-bsi` | `dt-real-lphone` | `dt-false-positive` |
|---|---|---|---|---|---|---|---|---|
| <img src="img/figma-parity/app/corpus-home-guardian.jpg" width="140"> | <img src="img/figma-parity/app/corpus-home-protected.jpg" width="140"> | <img src="img/figma-parity/app/corpus-act-guardian.jpg" width="140"> | <img src="img/figma-parity/app/corpus-act-protected.jpg" width="140"> | <img src="img/figma-parity/app/corpus-pf-guardian.jpg" width="140"> | <img src="img/figma-parity/app/corpus-dt-top.jpg" width="140"> | <img src="img/figma-parity/app/corpus-dt-real-bsi.jpg" width="140"> | <img src="img/figma-parity/app/corpus-dt-real-lphone.jpg" width="140"> | <img src="img/figma-parity/app/corpus-dt-false-positive.jpg" width="140"> |

## Test 2a: does the detector score saved pages right?

**What it checks:** Imelda's test set has 108 saved web pages: 52 scam and 56 normal. Each page goes through all 4 layers, and its score is compared with what it should be. No real website is opened.

**Result: targets not met.** Too few scams are blocked, and 4 normal pages are wrongly flagged.

| Check | Target | Result | |
|---|---|---|---|
| Scam pages blocked (score 80 or more) | at least 70% | 15 of 52 = 29% | ❌ fail |
| Scam pages scoring 50 or more | at least 90% | 32 of 52 = 62% | ❌ fail |
| Scam pages that got any warning (30 or more) | no target | 37 of 52 = 71% | |
| Scam pages missed (under 30) | no target | 15 of 52 | |
| Normal pages wrongly flagged (30 or more) | 0 | 4 of 56 | ❌ fail |
| Server time for one page (95th percentile) | under 8 s | 6.0 s | ✅ pass |
| Server errors | 0 | 0 | ✅ pass |

**Keep in mind:** only 3 of the 52 scam pages are real captured scams. The rest were written by Team AI for testing ("made up"). 39 of the 56 normal pages are real sites. So these numbers show how the detector does on the test set, not yet on the real web. "Held back" pages are kept aside and never used to tune the detector.

Targets: `docs/mandates/imelda.md`. Command: `node ai/eval/run.mjs --analyze-url http://127.0.0.1:8788 --json --show-holdout`, against a local copy of the AI server (`ai/`) with the same AI model as production and the public scam list (190 000 sites) loaded. `corpus-to-scans.mjs` turns the results into the `corpus` data set for Test 1.

### Pages scored wrong

**How to read it:** "Should get" is the target for that kind of page. "Got" is the detector's score. "Why" lists the reasons that fired: name, layer, and points added.

| Page | Problem | Source | Should get | Got | Why |
|---|---|---|---|---|---|
| `trap-blog-cek-saldo-bca` | normal page flagged | made up | < 30 % · not scam, show nothing | 49 % | suspicious_link (L2, +24), brand_logo_offsite (L3, +25) |
| `trap-github-pages-dokumentasi` | normal page flagged | made up, held back | < 30 % · not scam, show nothing | 34 % | suspicious_link (L2, +19), asks_password (L3, +15) |
| `trap-fintech-kyc-sah` | normal page flagged | made up | < 30 % · not scam, show nothing | 95 % | suspicious_link (L2, +10), asks_selfie_ktp (L3, +35), asks_ktp (L3, +25), asks_otp (L3, +25) |
| `trap-asuransi-klaim-resmi` | normal page flagged | made up, held back | < 30 % · not scam, show nothing | 35 % | suspicious_link (L2, +10), asks_ktp (L3, +25) |
| `regs-apps14-code-php` | scam missed | real | ≥ 80 % · scam, block it | 21 % | suspicious_link (L2, +21) |
| `fixture-bca-verifikasi` | scam missed | made up | ≥ 80 % · scam, block it | 29 % | brand_plus_keyword (L2, +14), cheap_tld (L2, +15) |
| `fixture-promo-shopee` | scam missed | made up | ≥ 80 % · scam, block it | 29 % | brand_plus_keyword (L2, +14), cheap_tld (L2, +15) |
| `fixture-bansos-kemensos` | scam missed | made up | ≥ 80 % · scam, block it | 29 % | brand_plus_keyword (L2, +14), cheap_tld (L2, +15) |
| `synthetic-p0stindonesia` | scam missed | made up | ≥ 80 % · scam, block it | 25 % | lookalike_domain (L2, +25) |
| `syn-cimb-octo-limit` | scam missed | made up, held back | ≥ 80 % · scam, block it | 0 % | none |
| `syn-sicepat-apk` | scam missed | made up | ≥ 80 % · scam, block it | 5 % | cheap_tld (L2, +5) |
| `syn-anteraja-alamat` | scam missed | made up | ≥ 80 % · scam, block it | 20 % | asks_card (L3, +20) |
| `syn-telkomsel-poin` | scam missed | made up | ≥ 80 % · scam, block it | 25 % | asks_otp (L3, +25) |
| `syn-etilang-denda` | scam missed | made up, held back | ≥ 80 % · scam, block it | 20 % | asks_card (L3, +20) |
| `syn-samsat-pajak-kendaraan` | scam missed | made up, held back | ≥ 80 % · scam, block it | 5 % | cheap_tld (L2, +5) |
| `syn-find-my-iphone-hilang` | scam missed | made up | ≥ 80 % · scam, block it | 25 % | lookalike_domain (L2, +10), cheap_tld (L2, +15) |
| `syn-apple-pay-tagihan` | scam missed | made up | ≥ 80 % · scam, block it | 25 % | cheap_tld (L2, +5), asks_card (L3, +20) |
| `syn-loker-admin-online` | scam missed | made up | ≥ 80 % · scam, block it | 0 % | none |
| `syn-investasi-kripto-profit` | scam missed | made up | ≥ 80 % · scam, block it | 0 % | none |

<details><summary>All 108 pages</summary>

"L1-2" is the score from the phone alone; "Final" adds the server layers.

| Page | Type | Source | Should get | L1-2 | Final | Right? | Why |
|---|---|---|---|---|---|---|---|
| `bank-login-bri` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `bank-login-btn` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `bank-login-danamon` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `bank-login-klikbca` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `bank-login-mega` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `bank-login-permata` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-bukalapak` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-lazada` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-orami` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-ruparupa` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-shopee-cart` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-sociolla` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-tokopedia-cart` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-traveloka` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-zalora` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `gov-bi` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `gov-bpjs-kesehatan` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `gov-dukcapil` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `gov-kemensos` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `gov-komdigi` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `gov-ojk` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `gov-pajak` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-cnnindonesia` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-detik` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-idntimes` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-kompas` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-kumparan` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-liputan6` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-tribunnews` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-wikipedia-id` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `bank-login-bni-web` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `bank-login-mandiri-web` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `checkout-bhinneka` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `gov-kemenkeu` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-merdeka` | normal | real, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `official-tokopedia-home` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `official-bca-home` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `official-shopee-home` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `popular-wikipedia` | normal | real | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `trap-dana-sosial` | normal | made up | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `trap-mandiri-jaya` | normal | made up | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `trap-toko-iphone-bekas` | normal | made up, held back | < 30 % · not scam, show nothing | 10 | 10 | ✅ left alone | lookalike_domain (L2, +10) |
| `trap-cloud-storage` | normal | made up | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `trap-toko-logo-bank-checkout` | normal | made up, held back | < 30 % · not scam, show nothing | 0 | 20 | ✅ left alone | brand_logo_offsite (L3, +12), urgent_language (L3, +8) |
| `trap-blog-cek-saldo-bca` | normal | made up | < 30 % · not scam, show nothing | 24 | 49 | ❌ wrongly flagged | suspicious_link (L2, +24), brand_logo_offsite (L3, +25) |
| `trap-github-pages-dokumentasi` | normal | made up, held back | < 30 % · not scam, show nothing | 19 | 34 | ❌ wrongly flagged | suspicious_link (L2, +19), asks_password (L3, +15) |
| `trap-sign-in-google-facebook` | normal | made up | < 30 % · not scam, show nothing | 10 | 25 | ✅ left alone | suspicious_link (L2, +10), asks_password (L3, +15) |
| `trap-fintech-kyc-sah` | normal | made up | < 30 % · not scam, show nothing | 10 | 95 | ❌ wrongly flagged | suspicious_link (L2, +10), asks_selfie_ktp (L3, +35), asks_ktp (L3, +25), asks_otp (L3, +25) |
| `trap-berita-waspada-penipuan` | normal | made up | < 30 % · not scam, show nothing | 0 | 20 | ✅ left alone | brand_logo_offsite (L3, +12), urgent_language (L3, +8) |
| `trap-portal-orang-tua-sekolah` | normal | made up | < 30 % · not scam, show nothing | 0 | 15 | ✅ left alone | asks_password (L3, +15) |
| `trap-asuransi-klaim-resmi` | normal | made up, held back | < 30 % · not scam, show nothing | 10 | 35 | ❌ wrongly flagged | suspicious_link (L2, +10), asks_ktp (L3, +25) |
| `trap-toko-kopi-kartu-native` | normal | made up | < 30 % · not scam, show nothing | 0 | 20 | ✅ left alone | asks_card (L3, +20) |
| `trap-batik-card-checkout-en` | normal | made up | < 30 % · not scam, show nothing | 5 | 25 | ✅ left alone | cheap_tld (L2, +5), asks_card (L3, +20) |
| `syn-sekolah-portal2` | normal | made up, held back | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `syn-toko-app3-index-php` | normal | made up | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `syn-kampus-code-path` | normal | made up | < 30 % · not scam, show nothing | 0 | 0 | ✅ left alone | none |
| `regs-apps14-code-php` | scam | real | ≥ 80 % · scam, block it | 21 | 21 | ❌ missed | suspicious_link (L2, +21) |
| `cusbsi-bsi-cash-management` | scam | real, held back | ≥ 80 % · scam, block it | 0 | 60 | ⚠️ only warned | brand_logo_offsite (L3, +25), new_domain (L3, +20), asks_password (L3, +15) |
| `lphone-login` | scam | real | ≥ 80 % · scam, block it | 39 | 39 | ⚠️ only warned | lookalike_domain (L2, +25), brand_plus_keyword (L2, +14) |
| `fixture-bca-verifikasi` | scam | made up | ≥ 80 % · scam, block it | 29 | 29 | ❌ missed | brand_plus_keyword (L2, +14), cheap_tld (L2, +15) |
| `fixture-promo-shopee` | scam | made up | ≥ 80 % · scam, block it | 29 | 29 | ❌ missed | brand_plus_keyword (L2, +14), cheap_tld (L2, +15) |
| `fixture-bansos-kemensos` | scam | made up | ≥ 80 % · scam, block it | 29 | 29 | ❌ missed | brand_plus_keyword (L2, +14), cheap_tld (L2, +15) |
| `synthetic-p0stindonesia` | scam | made up | ≥ 80 % · scam, block it | 25 | 25 | ❌ missed | lookalike_domain (L2, +25) |
| `syn-bri-token-expired` | scam | made up | ≥ 80 % · scam, block it | 29 | 100 | ✅ blocked | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), asks_pin (L3, +35), asks_otp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-mandiri-livin-upgrade` | scam | made up, held back | ≥ 80 % · scam, block it | 29 | 100 | ✅ blocked | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), unreasonable_request (L4, +30), brand_logo_offsite (L3, +25), asks_password (L3, +15), urgent_language (L3, +15) |
| `syn-bni-mobile-banking` | scam | made up, held back | ≥ 80 % · scam, block it | 25 | 100 | ✅ blocked | lookalike_domain (L2, +10), cheap_tld (L2, +15), unreasonable_request (L4, +30), brand_logo_offsite (L3, +25), asks_card (L3, +20), asks_password (L3, +15) |
| `syn-bsi-sharia-bonus` | scam | made up | ≥ 80 % · scam, block it | 25 | 100 | ✅ blocked | lookalike_domain (L2, +10), cheap_tld (L2, +15), asks_pin (L3, +35), unreasonable_request (L4, +30), asks_ktp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-bca-klikbca-clean` | scam | made up | ≥ 80 % · scam, block it | 0 | 80 | ✅ blocked | unreasonable_request (L4, +30), asks_otp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-cimb-octo-limit` | scam | made up, held back | ≥ 80 % · scam, block it | 0 | 0 | ❌ missed | none |
| `syn-bca-blokir-kartu` | scam | made up, held back | ≥ 80 % · scam, block it | 14 | 59 | ⚠️ only warned | brand_plus_keyword (L2, +14), brand_logo_offsite (L3, +25), asks_card (L3, +20) |
| `syn-bri-cashback-survey` | scam | made up | ≥ 80 % · scam, block it | 25 | 85 | ✅ blocked | lookalike_domain (L2, +10), cheap_tld (L2, +15), asks_pin (L3, +35), brand_logo_offsite (L3, +25) |
| `syn-mandiri-kyc-update` | scam | made up | ≥ 80 % · scam, block it | 0 | 100 | ✅ blocked | asks_selfie_ktp (L3, +35), unreasonable_request (L4, +30), asks_ktp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-dana-kaget-bonus` | scam | made up | ≥ 80 % · scam, block it | 29 | 100 | ✅ blocked | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), unreasonable_request (L4, +30), asks_otp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-ovo-upgrade-premier` | scam | made up | ≥ 80 % · scam, block it | 25 | 100 | ✅ blocked | lookalike_domain (L2, +10), cheap_tld (L2, +15), asks_pin (L3, +35), asks_ktp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-gopay-driver-refund` | scam | made up | ≥ 80 % · scam, block it | 29 | 100 | ✅ blocked | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), asks_pin (L3, +35), asks_otp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-shopeepay-limit` | scam | made up | ≥ 80 % · scam, block it | 29 | 69 | ⚠️ only warned | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), brand_logo_offsite (L3, +25), asks_password (L3, +15) |
| `syn-linkaja-hadiah` | scam | made up, held back | ≥ 80 % · scam, block it | 0 | 35 | ⚠️ only warned | asks_pin (L3, +35) |
| `syn-dana-premium-pin` | scam | made up, held back | ≥ 80 % · scam, block it | 29 | 100 | ✅ blocked | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), asks_pin (L3, +35), asks_otp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-ovo-undian-grab` | scam | made up | ≥ 80 % · scam, block it | 29 | 54 | ⚠️ only warned | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), brand_logo_offsite (L3, +25) |
| `syn-gopay-later-pinjam` | scam | made up | ≥ 80 % · scam, block it | 5 | 90 | ✅ blocked | cheap_tld (L2, +5), asks_selfie_ktp (L3, +35), asks_ktp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-jne-paket-tertahan` | scam | made up | ≥ 80 % · scam, block it | 25 | 70 | ⚠️ only warned | lookalike_domain (L2, +10), cheap_tld (L2, +15), brand_logo_offsite (L3, +25), asks_card (L3, +20) |
| `syn-jnt-tarif-selisih` | scam | made up | ≥ 80 % · scam, block it | 25 | 50 | ⚠️ only warned | lookalike_domain (L2, +10), cheap_tld (L2, +15), brand_logo_offsite (L3, +25) |
| `syn-sicepat-apk` | scam | made up | ≥ 80 % · scam, block it | 5 | 5 | ❌ missed | cheap_tld (L2, +5) |
| `syn-anteraja-alamat` | scam | made up | ≥ 80 % · scam, block it | 0 | 20 | ❌ missed | asks_card (L3, +20) |
| `syn-pos-kiriman-luar-negeri` | scam | made up | ≥ 80 % · scam, block it | 25 | 50 | ⚠️ only warned | lookalike_domain (L2, +25), brand_logo_offsite (L3, +25) |
| `syn-tiki-nomor-resi` | scam | made up | ≥ 80 % · scam, block it | 5 | 30 | ⚠️ only warned | cheap_tld (L2, +5), asks_otp (L3, +25) |
| `syn-ninja-ganti-rugi` | scam | made up, held back | ≥ 80 % · scam, block it | 5 | 40 | ⚠️ only warned | cheap_tld (L2, +5), asks_pin (L3, +35) |
| `syn-tokopedia-undian` | scam | made up, held back | ≥ 80 % · scam, block it | 29 | 69 | ⚠️ only warned | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), brand_logo_offsite (L3, +25), asks_password (L3, +15) |
| `syn-telkomsel-poin` | scam | made up | ≥ 80 % · scam, block it | 0 | 25 | ❌ missed | asks_otp (L3, +25) |
| `syn-lazada-giveaway` | scam | made up | ≥ 80 % · scam, block it | 25 | 70 | ⚠️ only warned | lookalike_domain (L2, +10), cheap_tld (L2, +15), brand_logo_offsite (L3, +25), asks_card (L3, +20) |
| `syn-shopee-flash-undian` | scam | made up | ≥ 80 % · scam, block it | 29 | 54 | ⚠️ only warned | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), brand_logo_offsite (L3, +25) |
| `syn-bpjs-bonus-iuran` | scam | made up | ≥ 80 % · scam, block it | 29 | 74 | ⚠️ only warned | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), brand_logo_offsite (L3, +25), asks_card (L3, +20) |
| `syn-pertamina-subsidi` | scam | made up | ≥ 80 % · scam, block it | 0 | 60 | ⚠️ only warned | asks_selfie_ktp (L3, +35), asks_ktp (L3, +25) |
| `syn-bukalapak-voucher` | scam | made up | ≥ 80 % · scam, block it | 29 | 79 | ⚠️ only warned | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), asks_otp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-bpjs-kesehatan-nonaktif` | scam | made up, held back | ≥ 80 % · scam, block it | 25 | 75 | ⚠️ only warned | lookalike_domain (L2, +10), cheap_tld (L2, +15), asks_ktp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-pajak-djp-sptp` | scam | made up | ≥ 80 % · scam, block it | 29 | 69 | ⚠️ only warned | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), brand_logo_offsite (L3, +25), asks_password (L3, +15) |
| `syn-etilang-denda` | scam | made up, held back | ≥ 80 % · scam, block it | 0 | 20 | ❌ missed | asks_card (L3, +20) |
| `syn-samsat-pajak-kendaraan` | scam | made up, held back | ≥ 80 % · scam, block it | 5 | 5 | ❌ missed | cheap_tld (L2, +5) |
| `syn-prakerja-gelombang` | scam | made up | ≥ 80 % · scam, block it | 0 | 85 | ✅ blocked | asks_selfie_ktp (L3, +35), asks_ktp (L3, +25), asks_otp (L3, +25) |
| `syn-dukcapil-ktp-digital` | scam | made up | ≥ 80 % · scam, block it | 0 | 85 | ✅ blocked | asks_selfie_ktp (L3, +35), asks_ktp (L3, +25), asks_otp (L3, +25) |
| `syn-kemensos-bansos-pkh` | scam | made up | ≥ 80 % · scam, block it | 14 | 99 | ✅ blocked | brand_plus_keyword (L2, +14), asks_pin (L3, +35), asks_ktp (L3, +25), brand_logo_offsite (L3, +25) |
| `syn-icloud-terkunci` | scam | made up | ≥ 80 % · scam, block it | 29 | 69 | ⚠️ only warned | brand_plus_keyword (L2, +14), cheap_tld (L2, +15), asks_otp (L3, +25), asks_password (L3, +15) |
| `syn-find-my-iphone-hilang` | scam | made up | ≥ 80 % · scam, block it | 25 | 25 | ❌ missed | lookalike_domain (L2, +10), cheap_tld (L2, +15) |
| `syn-apple-pay-tagihan` | scam | made up | ≥ 80 % · scam, block it | 5 | 25 | ❌ missed | cheap_tld (L2, +5), asks_card (L3, +20) |
| `syn-loker-admin-online` | scam | made up | ≥ 80 % · scam, block it | 0 | 0 | ❌ missed | none |
| `syn-pinjol-cair-cepat` | scam | made up | ≥ 80 % · scam, block it | 5 | 65 | ⚠️ only warned | cheap_tld (L2, +5), asks_selfie_ktp (L3, +35), asks_ktp (L3, +25) |
| `syn-investasi-kripto-profit` | scam | made up | ≥ 80 % · scam, block it | 0 | 0 | ❌ missed | none |
| `syn-olx-pembeli-cod` | scam | made up, held back | ≥ 80 % · scam, block it | 0 | 45 | ⚠️ only warned | asks_otp (L3, +25), asks_card (L3, +20) |

</details>

## Test 2b/2c: real websites on two paired phones

**What it checks:** the whole chain on real pages: Safari extension, then server, then the Guardian's app and notification.

**Setup:** two simulators. Adhella is the Guardian (the one who watches). Maria is Protected (the one being watched). They paired with a code, like real users. Maria's Safari opened the test-set pages one by one. Page load only: no typing, no tapping on the page, no downloads.

- **2b:** the 45 pages that still exist online (43 normal, 2 scam).
- **2c:** the 63 pages that no longer exist, including 50 scam pages. These only have the offline result from Test 2a.

### Result

| What | Result | |
|---|---|---|
| Normal pages | All showed 0%, except one old blog post at 24% (still under 30). None were sent to the server. | ✅ |
| Real scam `regs-apps14.regnows-dfg.com/code.php` | Popup with a 76% warning. Sent to the server and shown in the Guardian's app. | ✅ |
| Real scam `lphone-login.com` | Now forwards to the real iCloud page, so 0%. The scam hides itself from this visit. | ⚪ expected |
| Guardian sees Maria's scan | Only after Family mode is switched on by hand (problem 6). | ❌ |
| Push to the Guardian | The server tried, but the laptop setup can't send it (problem 7). The app shows the notification when it is sent by hand. | ⚠️ |
| Scheduled cleanup jobs | Ran fine when started by hand. | ✅ |

Raw count: 45 pages opened (43 legit, 2 scam). 1 reached the server as a scan (score ≥ 30), 1 Guardian push attempt(s) in push_log.

### Scam pages

| Page | Type | Offline score (2a) | What Safari showed | Sent to server | Push |
|---|---|---|---|---|---|
| `regs-apps14-code-php` | scam | 21 | **76% High risk popup** ("This site looks suspicious", "Link sent to Adhella", Leave this page / Continue anyway), copy in English | 76 warning | failed:network |
| `lphone-login` | scam | 39 | redirects to the real icloud.com Find Devices; 0% badge (cloaked kit) | none | n/a |

<details><summary>43 normal pages</summary>

| Page | Type | Offline score (2a) | What Safari showed | Sent to server | Push |
|---|---|---|---|---|---|
| `bank-login-bri` | normal | 0 | 0% badge | none | n/a |
| `bank-login-btn` | normal | 0 | 0% badge | none | n/a |
| `bank-login-danamon` | normal | 0 | 0% badge | none | n/a |
| `bank-login-klikbca` | normal | 0 | 0% badge | none | n/a |
| `bank-login-mega` | normal | 0 | 0% badge | none | n/a |
| `bank-login-permata` | normal | 0 | 0% badge | none | n/a |
| `checkout-bukalapak` | normal | 0 | 0% badge | none | n/a |
| `checkout-lazada` | normal | 0 | 0% badge | none | n/a |
| `checkout-orami` | normal | 0 | 0% badge | none | n/a |
| `checkout-ruparupa` | normal | 0 | 0% badge | none | n/a |
| `checkout-shopee-cart` | normal | 0 | Shopee language picker; 0% badge | none | n/a |
| `checkout-sociolla` | normal | 0 | 0% badge | none | n/a |
| `checkout-tokopedia-cart` | normal | 0 | 0% badge | none | n/a |
| `checkout-traveloka` | normal | 0 | app-download sheet on top; 0% badge | none | n/a |
| `checkout-zalora` | normal | 0 | 0% badge | none | n/a |
| `gov-bi` | normal | 0 | 0% badge | none | n/a |
| `gov-bpjs-kesehatan` | normal | 0 | 0% badge | none | n/a |
| `gov-dukcapil` | normal | 0 | 0% badge | none | n/a |
| `gov-kemensos` | normal | 0 | 0% badge | none | n/a |
| `gov-komdigi` | normal | 0 | 0% badge | none | n/a |
| `gov-ojk` | normal | 0 | 0% badge | none | n/a |
| `gov-pajak` | normal | 0 | PSA popup on top; 0% badge | none | n/a |
| `popular-cnnindonesia` | normal | 0 | 0% badge | none | n/a |
| `popular-detik` | normal | 0 | 0% badge | none | n/a |
| `popular-idntimes` | normal | 0 | ad interstitial; 0% badge | none | n/a |
| `popular-kompas` | normal | 0 | ad interstitial; 0% badge | none | n/a |
| `popular-kumparan` | normal | 0 | 0% badge | none | n/a |
| `popular-liputan6` | normal | 0 | ad interstitial; 0% badge | none | n/a |
| `popular-tribunnews` | normal | 0 | 0% badge | none | n/a |
| `popular-wikipedia-id` | normal | 0 | 0% badge | none | n/a |
| `bank-login-bni-web` | normal | 0 | 0% badge | none | n/a |
| `bank-login-mandiri-web` | normal | 0 | cookie notice on top; 0% badge | none | n/a |
| `checkout-bhinneka` | normal | 0 | 0% badge | none | n/a |
| `gov-kemenkeu` | normal | 0 | 0% badge | none | n/a |
| `popular-merdeka` | normal | 0 | ad interstitial; 0% badge | none | n/a |
| `official-tokopedia-home` | normal | 0 | 0% badge | none | n/a |
| `official-bca-home` | normal | 0 | 0% badge | none | n/a |
| `official-shopee-home` | normal | 0 | Shopee language picker; 0% badge | none | n/a |
| `popular-wikipedia` | normal | 0 | 0% badge | none | n/a |
| `trap-cloud-storage` | normal | 0 | redirects to a sedo.com parking page (cookie dialog); 0% badge | none | n/a |
| `trap-blog-cek-saldo-bca` | normal | 49 | blog post now 404; **24% badge** (under 30, nothing sent) | none | n/a |
| `trap-github-pages-dokumentasi` | normal | 34 | GitHub Pages 404; badge collapsed to a dot | none | n/a |
| `trap-berita-waspada-penipuan` | normal | 20 | Safari "This Connection Is Not Private" (certificate for another host); no badge | none | n/a |

</details>

### Step by step

1. **Normal pages.** Every page that loaded showed the green 0% badge. One old blog post showed 24%; that is under 30, so nothing happens. Pages under 30 are never sent to the server. The 4 normal pages that Test 2a flagged no longer show their old content (error page, parked domain, or no server), so here they scored 0. `beritakota` stopped at Safari's "This Connection Is Not Private" page, so there was no badge.
2. **The live scam, `regs-apps14.regnows-dfg.com/code.php`.** The extension showed a popup: 76%, "Link sent to Adhella", with *Leave this page* and *Continue anyway*. The server got the scan at 76 (warning) with 3 reasons: the page asks for things that don't fit it (L4, it quotes "PENDAFTARAN VIA TELEGRAM"), it asks for an OTP (L3), and the link looks suspicious (L2). The saved copy in Test 2a scored only 21 because it has no OTP field. On 2026-10-31 this page scored 46, without the L4 reason.
3. **`lphone-login.com`.** It scored 39 offline. Live, it forwards to the real `icloud.com` Find Devices page, so it scored 0%. Only the saved copy shows the fake login form.
4. **Push.** The visit was at 21.29 WITA, before quiet hours (22:00 to 06:00), so the server sent a push to Adhella and one to Maria right away. Both failed with `failed:network`. The reason: the local server can't use HTTP/2, and Apple's push service only accepts HTTP/2. Production sends from the deployed server, which passed this check before (fase 07, D-alief-B01). To test the app side, the same push was sent by hand with `xcrun simctl push` ("Maria membuka situs mencurigakan · 76%", real scan id). The notification showed on Adhella's Home screen.
5. **Guardian's app.** Right after pairing, Activity is empty: Family mode is off until Adhella switches it on from Home. After the switch, Home shows "Keluarga Butuh Konfirmasi" with Maria's 76% card. Activity lists the scan with Maria's name, and Detail opens with the 76% gauge.
6. **Maria's app.** Home shows "Anda Terlindungi!", "Terhubung dengan Adhella", 0 Diblokir and 1 Waspada, and the regnows row. Her Activity lists the same scan.
7. **No location popup** this time. On 2026-10-31 a Safari location question from `ruparupa.com` covered the later screenshots.
8. **Cleanup jobs.** Both scheduled jobs were started by hand and answered 200. The health row was written. There was nothing older than 14 days to delete, since the database was new.

### Screenshots

| Safari · regs-apps14-code-php | Safari · lphone-login | Safari · bank-login-klikbca | Guardian Activity, Family mode off | Guardian Activity, Family mode on | Guardian Home | Guardian Detail | Guardian push (simctl) | Protected Activity | Protected Home |
|---|---|---|---|---|---|---|---|---|---|
| <img src="img/figma-parity/live/safari-regs-apps14-code-php.jpg" width="140"> | <img src="img/figma-parity/live/safari-lphone-login.jpg" width="140"> | <img src="img/figma-parity/live/safari-bank-login-klikbca.jpg" width="140"> | <img src="img/figma-parity/live/guardian-activity.jpg" width="140"> | <img src="img/figma-parity/live/guardian-activity-family.jpg" width="140"> | <img src="img/figma-parity/live/guardian-home-family.jpg" width="140"> | <img src="img/figma-parity/live/guardian-detail-regnows.jpg" width="140"> | <img src="img/figma-parity/live/guardian-push.jpg" width="140"> | <img src="img/figma-parity/live/protected-activity.jpg" width="140"> | <img src="img/figma-parity/live/protected-home.jpg" width="140"> |

<details><summary>Laptop setup vs production</summary>

| Part | On the laptop | In production |
|---|---|---|
| API | `wrangler dev` of `backend/api` on :8787, `--test-scheduled` | Worker `shoo-api` |
| Database and storage | `supabase start` + `supabase db reset` (all migrations, row security on) | Supabase project |
| Page copies | local R2 (Miniflare) | R2 `shoo-replicas` |
| AI layers 3 and 4 | `wrangler dev` of `ai/` on :8788, same AI model as production, public scam list loaded | Worker `shoo-ai` |
| Push | Apple push **sandbox**, team key AK7HLX5ZX5, topic `com.aliefauzan.shoo` | Apple push |
| App | Debug build, `-debug.aiBaseURL http://localhost:8788` (Debug only) | Release |

Pairing (`LiveQAUITests`): both phones go through onboarding in Bahasa Indonesia. Maria types the code shown on Adhella's screen. Both answer the real notification question. Maria's Safari has Shoo on for all websites.

</details>

## How to run it again

```bash
# Figma frames (TalkToFigma plugin open in the file, channel joined)
node plan/alief/qa/figma-export.mjs plan/alief/qa/img/figma-parity/figma <channel>
# Screens + Test 1 screenshots (set TEST_RUNNER_QA_SCENARIO to figma, mixedVerdicts, heavy, edge, allSafe, allBlocked or corpus)
TEST_RUNNER_QA_SCENARIO=figma TEST_RUNNER_QA_SHOT_DIR=$PWD/plan/alief/qa/img/figma-parity/app xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShooAppUITests/FigmaParityUITests
# Test 2a data
npx --prefix ai wrangler dev --cwd ai --port 8788 &
node ai/eval/run.mjs --analyze-url http://127.0.0.1:8788 --json --show-holdout > /tmp/corpus-eval.json && node plan/alief/qa/corpus-to-scans.mjs /tmp/corpus-eval.json
# Test 2b: pair, then visit
TEST_RUNNER_QA_LIVE=1 TEST_RUNNER_QA_PAIR_DIR=/tmp/pair xcodebuild test … -only-testing:ShooAppUITests/LiveQAUITests/testGuardianPairs   # Guardian sim
TEST_RUNNER_QA_LIVE=1 TEST_RUNNER_QA_PAIR_DIR=/tmp/pair xcodebuild test … -only-testing:ShooAppUITests/LiveQAUITests/testProtectedJoins  # Protected sim
bash plan/alief/qa/live-visit.sh <protected-udid>
# then write live/observations.json from the shots, and
node plan/alief/qa/live-results.mjs
node plan/alief/qa/figma-parity-report.mjs
```
