# Proposal: pairing and role changes must show a result right away (20 Nov 2026)

Status: **proposal only, nothing built.** Owner: Alief (Team App). Areas: `ios/ShooApp/` (PR-*, GD-*, PF-01).

## Why

Usability test, 20 Nov 2026. The tester:

- tapped connect / chose to be Guardian, then saw nothing change: *"aku bingung harus ngapain, apa yang berubah… ternyata berubahnya pas aku balik ke halaman home"*;
- added a family member: *"aku nambahin guardian terus kayak gak ada apa-apa, ah ngapain nih?"*;
- did not know the Guardian feature existed until told.

Goal: the simplest change after which **something visibly changes right after every pairing or role tap**.

## How this was checked

- `main` at `5a62eb94`. Two iPhone 17 simulators (iOS 26.5), app in Bahasa Indonesia, local backend (`pnpm -C backend/api dev` + local Supabase).
- A throwaway XCUITest (not committed) drove both phones at once, the same way `LivePairingUITests` does. Guardian "Ayah" invites, Protected "Ibu" joins with the code. Screenshots were taken right after each tap and again ~2 s later.
- The Profile routes (Guardian card, Account mode) ran on the mock backend (`-UITestMock YES -mock.scenario empty`).
- Haptics and animations do not show in still screenshots. Those parts come from reading the code (file:line below).

## Current flows

### A. Guardian side: Pribadi → Guardian from Home ⇆, then invite, then a member joins

| g01 Home (Pribadi) | g02 tap ⇆ → intro | g04 "Mulai" → Home | g05 Profile | g06 "Undang Keluarga" sheet |
|---|---|---|---|---|
| <img src="img/pairing-feedback/g01-home-personal.jpg" width="150"> | <img src="img/pairing-feedback/g02-guardian-intro.jpg" width="150"> | <img src="img/pairing-feedback/g04-after-start-2s.jpg" width="150"> | <img src="img/pairing-feedback/g05-profile-guardian.jpg" width="150"> | <img src="img/pairing-feedback/g06-invite-sheet.jpg" width="150"> |

| g07 Ibu joined, +1 s | g08 Ibu joined, +8 s | g09 close sheet → Profile | g10 Back → Home |
|---|---|---|---|
| <img src="img/pairing-feedback/g07-invite-sheet-after-join-1s.jpg" width="150"> | <img src="img/pairing-feedback/g08-invite-sheet-after-join-8s.jpg" width="150"> | <img src="img/pairing-feedback/g09-profile-after-closing-sheet.jpg" width="150"> | <img src="img/pairing-feedback/g10-home-after-back.jpg" width="150"> |

- g02 → g04 works: Home swaps to the teal "Lindungi Orang Terdekat" Home with the code card. The swap has no transition and no haptic. The ⇆ icon has no text label.
- g06 → g08: **Ibu joined while the sheet was open, and the sheet did not change.** Only the countdown moved. `FamilyCodeModel.run` already re-reads the members every 5 s (`Features/Pairing/FamilyCodeModel.swift:90-97`), but `InviteSheet` never shows them.
- g09: Ibu appears on Profile only after the sheet is closed, with no message.
- g10: "Keluarga Terlindungi!" + Ibu shows only after Back to Home.

### B. Guardian side: Pribadi → Guardian from Profile (Guardian card and Account mode)

| m02 Profile (Pribadi) | m03 "Menjadi Guardian" → intro | m04 "Mulai", +0.3 s | m05 "Mulai", +2 s |
|---|---|---|---|
| <img src="img/pairing-feedback/m02-profile-personal.jpg" width="150"> | <img src="img/pairing-feedback/m03-intro-from-profile.jpg" width="150"> | <img src="img/pairing-feedback/m04-profile-after-start-0s.jpg" width="150"> | <img src="img/pairing-feedback/m05-profile-after-start-2s.jpg" width="150"> |

| m06 Mode akun (Guardian) | m07 pick Pribadi | m08 "Ganti ke Pribadi", +0.3 s | m09 +2 s | m10 back to Guardian |
|---|---|---|---|---|
| <img src="img/pairing-feedback/m06-account-mode-guardian.jpg" width="150"> | <img src="img/pairing-feedback/m07-account-mode-picked-personal.jpg" width="150"> | <img src="img/pairing-feedback/m08-account-mode-after-switch-0s.jpg" width="150"> | <img src="img/pairing-feedback/m09-account-mode-after-switch-2s.jpg" width="150"> | <img src="img/pairing-feedback/m10-account-mode-back-to-guardian.jpg" width="150"> |

- m04: after "Mulai" the user is back on Profile. The page re-lays itself out with no animation: the card goes, the label says "Mode Guardian", and the stats row is replaced by "Orang yang dilindungi". **The real change (the Guardian Home) is two Backs away.** This matches the first quote.
- m08: "Ganti ke Pribadi" only moves the small "Saat ini" chip and removes the button. Nothing is said on screen. VoiceOver alone hears "Switched to Personal" (`Features/Profile/ProfilePages.swift:270-279`).
- The first switch to Guardian from Account mode opens the intro, then returns to Account mode, where the picker has already snapped back (`selected = nil`, `ProfilePages.swift:272`).

### C. Protected side: Pribadi joins a guardian ("Hubungkan" on Home)

| p01 Home (Pribadi) | p02 "Hubungkan" → Mode akun | p03 "Punya kode undangan?" | p04 code typed |
|---|---|---|---|
| <img src="img/pairing-feedback/p01-home-personal.jpg" width="150"> | <img src="img/pairing-feedback/p02-mode-page.jpg" width="150"> | <img src="img/pairing-feedback/p03-connect-sheet.jpg" width="150"> | <img src="img/pairing-feedback/p04-code-typed.jpg" width="150"> |

| p05 "Hubungkan" → success | p06 "Selanjutnya", +0.4 s | p07 +2 s | p08 settled |
|---|---|---|---|
| <img src="img/pairing-feedback/p05-joined.jpg" width="150"> | <img src="img/pairing-feedback/p06-after-continue-0s.jpg" width="150"> | <img src="img/pairing-feedback/p07-after-continue-2s.jpg" width="150"> | <img src="img/pairing-feedback/p08-home-after-back.jpg" width="150"> |

- This side is the best one today: a full success page "Berhasil Terhubung dengan Ayah!" with a success haptic (`Features/Pairing/ConnectView.swift:42`). "Selanjutnya" goes straight to Home (`router.reset()`, `ProfilePages.swift:400-403`).
- p06 → p07: Home loads with a skeleton. The "Terhubung dengan Ayah" pill then pops in with no animation or haptic. It is small and easy to miss.
- "Hubungkan" on Home first opens **Mode akun** (p02), not the code entry. That is one extra, puzzling step.

## Every point where the user acts and nothing visible happens

| # | Action | What the user sees | Where the change really is | Proof |
|---|---|---|---|---|
| 1 | Profile › "Menjadi Guardian" › intro "Mulai" | Back on Profile, re-laid out silently | Home (2× Back) | m03 → m05 |
| 2 | Profile › Mode akun › "Ganti ke Guardian / Pribadi" | "Saat ini" chip moves, button disappears | Home (2× Back) | m07 → m09, m10 |
| 3 | First Guardian switch from Mode akun | Intro, then Mode akun with the picker snapped back | Home (2× Back) | code, `ProfilePages.swift:270-279` |
| 4 | Guardian's invite sheet open, member joins | **Nothing** (only the timer moves) | Profile after closing, Home after Back | g06 → g08 |
| 5 | Invite sheet closed | Member row fades in on Profile, no message or haptic | Home | g09 |
| 6 | Guardian not on the sheet (other screen, app closed) | Nothing. The backend sends no push on join (`backend/api/src/routes/family.ts:34-40`) | next refresh of Home | code |
| 7 | **Pribadi** invites from Profile "Bagikan undangan" (Family mode off), member joins | Personal Home only loses the "Mode Terawasi" card. Family mode stays off, so the new member is not on Home at all | Family Home, after ⇆ | code, `ProfileView.swift:129-136` |
| 8 | Home ⇆ → "Mulai" | Home swaps instantly, no transition or haptic; ⇆ off has no confirmation | (visible, just abrupt) | g01 → g04 |
| 9 | Protected "Selanjutnya" after joining | Home skeleton, then a small pill pops in | (visible, easy to miss) | p06 → p08 |
| 10 | Guardian disconnects a member (MemberDetail) | Screen pops back, no message | Home / Profile reload | code, `MemberDetailView.swift`, `MemberDetailModel.swift:157-174` |

One flow already gets it right. The **invite card on the empty Family Home** polls, animates the family in, and plays a success haptic when someone joins (`Features/Shield/GuardianHomeView.swift:68, 96-104, 276-279`). The problem is that the Profile routes (#1–#5) never reach it.

## Options (simplest first)

### Option A · Always land on Home and say what changed (recommended) · S

Right after the tap:
- the app closes Profile / the sheet and goes to the **Shield Home**, where the change is already drawn (teal Family Home, the member, the "Terhubung dengan …" pill);
- a **toast** slides in at the top for ~3 s: a check icon, a title and one line;
- the new element gets a **one-time highlight**: a ring pulse, plus a "Baru terhubung" chip on a new member;
- a **success haptic** plays and VoiceOver reads the toast text.

| Action | Toast (ID / EN) | Highlight |
|---|---|---|
| Intro "Mulai" / "Ganti ke Guardian" (#1–#3, #8) | "Mode Guardian aktif · Bagikan kode ini ke keluarga" / "Guardian mode on · Share this code with your family", with an **"Undang"** button (see the decision below) | the code card + "Bagikan" |
| "Ganti ke Pribadi" (#2, #8) | "Mode Pribadi aktif · Perlindunganmu tetap menyala" / "Personal mode on · Your protection stays on" | none |
| Member joins while the invite sheet is open (#4, #5) | "Ibu sudah terhubung · Kamu sekarang ikut menjaga Ibu" / "Ibu is connected · You now help protect Ibu" | Ibu's avatar + "Baru terhubung" |
| Pribadi inviter, member joins (#7) | same, and Home switches to Family (see decision 1) | the member |
| Protected "Selanjutnya" (#9) | "Terhubung dengan Ayah · Ayah akan dikabari saat ada situs berbahaya" / "Connected with Ayah · Ayah will hear about dangerous sites" | the pill |
| Member disconnected (#10) | "Ibu tidak lagi terhubung" / "Ibu is no longer connected" | none |

What changes (all inside `ios/ShooApp/`):
- `App/Router.swift`: add `homeNotice: HomeNotice?` (a small enum), set together with `reset()`.
- New `Components/HomeNotice.swift`: the toast, shown as an overlay in `Features/Main/MainTabView.swift` next to `InviteNoticeBanner`. It plays `.sensoryFeedback(.success)`, posts an `AccessibilityNotification.Announcement`, hides after ~3 s, and respects Reduce Motion.
- `App/AppEnvironment.swift` `startGuardian()` and `Features/Profile/ProfilePages.swift` mode switch: call `router.reset()` + set the notice.
- `Features/Pairing/InviteSheet.swift`: `FamilyCodeModel` already polls the members. When the count goes up, dismiss the sheet, reset, and set `memberJoined(name)`.
- `Features/Shield/GuardianHomeView.swift`: reuse the existing join hand-over animation (`joinAnimates`) and add the member ring + chip. `Features/Shield/ProtectedShieldView.swift`: animate the pill in.
- `Features/Profile/MemberDetailView.swift`: set the notice after a disconnect.
- `Resources/Localizable.xcstrings`: ~6 strings, EN + ID.
- UI tests: `LivePairingUITests`, `PairingUITests`, and `GuardianUITests` now expect Profile to close.

Backend: none. `contracts/`: none.
Limit: the guardian still learns of a join only while the app is open (#6). Option C covers that.

### Option B · A success page after each action · M

Reuse `OnboardingSuccessPage`, the page the Protected side already shows ("Berhasil Terhubung dengan Ayah!", p05):
- invite sheet: when someone joins, the sheet turns into "Ibu sudah terhubung!" with one button, "Lihat di Beranda";
- after "Mulai" / "Ganti ke Guardian": "Kamu sekarang Guardian" with "Undang keluarga" (opens the invite) and "Nanti";
- "Ganti ke Pribadi": "Kembali ke mode Pribadi" with "OK".

This is unmissable and fits the existing celebration style. The costs:
- one extra tap every time;
- 3 new pages that need Figma frames and copy from the designer;
- it still needs Option A's "go to Home" step after the button.

Screens: `InviteSheet`, `GuardianIntroView` / `MainTabView`, `ProfilePages`. Backend and `contracts/`: none.

### Option C · Tell the guardian wherever they are · M–L, needs a contract change

When `POST /family/join` succeeds, the backend sends the guardian a family push (the same mechanism as `memberLeft`, `backend/api/src/services/push/messages.ts:18`), e.g. "Ibu sudah terhubung dengan Shoo".
- App open: the push already triggers a reload (`pushesWhileOpen`, `GuardianHomeView.swift:106-108`) and would show Option A's toast.
- App closed: a lock-screen notification.

This fixes #6, the only case A and B cannot reach. It needs a new push kind in `contracts/api.md`, so it needs a GitHub issue to the lead (rule 7). **Not opened.** Suggested title:
**`GD-04: add a "memberJoined" family push to the guardian`**. It would also be a chance to write down the other family pushes (`remind`, `disconnected`, `memberLeft`), which `messages.ts` still marks as a "proposed contract addition".

This is a follow-up to A, not a replacement for it.

## Recommendation: Option A

It is the smallest change that answers both quotes. Every role or pairing tap ends on Home, the screen that actually changed, with a toast that names the change. No backend, no contract, no new pages from the designer. Most of the logic already exists: `router.reset()`, the 5 s member poll, Home's join animation and haptic.

Rough mock, drawn over the real screenshots. ① is the new toast, ② the one-time highlight.

| After a member joins (Guardian) | After "Mulai" / "Ganti ke Guardian" | After "Selanjutnya" (Protected) |
|---|---|---|
| <img src="img/pairing-feedback/mock-1-guardian-member-joined.jpg" width="220"> | <img src="img/pairing-feedback/mock-2-became-guardian.jpg" width="220"> | <img src="img/pairing-feedback/mock-3-protected-connected.jpg" width="220"> |
| Sheet closes by itself, Home shows Ibu with a green ring + "Baru terhubung" chip, toast "Ibu sudah terhubung", success haptic. | Profile / Mode akun closes, Home shows the teal Family Home, the code card glows once, toast "Mode Guardian aktif". | Home settles, the pill pulses once, toast "Terhubung dengan Ayah". |

Toast details for whoever builds it: white card, 12 pt below the top bar, so it never covers ⇆ or the avatar. One row, vertically centred: the check icon in the mode colour on the left (green for a connection, teal for Guardian), then the title with its line under it, then the optional button ("Undang") on the right. It slides down with the app's `StateMotion` and fades out after 3 s. VoiceOver reads the title and line once.

### Decided (Alief, 20 Nov 2026): no automatic invite sheet after "Ganti ke Guardian"

After switching to Guardian, no invite sheet opens by itself. An automatic sheet would cover the very change the user should see (the teal Home and the toast). It would also repeat the code card that the empty Guardian Home already shows, and it would push people who only wanted to look around. Instead, inviting is made one tap away:

1. **"Bagikan" becomes the main button on the empty Guardian Home:** full width, under the code card, with the share icon. It glows once together with the code card. "Salin" becomes a text button, "Salin kode".
2. **The "Mode Guardian aktif" toast gets an "Undang" button.**
3. **Both open the iOS share sheet directly** (Messages, WhatsApp, Mail, Salin), carrying the invite link and the code. They do not go through the "Kirim Undangan" sheet from Profile. The Home "Share" button already works this way today: `ShareLink(item: FamilyCodeModel.inviteText(…))` (`Features/Shield/GuardianHomeView.swift:803`). So "Undang" reuses that, and "Bagikan" is a restyle, not new logic.
4. Mode akun's button stays "Ganti ke Guardian".

This adds to Option A's file list: `GuardianHomeView.swift` (`InviteCodeCard`: the button layout + the one-time glow on Bagikan) and `Components/HomeNotice.swift` (an optional action on the toast, here a `ShareLink`). It also adds 1–2 strings ("Undang", "Salin kode", EN + ID). Backend and `contracts/`: none.

### Figma (flow screens, 20 Nov 2026)

The Option A flows, plus the ⇆ decision (no ⇆ before Guardian, then a one-time tip) and the share-sheet decision, are drawn in the Figma file *[CH7] Shoo Scam App*, page High Fidelity, section **"Alief Revishit Flow"** (`2364:3633`). Every frame there is a new copy of an existing frame, and the original frames are untouched. The section holds 7 flows:

| # | Flow | Frames |
|---|---|---|
| 1 | Pribadi Home without ⇆ (Alief's card) → "Menjadi Guardian" (+ To be guardian) → Guardian Home with the one-time ⇆ tip → tip closed: toast + Undang → iOS share sheet | `2368:13129` → `2368:13263` → `2364:3800` → `2364:12677` |
| 2 | Profile "Menjadi Guardian" → To be guardian → Guardian Home → share sheet | `2364:3921` → `2364:4034` → `2364:4085` → `2364:12827` |
| 3 | Mode akun → Guardian → Guardian Home → share sheet | `2364:4204` → `2364:4248` → `2364:12977` |
| 4 | Mode akun → Pribadi | `2364:4366` → `2364:4410` |
| 5 | Guardian: a member joins | `2364:4544` → `2364:4656` |
| 6 | Protected: connected | `2364:4805` → `2364:4840` |
| 7 | Guardian disconnects a member | `2364:4974` → `2364:5111` |

The Figma frames use the names already in the file (Renatta, Putri, Syahnaz) instead of this doc's Ibu / Ayah.

Notes on the ⇆ frames:
- Flow 1's first frame is a copy of `1382:10567` with ⇆ hidden in the copy. Alief's card `2366:10994` and the original frame are untouched. The tip is the group `2368:13380` in `2368:13263`.
- Flows 2 and 3 show the toast frame. For someone who becomes Guardian for the first time, the tip frame comes first, as in flow 1.
- Flow 4's Pribadi Home keeps ⇆, because that user has already been Guardian.

### Decisions for Alief before building

1. **#7 Pribadi inviter.** When someone joins a Pribadi user who invited from Profile, should Family mode turn on by itself, so the member shows on Home? The proposal assumes **yes**: inviting someone already means "I want to protect them". The alternative is a toast with a "Lihat keluarga" button that flips ⇆.
2. **Home "Hubungkan" (p02).** Should it open the code entry directly, not Mode akun first? Today it goes through Mode akun on purpose: that page checks first that nobody is looked after (comment at `GuardianHomeView.swift:252-253`). A direct route (`router.showJoinFamily()`) would have to keep that check. The server's `has_members` answer already arrives in the join sheet. This is optional and not needed for A.

## Side note: how a first-time user can learn that Guardian exists

Today:
- onboarding registers everyone as Pribadi and never mentions Guardian (`Features/Onboarding/OnboardingModel.swift:155-156`);
- Pribadi Home has only the **unlabelled ⇆ icon**, plus a "Mode Terawasi · Tidak yakin?" card that points the other way (become Protected, p01);
- the only explainer is the "Mode Guardian · Lindungi orang terdekat" card on **Profile** (m02), which one tap on X hides for good.

### Decided (Alief, 20 Nov 2026): ⇆ appears only after the user has been Guardian once

Alief: *"pertama kali, tombol ⇆ gk ada, itu baru muncul setelah dia udah jadi guardian"*. This replaces the earlier decision that the first ⇆ tap opens Mode akun. That flow is dropped.

<img src="img/pairing-feedback/figma-flow-1.jpg" width="700">

*Figma flow 1, left to right: Pribadi Home without ⇆ (Alief's card) → Guardian Home with the one-time ⇆ tip → the same Home after the tip closes (toast + Undang) → iOS share sheet.*

1. **No ⇆ on Pribadi Home until the user has been Guardian once.** Someone who never was Guardian has nothing to switch to, so the icon only confused (row #8). The avatar stays top right; it does not move left into the empty spot. `HomeTopBar` already hides ⇆ when `onSwitch` is `nil` (`Features/Shield/HomeChrome.swift:338-339`, used that way for protected/Home), so Home passes `nil` while the flag below is false.
2. **Pribadi Home gets Alief's card** "Jadi Penjaga · Lindungi orang terdekat" (Figma `2366:10994`, in the HOME frame `1382:10567`), under "Anda Terlindungi!". It is used as designed. "Menjadi Guardian" calls `env.requestFamilyMode()`, the same as Profile's card: the first time, "To be guardian" shows, and "Mulai" lands on Guardian Home (`App/AppEnvironment.swift:505-519`). The card shows only while the user has never been Guardian; after that, ⇆ takes its place. **Recommendation, not yet confirmed:** "Tutup" (×) uses the same `guardianCardDismissed` flag as Profile's card, so one "not now" hides both.
3. **On the first arrival at Guardian Home, a tip points at the ⇆ that just appeared.** It follows Alief's reference: a white rounded card right under ⇆ with a small pointer, a teal tile with a white ⇆, a bold "Mode Penjaga" and a grey "Riwayat link dari keluarga". The English source strings are "Guardian mode" / "Link history from your family" (2 strings, EN + ID).
   - **How it closes:** a tap anywhere on the screen, ⇆ included. That tap only closes the tip. It does not switch the mode or press what is underneath, the same as an iOS popover tip, so a tap aimed at the tip never flips the user straight back to Pribadi. There is no dim background and no timer, so the tip stays until it is seen. VoiceOver reads it once when it appears, and the escape gesture also closes it.
   - **Shown once:** a new `AppSettings` Bool `guardianSwitchTipSeen` (key `settings.guardianSwitchTipSeen`, UserDefaults on the device), set to `true` when the tip closes.
     - Installs that already have `guardianIntroSeen == true` start as seen, because they already know ⇆.
     - The demo starts with it `true` and saves and restores it like `guardianIntroSeen` (`DemoReturn`, `App/AppSettings.swift:190-233`). `reset()` clears it (`AppSettings.swift:290-292`).
     - Nothing goes to the server, and nothing changes in `contracts/`.
   - **Every path counts:** Home card (flow 1), Profile card (flow 2), Mode akun (flow 3). All three end in `startGuardian()`, which sets a router flag for the tip when `guardianSwitchTipSeen` is false.
   - **Why not TipKit:** TipKit (iOS 17+) does popover tips and remembers "seen" itself. But it draws the system popover, not Alief's white card with the teal tile, and it keeps its own datastore that `reset()` and the demo restore would also have to clear. One small overlay and one flag match how the app already stores its first-time flags.
4. **Order with the toast: the tip first, the toast after the tip closes.** Both sit at the top, so they never show together. While the tip is up, the "Mode Guardian aktif" toast (with "Undang") and the one-time glow on the code card and "Bagikan" wait. A tap closes the tip, and then they run as in Option A. Why this order:
   - The tip waits for a tap, while the toast leaves by itself after 3 s. With the toast first, the tip would appear about 3 s later. By then the user may be reading the code card or may have tapped "Undang", and a tip that pops up late feels like an interruption.
   - Nothing is silent while the tip is up: the teal Home and "Mode Penjaga" already show that the mode changed.
   - Rejected: showing both at once with the toast moved lower, because the two cards compete and the toast covers the code card. Also rejected: no toast the first time, because it loses the "Undang" shortcut, which is the next step.
   - Every later switch (⇆, Mode akun, Profile) has no tip, and the toast shows right away.
5. **Unchanged:** "Bagikan" is the main button, "Undang" and "Bagikan" open the iOS share sheet, and no invite sheet opens by itself.

**Storing "has been Guardian once":** reuse `guardianIntroSeen`, no new flag. It is set only by `startGuardian()` (the "Mulai" on "To be guardian") and by the demo (`AppEnvironment.swift:515-519`, `AppSettings.swift:215`). So it is already `true` exactly when the user has turned Guardian on at least once. Closing "To be guardian" without "Mulai" leaves it `false`, and ⇆ stays hidden, which is correct. The Activity tab's "Family: Off" toggle (`FamilyModeToggle`, `Features/Main/MainTabView.swift:129-157`) is the same switch in text form. It should follow the same rule and stay hidden until then (recommendation).

Effort: S–M. Files:
- `App/AppSettings.swift` (the tip flag);
- `App/AppEnvironment.swift` (`startGuardian()` sets the tip flag);
- `App/Router.swift` (tip presented);
- `Features/Shield/GuardianHomeView.swift` (`onSwitch: nil` while never Guardian, the new card, the tip overlay, the toast waiting for the tip);
- `Features/Main/MainTabView.swift` (the toggle);
- `Resources/Localizable.xcstrings`.

UI tests that turn Guardian on from ⇆ on a fresh install (`becomeGuardian()`, `UITests/UITestSupport.swift:155-161`, used by `LivePairingUITests` and others) must tap the Home card's "Menjadi Guardian" instead and close the tip with one tap. A `-settings.guardianSwitchTipSeen YES` launch argument can skip the tip where a test doesn't care about it.

## Not covered

- Haptics, animations and VoiceOver were read from code, not felt or heard. Screenshots cannot show them.
- Rows #6, #7 and #10 come from the code. They were not run on the simulators.
- Only iPhone 17 (iOS 26.5) and Bahasa Indonesia were run. English and the iPhone SE size were not checked.
