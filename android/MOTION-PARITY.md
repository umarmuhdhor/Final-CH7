# Motion parity: iOS (SwiftUI) → Android (Compose)

Every animation in `ios/ShooApp` (App, Components, every `Features/*` folder) paired with its Kotlin counterpart.
Audited 2026-11-18 on `feat/android-app`.

**Summary: 284 sites. 158 MATCH · 68 FIXED · 58 APPROXIMATED.**

| Area | Match | Fixed | Approximated |
|---|---|---|---|
| App, Components, Main (navigation, tabs, sheets) | 23 | 2 | 9 |
| Shield | 28 | 21 | 16 |
| Onboarding | 31 | 11 | 4 |
| Pairing | 30 | 14 | 6 |
| Detail + Activity | 21 | 10 | 9 |
| Profile | 25 | 10 | 14 |

- **MATCH**: same timing, curve, animated properties, transition and Reduce Motion behaviour.
- **FIXED**: the Kotlin differed or was missing; changed in this audit to match.
- **APPROXIMATED**: no Compose equivalent; the note says exactly what differs.

## Curves (`components/Motion.kt`)

| SwiftUI | Compose helper | Mapping |
|---|---|---|
| `.spring(duration: d, bounce: b)` | `shooSpring(d, b)` | stiffness = (2π / d)², damping ratio = 1 − b (b ≥ 0) or 1 / (1 + b) (b < 0), mass 1 |
| `.spring(response: r, dampingFraction: f)` | `shooSpringResponse(r, f)` | stiffness = (2π / r)², damping ratio = f |
| `.default`, `withAnimation { }`, `.spring()` | `shooDefault()` | spring(0.55, 0) |
| `.smooth` / `.snappy` / `.bouncy` (`duration:`) | `shooSmooth` / `shooSnappy` / `shooBouncy` | bounce 0 / 0.15 / 0.3, default 0.5 s |
| `.easeOut` / `.easeIn` / `.easeInOut` / `.linear` (`duration:`) | `shooEaseOut` / `shooEaseIn` / `shooEaseInOut` / `shooLinear` | cubic-bezier (0, 0, 0.58, 1) / (0.42, 0, 1, 1) / (0.42, 0, 0.58, 1) / linear, default 0.35 s |
| `animation.delay(d)` | `spec.withDelay(d)` (any spec, springs too), or `swiftDelay(d)` before `animateTo` | holds the start value for d, then runs the spec |
| `\.shooReduceMotion` | `LocalReduceMotion.current` | usually a plain short fade instead of movement |

Helper fixes in this audit: durations are now rounded to the millisecond instead of truncated (0.29 s was 289 ms);
added `shooSpringResponse`, `shooDefault` and `withDelay`. Unit-tested in `app/src/test/.../MotionTest.kt`.

## Known app-wide differences (not counted per site)

- **Sheets** (`ModalBottomSheet`): Material's sheet spring and scrim fade. UIKit's sheet curve can't be set, because
  `rememberModalBottomSheetState` takes no animation spec.
- **Symbol effects** (`.bounce`, `.wiggle`, `.pulse`, `.replace`): Compose has no SF Symbols. Bounce is a scale up
  then a spring back, wiggle is a short rotation shake, and replace is a scale plus a cross-fade.
- **`.numericText()`**: the changed digits roll with the same spec. iOS's per-digit blur is not drawn.
- **`.buttonStyle(.plain)` press dim**: iOS dims a plain button while it's held; Android buttons use
  `indication = null`.
- **Paged `TabView` swipes** (Splash slides, Evidence carousel): `HorizontalPager` fling and snap physics.
- **Navigation push/pop**: the UIKit curve is private, so Android uses spring(0.45, 0) with a 30 % parallax and no
  dimming. Android's back gesture is not finger-tracked.

## App, Components, Main

| Swift (ios/ShooApp/…) | Kotlin (android/app/src/main/java/com/shoo/app/…) | Animation | Status | Note |
|---|---|---|---|---|
| App/RootView.swift:35-41 | app/RootView.kt:80 | phase screens `.transition(.opacity)` (session expired, consent, main, onboarding) | MATCH | `Crossfade`: old fades out while new fades in, same as SwiftUI's opacity in/out pair |
| App/RootView.swift:46 | app/RootView.kt:85 | phase cross-fade `.easeOut(0.3)` / 0.2 RM | MATCH | now `shooEaseOut(...)` (was Compose `EaseOut`, same points 0,0,0.58,1) |
| App/RootView.swift:49 + Features/Onboarding/LaunchSplash.swift:46 | app/RootView.kt:71 | content `.opacity(launchSplash == .showing ? 0 : 1)` inside the splash's `withAnimation(.easeOut(0.3 / 0.2 RM))` | FIXED | the content snapped to 1 under the fading splash; now fades in on the same easeOut so the two cross-fade like iOS |
| Components/StateViews.swift:10-11 | components/StateViews.kt:79 | `StateMotion.enter`: spring(0.32, 0.18) / easeOut 0.2 RM | MATCH | |
| Components/StateViews.swift:15-17 | components/StateViews.kt:85,95 | `StateMotion.transition`: opacity + move(edge) + scale 0.98 / opacity RM | MATCH | slide by full height, edge via `fromBottom`/`toBottom` |
| Components/StateViews.swift:33 | components/StateViews.kt:109 | `stateEntrance(delay:)`: opacity 0→1, y 10→0, enter spec `.delay(d)` | MATCH | coroutine delay then spring; RM keeps y 0 |
| Components/StateViews.swift:118 | components/StateViews.kt:281,289 | notice action: label opacity + spinner insert/remove under `.easeOut(0.15)` on isRunning | FIXED | label fade matched; spinner popped in/out, now `AnimatedVisibility` fade easeOut 0.15 |
| Components/StateViews.swift:146 | components/StateViews.kt:152,235 | `.symbolEffect(.wiggle.byLayer)` on nudge (error tone) | APPROXIMATED | no symbol effects in Compose: rotation −12°,10°,−8°,6°,0° at easeInOut 0.08 each; no per-layer motion |
| Components/StateViews.swift:148 | components/StateViews.kt:152,235 | `.symbolEffect(.bounce)` on nudge (info tone) | APPROXIMATED | scale 1→1.18 (easeOut 0.12) → spring(0.3, 0.4) back; iOS bounce curve is private |
| Components/StateViews.swift:159-161 | components/StateViews.kt:130 | `PressScaleButtonStyle`: 0.96 + 0.7 opacity, easeOut 0.12; RM dims only | MATCH | `Modifier.pressScale` |
| Components/StateViews.swift:188 | components/StateViews.kt:355 | `StateMessage` symbol `.bounce` when shown (none with RM) | APPROXIMATED | same scale stand-in as above |
| Components/StateViews.swift:191,211 | components/StateViews.kt:325 | `StateMessage` tile scale 0.85→1 + opacity, spring(0.35, 0.3) / easeOut 0.2 RM | MATCH | |
| Components/StateViews.swift:237 | components/StateViews.kt:378 | `Shimmer`: band 0.6w, offset phase·1.6w, linear 1.3 s repeatForever(no reverse), off with RM | MATCH | |
| Components/ShieldPulseLoader.swift:19 | components/ShieldPulseLoader.kt:36 | `SoftPulse` TimelineView: 3 discs, phase = t/period + i/3, fade-in 12 %, alpha·(1−p)^1.2; still at 0.15·period RM | MATCH | frame clock instead of wall clock: same motion, different start phase |
| Components/ShieldPulseLoader.swift:69 | components/ShieldPulseLoader.kt:104 | `LoaderReplacementFade`: opacity 0→1 easeOut 0.2 on appear | MATCH | |
| Components/HalftoneShield.swift:30 | components/HalftoneShield.kt:72 | TimelineView paused when off / RM (still picture, breath 0.5) | MATCH | frame-clock loop stops when `moving` is false |
| Components/HalftoneShield.swift:46-68 | components/HalftoneShield.kt:97 | breath (1−cos(tπ/2.4))/2: glow opacity 0.1+0.06b, scale 0.96+0.08b, shadow 0.27+0.16b, blur 15+4b | MATCH | |
| Components/HalftoneShield.swift:130-150 | components/HalftoneShield.kt:175 | glass sweep: every 5 s, 0.9 s pass, 0.45w band rotated 20°, plusLighter | MATCH | `BlendMode.Plus` |
| Components/HalftoneShield.swift:174-195 | components/HalftoneShield.kt:222 | dot wave: 2.6 s rise + 1.4 s rest, gaussian boost r·(1+0.35b), opacity 0.85+0.15b | MATCH | |
| Components/StateHeroPage.swift:65-66,119 | components/StateHeroPage.kt:116 | shield scale 0.86→1 + opacity, spring(0.35, 0.3) / easeOut 0.2 RM (no scale) | MATCH | |
| Components/StateHeroPage.swift:63 | features/shield/HomeChrome.kt:523 | `HeroPulse` (SoftPulse period 9 + three still rings) | MATCH | |
| Components/StateHeroPage.swift:115 | components/StateHeroPage.kt:197 | footer `.stateEntrance(delay: 0.24)` | MATCH | |
| Components/StateHeroPage.swift:137 | components/StateHeroPage.kt:242 | chip `.stateEntrance(delay: 0.06)` | MATCH | |
| Components/StateHeroPage.swift:155 | components/StateHeroPage.kt:249 | title/message `.stateEntrance(delay: 0.1)` | MATCH | |
| Components/StateHeroPage.swift:157 | components/StateHeroPage.kt:270 | content `.stateEntrance(delay: 0.16)` | MATCH | |
| Features/Main/MainTabView.swift:10 | features/main/MainTabView.kt:166 | tab switch (TabView selection) | MATCH | instant swap, both tabs kept alive, like UITabBarController |
| Features/Main/MainTabView.swift:10 (system tab bar) | features/main/MainTabView.kt:463 | iOS 26 tab bar selection highlight moving between tabs | APPROXIMATED | Liquid Glass morph is system-private; pill offset spring(0.35, 0.2) / easeInOut 0.2 RM |
| Features/Main/MainTabView.swift:11,21 (NavigationStack push) | features/main/MainTabView.kt:390 | push: new screen from trailing edge, screen under moves ~30 % left | APPROXIMATED | UIKit push curve is private: spring(0.45, 0), under-screen −30 %, no dimming shadow; RM: 0.2 s cross-fade (iOS slides) |
| Features/Main/MainTabView.swift:11,21 (NavigationStack pop) | features/main/MainTabView.kt:139,390 | pop: reverse slide; edge-swipe back | APPROXIMATED | same spring reversed; Android back gesture is not interactive (no finger-tracked swipe) |
| Features/Detail/DetailView.swift:61 etc. `.toolbar(.hidden, for: .tabBar)` | features/main/MainTabView.kt:186 | tab bar hides on push, returns on pop | APPROXIMATED | iOS animates it with the push; Android fades + slides half its height (smooth 0.35 in / 0.25 out, easeInOut 0.2 RM) |
| Features/Main/MainTabView.swift:33-34 | features/main/MainTabView.kt:197 | demo banner appears/disappears | MATCH | no animation on either side |
| Features/Main/MainTabView.swift:41,44 | features/main/MainTabView.kt:204 | invite notice `.move(edge: .top) + .opacity`, `.smooth` / easeInOut 0.2 RM | MATCH | slide by own height + fade, shooSmooth() |
| Features/Main/MainTabView.swift:48,56 | features/main/MainTabView.kt:607 | Connect and Join sheets present/dismiss | APPROXIMATED | `ModalBottomSheet` uses Material's sheet spring; no hook to set UIKit's sheet curve |
| Features/Main/MainTabView.swift:61 | features/main/MainTabView.kt:214 | Guardian intro `.fullScreenCover` slide up / down | APPROXIMATED | smooth(0.5) slide by full height stands in for UIKit's cover curve; RM: 0.2 s fade |

## Shield

| Swift (ios/ShooApp/…) | Kotlin (android/app/src/main/java/com/shoo/app/…) | Animation | Status | Note |
|---|---|---|---|---|
| Features/Shield/GuardianHomeView.swift:43 | features/shield/GuardianHomeView.kt:185 | `handOver` spec: .smooth(0.3) / easeInOut 0.2 RM | MATCH | same spec, now defined once at screen level |
| Features/Shield/GuardianHomeView.swift:71 | features/shield/GuardianHomeView.kt:188 | `.animation(handOver, value: verdictSaves)` on the whole page (hero, sheet, gap, below) | FIXED | was only on the family sheet; now `pageAnimation` (changedNow(verdictSaves)) also drives hero headline/shield and the gap above "below" |
| Features/Shield/GuardianHomeView.swift:73 | features/shield/GuardianHomeView.kt:188 | `.animation(joinAnimates ? handOver : nil, value: hasNoFamily)` | FIXED | invite → family now also animates the hero (headline, shield place, rings) and the gap, not only the sheet |
| Features/Shield/GuardianHomeView.swift:74 | features/shield/GuardianHomeView.kt:558 | `.animation(StateMotion.enter, value: refreshFailed)` on the page (personal) | FIXED | notice used StateMotion transition but the rows under it jumped; `stateNoticeEnter/Exit` adds unclipped expand/shrink with the same spring (easeOut 0.2 RM) |
| Features/Shield/GuardianHomeView.swift:360 | features/shield/GuardianHomeView.kt:599 | refresh notice `.transition(StateMotion.transition(edge: .top))` (family, below) | FIXED | same as above: StateMotion rise/fade/scale kept, layout below now glides |
| Features/Shield/GuardianHomeView.swift:90 | features/shield/ShieldSupport.kt:239 | top scrim opacity, easeOut 0.2 on isHeroHidden | MATCH | |
| Features/Shield/GuardianHomeView.swift:134 | features/shield/ShieldSupport.kt:320 | Turn-on `.sheet` present/dismiss | APPROXIMATED | ModalBottomSheet's Material spring; no spec hook for UIKit's sheet curve |
| Features/Shield/GuardianHomeView.swift:173 | features/shield/GuardianHomeView.kt:356 | personal hero (style/title/shield on-off) | MATCH | changes outside an animated update jump on both; hero now gets `animation` (null unless a keyed update) — was a default 300 ms Crossfade on every title change |
| Features/Shield/GuardianHomeView.swift:197 | features/shield/GuardianHomeView.kt:391 | family hero branches (failed/loading/empty/pending/protected) swapped in an animated update | APPROXIMATED | iOS cross-fades the whole hero (default .opacity transition); Android keeps one teal backdrop and cross-fades the headline+subtitle, eases shield top/scale/title top/bottom gap and fades the rings, same spec. Whole-hero fade not used: the backdrop draws outside its bounds and an alpha layer would clip it |
| Features/Shield/GuardianHomeView.swift:206 | features/shield/GuardianHomeView.kt:391 | hasNoFamily hero subtitle / no rings (familyEmpty layout) | FIXED | subtitle cross-fades with the headline, rings fade in/out, layout numbers ease (was a hard swap) |
| Features/Shield/GuardianHomeView.swift:233 | features/shield/GuardianHomeView.kt:431 | loading skeleton shimmer (linear 1.3 s repeatForever) | MATCH | via components `shimmering` |
| Features/Shield/GuardianHomeView.swift:249 | features/shield/GuardianHomeView.kt:454 | load-error card `.stateEntrance()` | MATCH | |
| Features/Shield/GuardianHomeView.swift:268 | features/shield/GuardianHomeView.kt:563 | "Mode Terawasi" close: withAnimation(.easeOut 0.2) + `.transition(.opacity)` | FIXED | fade kept; the slot now shrinks (unclipped, easeOut 0.2) so the list moves up with it, and the 0/3 and 35/37 gaps ease (`dismissal`) instead of jumping after the fade |
| Features/Shield/GuardianHomeView.swift:281 | features/shield/GuardianHomeView.kt:581 | RecentActivity / LatestScams top padding change in the dismiss transaction | FIXED | animatedOrSnapped with easeOut 0.2 only for the dismissal |
| Features/Shield/GuardianHomeView.swift:289 | features/shield/GuardianHomeView.kt:494 | invite card → family members (join) | MATCH | AnimatedContent fade, smooth 0.3 / easeInOut 0.2, only when joinAnimates |
| Features/Shield/GuardianHomeView.swift:311 | features/shield/GuardianHomeView.kt:305 | "Why is it safe?" `.sheet` | APPROXIMATED | ModalBottomSheet's Material spring |
| Features/Shield/GuardianHomeView.swift:318 | features/shield/GuardianHomeView.kt:473 | pending card `.id(scan.id)` + `.transition(.opacity.combined(.scale(0.97)))` / .opacity RM | FIXED | scale was applied to the invite and members row too; now only the pending card scales, the others fade (SwiftUI default); sheet height now eases with the same spec (SizeTransform, was Compose's default spring) |
| Features/Shield/GuardianHomeView.swift:322 | features/shield/GuardianHomeView.kt:473 | members row in/out on hand-over | MATCH | fade only, smooth 0.3 / easeInOut 0.2 |
| Features/Shield/GuardianHomeView.swift:520 | features/shield/GuardianHomeView.kt:797 | scroll to "Couldn't save": withAnimation(.smooth 0.3 / nil RM) { scrollTo } | APPROXIMATED | bringIntoView uses Compose's default scroll spring and also scrolls smoothly with Reduce Motion |
| Features/Shield/GuardianHomeView.swift:577 | features/shield/GuardianHomeView.kt:865 | buttons grayscale 1 + opacity 0.5 when notAllowed, under StateMotion.enter | FIXED | was a snap; now `dim` animates with StateMotion.enter (saturation and alpha) |
| Features/Shield/GuardianHomeView.swift:588 | features/shield/GuardianHomeView.kt:895 | "Couldn't save" notice `.transition(StateMotion.transition)` | MATCH | |
| Features/Shield/GuardianHomeView.swift:595 | features/shield/GuardianHomeView.kt:912 | "Can't be marked yet" notice `.transition(StateMotion.transition)` | MATCH | |
| Features/Shield/GuardianHomeView.swift:599 | features/shield/GuardianHomeView.kt:820 | `.animation(StateMotion.enter, value: failed)` (card height, bottom padding) | FIXED | animateContentSize used Compose's default spring; now spring(0.32, 0.18) / easeOut 0.2 RM |
| Features/Shield/GuardianHomeView.swift:600 | features/shield/GuardianHomeView.kt:820 | `.animation(StateMotion.enter, value: notAllowed)` | FIXED | as above |
| Features/Shield/GuardianHomeView.swift:432 | features/shield/GuardianHomeView.kt:826 | pending card tap (`.buttonStyle(.plain)`) | APPROXIMATED | iOS plain style dims while pressed; Android `indication = null` (app-wide pattern) |
| Features/Shield/GuardianHomeView.swift:746 | features/shield/GuardianHomeView.kt:1023 | DecisionPressStyle: scale 0.97 / opacity 0.8 RM, easeOut 0.15 | MATCH | |
| Features/Shield/GuardianHomeView.swift:804 | features/shield/GuardianHomeView.kt:1150 | QR spinner opacity (loading) | MATCH | no animation on either |
| Features/Shield/GuardianHomeView.swift:839 | features/shield/GuardianHomeView.kt:1287 | Copy → Copied `.contentTransition(.opacity)` | FIXED | Crossfade used the default 300 ms tween; now snappy 0.3 / easeInOut 0.2 RM |
| Features/Shield/GuardianHomeView.swift:852 | features/shield/GuardianHomeView.kt:1271 | `.animation(snappy 0.3 / easeInOut 0.2, value: copied)` on the row (pill width) | FIXED | animateContentSize sat on the Row, so the capsule jumped; now on the pill. Copied → Copy shrinks after the label fade ends (Crossfade keeps both labels' max width while fading) |
| Features/Shield/HomeChrome.swift:168 | features/shield/HomeChrome.kt:346 | HeroPulse shown per layout.showsRings | FIXED | fades with the hero's animation in an animated update (was a hard swap) |
| Features/Shield/HomeChrome.swift:170 | features/shield/HomeChrome.kt:353 | shield scaleEffect/offset per layout | FIXED | eases with the caller's animation; jumps otherwise |
| Features/Shield/HomeChrome.swift:169 | features/shield/HomeChrome.kt:353 | HalftoneShield isOn / tint change in an animated update | APPROXIMATED | iOS interpolates the palette colours inside the shield; Android cross-fades two shields (OverflowCrossfade, alpha per draw call so the glow isn't clipped) |
| Features/Shield/HomeChrome.swift:184 | features/shield/HomeChrome.kt:369 | headline `.contentTransition(.opacity)` | FIXED | Crossfade always ran a default 300 ms tween; now the caller's spec, and instant outside an animated update ("no effect otherwise") |
| Features/Shield/HomeChrome.swift:268 | features/shield/HomeChrome.kt:533 | HeroPulse SoftPulse(120…368, peak 0.2, period 9) | MATCH | params identical; SoftPulse itself is a component (parent's table) |
| Features/Shield/HomeChrome.swift:360 | features/shield/HomeChrome.kt:619 | ⇆ / profile / See all / rows / Supervised buttons (`.buttonStyle(.plain)`) | APPROXIMATED | iOS plain style dims while pressed; Android uses `indication = null` |
| Features/Shield/HomeChrome.swift:746 | features/shield/HomeChrome.kt:1092 | empty state shield scale 0.85→1 + opacity, spring(response 0.5, damping 0.72) / easeOut 0.2 RM | MATCH | now via shooSpringResponse (same numbers as the inline spring) |
| Features/Shield/HomeChrome.swift:778 | features/shield/HomeChrome.kt:1107 | float 4 pt, easeInOut 2.4 repeatForever autoreverse, delay 0.5 | MATCH | StartOffset delay once, like `.repeatForever().delay()` |
| Features/Shield/HomeChrome.swift:779 | features/shield/HomeChrome.kt:1117 | ripple ring 1→1.45, 0.7→0, easeOut 2.6 repeatForever, delay 0.5 | MATCH | |
| Features/Shield/HomeChrome.swift:784 | features/shield/HomeChrome.kt:1097 | Reduce Motion turned on: loops stop at rest | MATCH | infinite transition leaves composition, values 0 |
| Features/Shield/HomeChrome.swift:804 | features/shield/HomeChrome.kt:1192 | RiseIn: opacity + 6 pt, easeOut 0.35 delay 0.12 / 0.2; easeOut 0.2 RM | MATCH | |
| Features/Shield/ProtectedShieldView.swift:38 | features/shield/ProtectedShieldView.kt:272 | hero `.animation(isLoaded ? smooth 0.35 / easeInOut 0.2 : nil, value: isActive)` | FIXED | was always animating the pill and never the headline/shield; now only off↔on once loaded, headline + shield + pill + paddings |
| Features/Shield/ProtectedShieldView.swift:44 | features/shield/ProtectedShieldView.kt:272 | hero `.animation(smooth 0.35 / easeInOut 0.2, value: heroPhase)` | FIXED | phase change now cross-fades the headline and eases the shield too; other updates (guardian loaded) no longer cross-fade |
| Features/Shield/ProtectedShieldView.swift:67 | features/shield/ShieldSupport.kt:239 | top scrim easeOut 0.2 | MATCH | |
| Features/Shield/ProtectedShieldView.swift:107 | features/shield/ShieldSupport.kt:320 | Turn-on `.sheet` | APPROXIMATED | ModalBottomSheet's Material spring |
| Features/Shield/ProtectedShieldView.swift:169 | features/shield/ProtectedShieldView.kt:290 | accessory switch (checking/failed/status pill) cross-fade | FIXED | spec now follows the hero's keyed animation (snap otherwise) |
| Features/Shield/ProtectedShieldView.swift:205 | features/shield/ProtectedShieldView.kt:319 | ConnectedPill `.transition(.opacity)` | MATCH | inside the accessory cross-fade |
| Features/Shield/ProtectedShieldView.swift:216 | features/shield/ProtectedShieldView.kt:151 | loading skeleton shimmer | MATCH | |
| Features/Shield/ProtectedShieldView.swift:232 | features/shield/ProtectedShieldView.kt:170 | load-error card `.stateEntrance()` | MATCH | |
| Features/Shield/ProtectedShieldView.swift:238 | features/shield/ProtectedShieldView.kt:179 | loaded page `LoaderReplacementFade` (easeOut 0.2) | MATCH | components `loaderReplacementFade` |
| Features/Shield/ProtectedShieldView.swift:263 | features/shield/ProtectedShieldView.kt:386 | refresh notice `.transition(StateMotion.transition(edge: .top))` | MATCH | the `.animation` is scoped to the notice's VStack, so rows below jump on iOS too |
| Features/Shield/ProtectedShieldView.swift:268 | features/shield/ProtectedShieldView.kt:386 | `.animation(StateMotion.enter, value: refreshFailed)` (notice only) | MATCH | |
| Features/Shield/ProtectedShieldView.swift:277 | features/shield/ProtectedShieldView.kt:408 | "Mode Terawasi" close: withAnimation(.easeOut 0.2) + `.transition(.opacity)` | FIXED | slot now shrinks with the fade and the top/list/scams gaps ease (easeOut 0.2) instead of jumping after it |
| Features/Shield/ProtectedShieldView.swift:312 | features/shield/ProtectedShieldView.kt:447 | HeroStatusPill dot: opacity 0.35 + scale 0.8, easeInOut 0.8 repeatForever autoreverse; none with RM | MATCH | |
| Features/Shield/ProtectedShieldView.swift:394 | features/shield/ProtectedShieldView.kt:538 | card `.animation(smooth 0.3 / easeInOut 0.2, value: decision)`: blush, glow colour, badge blush, risk panel | FIXED | only the footer cross-faded; card blush ↔ glow, warm ↔ red glow, header badge blush and the risk panel (OverflowCrossfade) now ease with the same spec, only on a decision change |
| Features/Shield/ProtectedShieldView.swift:442 | features/shield/ProtectedShieldView.kt:584 | footer line ("will check" / "marked it …") cross-fade | MATCH | Crossfade keyed on decision, same spec |
| Features/Shield/ProtectedShieldView.swift:469 | features/shield/ProtectedShieldView.kt:584 | ! ↔ ✓ badge `.contentTransition(.symbolEffect(.replace))` / .opacity RM | APPROXIMATED | no symbol-replace in Compose: the badge cross-fades with the footer |
| Features/Shield/ProtectedShieldView.swift:392 | features/shield/ProtectedShieldView.kt:563 | site card tap (`.buttonStyle(.plain)`) | APPROXIMATED | no pressed dim on Android |
| Features/Shield/TurnOffExtensionSheet.swift:83 | features/shield/TurnOffExtensionSheet.kt:181 | steps: opacity + 8 pt, StateMotion.enter delayed 0.08 × (i+1) | MATCH | |
| Features/Shield/TurnOffExtensionSheet.swift:115 | features/shield/TurnOffExtensionSheet.kt:220 | warning `.symbolEffect(.wiggle)` once on appear; none with RM | APPROXIMATED | rotation −12/10/−8/6/0°, 0.08 s steps (easeInOut) stands in for the system wiggle |
| Features/Shield/TurnOffExtensionSheet.swift:117 | features/shield/TurnOffExtensionSheet.kt:220 | iOS 17 fallback `.symbolEffect(.bounce)` | APPROXIMATED | Android always uses the wiggle stand-in (iOS 18 path) |
| Features/Shield/TurnOffExtensionSheet.swift:97 | features/shield/TurnOffExtensionSheet.kt:88 | sheet with `.presentationDetents([.height])` | APPROXIMATED | presented by Profile's ModalBottomSheet; Material spring |
| Features/Shield/TurnOnExtensionSheet.swift:9 | features/shield/TurnOnExtensionSheet.kt:37 | sheet closes itself once Shoo checks in (dismiss) | APPROXIMATED | `sheetState.hide()` Material animation |
| Features/Shield/LatestScamsCard.swift:45 | features/shield/LatestScamsCard.kt:198 | `.scrollTargetBehavior(.viewAligned)` snap | APPROXIMATED | custom fling settles with Compose's default spring, not UIKit's deceleration |
| Features/Shield/GuardianShieldView.swift:31 | features/shield/GuardianShieldView.kt:70 | "Notifications are off" `.alert` | APPROXIMATED | Material AlertDialog's own enter/exit |
| Features/Shield/GuardianShieldView.swift:13 | features/shield/GuardianShieldView.kt:33 | Family mode on/off swaps the Home (no animation) | MATCH | instant on both |

## Onboarding

| Swift (ios/ShooApp/…) | Kotlin (android/app/src/main/java/com/shoo/app/…) | Animation | Status | Note |
|---|---|---|---|---|
| Features/Onboarding/LaunchSplash.swift:43 | features/onboarding/LaunchSplash.kt:62 | splash hold 0.8 s (0.4 s RM) from scene active, then fade | MATCH | hold timed from resume like scenePhase .active |
| Features/Onboarding/LaunchSplash.swift:46 | features/onboarding/LaunchSplash.kt:68 | splash opacity 1→0, .easeOut 0.3 (0.2 RM), then .done | MATCH | taps pass through from .leaving like allowsHitTesting |
| Features/Onboarding/LaunchSplash.swift:69 | features/onboarding/LaunchSplash.kt:113 | light band sweep TimelineView, 1.2 s, cubic ease-out progress, ellipses drift 40 pt | MATCH | frame loop; still frame with RM |
| Features/Onboarding/LaunchSplash.swift:112 | features/onboarding/LaunchSplash.kt:163 | logo scale 0.7→1 + opacity 0→1 | MATCH | |
| Features/Onboarding/LaunchSplash.swift:122 | features/onboarding/LaunchSplash.kt:111 | logo .spring(response 0.6, dampingFraction 0.65); RM: no animation | FIXED | now shooSpringResponse(0.6, 0.65) (same physics as the inline spring it replaces) |
| Features/Onboarding/ShooBirdLogo.swift:14 | features/onboarding/ShooBirdLogo.kt:47 | TimelineView(.animation) clock, paused with RM | MATCH | withFrameNanos loop; time 0 with RM |
| Features/Onboarding/ShooBirdLogo.swift:36 | features/onboarding/ShooBirdLogo.kt:63 | breath: 2 % swell, 3 s cosine | MATCH | |
| Features/Onboarding/ShooBirdLogo.swift:23 | features/onboarding/ShooBirdLogo.kt:75 | blink: eye slits, two blinks per 4.2 s, 0.08 s half width | MATCH | |
| Features/Onboarding/ShooBirdLogo.swift:31 | features/onboarding/ShooBirdLogo.kt:81 | sparkle twinkle: scale 0.75+0.4t, rotation 45°·t, opacity 0.8+0.2t, 5 s loop | MATCH | |
| Features/Onboarding/OnboardingFlow.swift:60 | features/onboarding/OnboardingFlow.kt:78 | step transition: asymmetric move trailing/leading (reversed when movedBack) + opacity; RM opacity | MATCH | AnimatedContent slideIn/Out by full width + fade |
| Features/Onboarding/OnboardingFlow.swift:68 | features/onboarding/OnboardingFlow.kt:78 | step animation .smooth (0.5, 0); RM .easeInOut 0.2 | MATCH | shooSmooth() / shooEaseInOut(0.2) |
| Features/Onboarding/SplashView.swift:44 | features/onboarding/SplashView.kt:95 | paged TabView swipe | APPROXIMATED | HorizontalPager fling/snap physics instead of UIScrollView paging deceleration |
| Features/Onboarding/SplashView.swift:77 | features/onboarding/SplashView.kt:147 | Next: withAnimation { page += 1 } (default = spring 0.55, 0) | FIXED | was animateScrollToPage's default spring (StiffnessMediumLow); now shooDefault(). iOS page TabView may hand this to UIKit's own scroll animation |
| Features/Onboarding/SplashView.swift:88 | features/onboarding/SplashView.kt:138 | Next button OnboardingPressButtonStyle | MATCH | onboardingPress: 0.94 scale (RM 0.8 dim), easeOut 0.15 |
| Features/Onboarding/NameView.swift:44 | features/onboarding/NameView.kt:112 | big avatar swap: .scale(0.9)+.opacity; RM .opacity; under .snappy 0.25 | MATCH | AnimatedContent scaleIn/Out 0.9 + fade, shooSnappy(0.25) |
| Features/Onboarding/NameView.swift:82 | features/onboarding/NameView.kt:214 | avatar pick withAnimation(.snappy 0.25): selected ring cross-fade (card 2 pt ↔ green 4 pt) + shadow opacity | FIXED | was an instant swap; now both rings and the shadow fade on shooSnappy(0.25). Also animates when isMarked flips from typing (iOS: no animation there) |
| Features/Onboarding/NameView.swift:185 | features/onboarding/NameView.kt:220 | avatar button OnboardingPressButtonStyle | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:114 | features/onboarding/OnboardingStyle.kt:223 | capsule button press: scale 0.98 + opacity 0.85, .easeOut 0.15 | FIXED | opacity snapped; now scale and dim share one easeOut 0.15 press value; enabled change stays instant like iOS |
| Features/Onboarding/OnboardingStyle.swift:127 | features/onboarding/OnboardingStyle.kt:271 | OnboardingPressButtonStyle: scale 0.94 (RM: opacity 0.8), .easeOut 0.15 | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:516 | features/onboarding/OnboardingStyle.kt:316 | link button pressed opacity 0.6, no animation | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:300 | features/onboarding/OnboardingStyle.kt:491 | after 0.35 s, withAnimation(.smooth) scrollTo(target, anchor: .bottom) | FIXED | bringIntoView used Compose's default scroll spring; LocalBringIntoViewSpec now scrolls on shooSmooth(). Compose scrolls the minimum (none if already visible) where iOS always aligns the bottom |
| Features/Onboarding/OnboardingStyle.swift:531 | features/onboarding/OnboardingStyle.kt:650 | SuccessTextEntrance: opacity + 8 pt rise, .smooth(0.4).delay(0.15); RM fade only | MATCH | no caller sets revealsText on either platform |
| Features/Onboarding/OnboardingStyle.swift:556 | features/onboarding/OnboardingStyle.kt:674 | CelebrationTextEntrance: 16 pt rise (+0.94 scale if bounces), spring(0.45, 0.25) / .smooth(0.45); RM easeInOut 0.2; delayed | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:744 | features/onboarding/OnboardingStyle.kt:910 | success title entrance delay 0.3 s, bounces | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:747 | features/onboarding/OnboardingStyle.kt:917 | success message entrance delay 0.42 s, no bounce | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:629 | features/onboarding/OnboardingStyle.kt:723 | hero pop: scale 0.6→1 + opacity, spring(0.5, 0.35).delay(0.1) | MATCH | coroutine delay then spring |
| Features/Onboarding/OnboardingStyle.swift:626 | features/onboarding/OnboardingStyle.kt:718 | hero RM: opacity only, easeInOut 0.2, no rings/confetti | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:636 | features/onboarding/OnboardingStyle.kt:737 | first ring 0.8→2.2 scale, 0.5→0 opacity, .easeOut 0.8 at 0.35 s + 16 ms | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:638 | features/onboarding/OnboardingStyle.kt:739 | second ring, same, 0.12 s later | MATCH | |
| Features/Onboarding/OnboardingStyle.swift:684 | features/onboarding/OnboardingStyle.kt:753 | confetti burst TimelineView: 28 bits, gravity 1400, 0.85 s, fade over the last 0.3 s | MATCH | same seeded generator |
| Features/Onboarding/OnboardingIllustrations.swift:186 | features/onboarding/OnboardingIllustrations.kt:249 | orbit TimelineView (18 s per turn), paused with RM | MATCH | Android redraws every frame; iOS caps the timeline at 30 fps (same positions, smoother) |
| Features/Onboarding/OnboardingIllustrations.swift:258 | features/onboarding/OnboardingIllustrations.kt:345 | rider depth scale 1 + 0.1·(sin a − sin a0) | MATCH | |
| Features/Onboarding/OnboardingIllustrations.swift:268 | features/onboarding/OnboardingIllustrations.kt:359 | chip opacity near the orbit ends | MATCH | |
| Features/Onboarding/SafariDefaultView.swift:82 | features/onboarding/SafariDefaultView.kt:87 | "Make Safari default" ↔ "Keep going" .opacity transition | MATCH | Crossfade |
| Features/Onboarding/SafariDefaultView.swift:101 | features/onboarding/SafariDefaultView.kt:87 | .animation(.smooth(duration: 0.3), value: cameBack) | MATCH | shooSmooth(0.3); no RM switch on iOS either |
| Features/Onboarding/SafariDefaultView.swift:105 | features/onboarding/TutorialVideoPlayer.kt:61 | fullScreenCover TutorialVideoPlayer present/dismiss (slide up / down) | FIXED | was the Dialog window's own animation only; content now slides up from the bottom on present and down on Close/Back (shooSmooth(0.5)) |
| Features/Onboarding/TurnOnExtensionView.swift:158 | features/onboarding/TutorialVideoPlayer.kt:64 | fullScreenCover TutorialVideoPlayer (ON-04) | APPROXIMATED | slide added (see above), but the Compose Dialog window still adds its platform fade and dim, UIKit's cover curve is approximated by smooth(0.5), and the VideoView SurfaceView may not follow the layer translation |
| Features/Onboarding/TurnOnExtensionView.swift:66 | features/onboarding/TurnOnExtensionView.kt:252 | status note: .opacity + .move(edge: .top); RM .opacity | FIXED | was default fadeIn + expandVertically (Compose default springs); now fade + slide from the top on shooSmooth(0.3) (RM easeInOut 0.2), plus expand standing in for SwiftUI moving the siblings |
| Features/Onboarding/TurnOnExtensionView.swift:66 | features/onboarding/TurnOnExtensionView.kt:264 | Android add-on code card / code problem (same slot) | FIXED | same transition as the status note (Android-only content) |
| Features/Onboarding/TurnOnExtensionView.swift:115 | features/onboarding/TurnOnExtensionView.kt:318 | second action link .transition(.opacity) | FIXED | was fadeIn()/fadeOut() default spring; now shooSmooth(0.3) / easeInOut 0.2 RM with expand/shrink for the footer reflow |
| Features/Onboarding/TurnOnExtensionView.swift:122 | features/onboarding/TurnOnExtensionView.kt:339 | "Continue without checking" .transition(.opacity) | FIXED | same as above |
| Features/Onboarding/TurnOnExtensionView.swift:132 | features/onboarding/TurnOnExtensionView.kt:365 | .animation(RM ? easeInOut 0.2 : .smooth 0.3, value: cameBack) | APPROXIMATED | iOS only animates changes landing in the same update as cameBack; the status arrives after an await, so iOS often snaps. Android animates every visibility change with that curve |
| Features/Onboarding/TurnOnExtensionView.swift:202 | features/onboarding/TurnOnExtensionView.kt:517 | checkbox toggle withAnimation(.snappy 0.2): fill + stroke colour | MATCH | animateColorAsState shooSnappy(0.2) |
| Features/Onboarding/TurnOnExtensionView.swift:215 | features/onboarding/TurnOnExtensionView.kt:549 | checkmark .scale(0.6)+.opacity; RM .opacity (under .snappy 0.2) | FIXED | fade parts used the Compose default fade spec; now shooSnappy(0.2) for every part, RM included |
| Features/Onboarding/TurnOnExtensionView.swift:161 | features/onboarding/TurnOnExtensionView.kt:599 | DataSentSheet .sheet (detents 618 / large) | APPROXIMATED | ModalBottomSheet: Material sheet spring and drag physics, no spec hook |
| Features/Onboarding/TurnOnExtensionView.swift:392 | features/onboarding/TurnOnExtensionView.kt:797 | ExtensionOnView celebrated hero (HalftoneShield teal ×1.67 + successCelebrationHero 177) | MATCH | |

## Pairing

| Swift (ios/ShooApp/…) | Kotlin (android/app/src/main/java/com/shoo/app/…) | Animation | Status | Note |
|---|---|---|---|---|
| Features/Pairing/ConnectView.swift:34 | features/pairing/ConnectView.kt:166 | PR-02 "Connected" insertion: opacity + scale 0.97 (RM opacity) | MATCH | fadeIn + scaleIn(0.97) |
| Features/Pairing/ConnectView.swift:37 | features/pairing/ConnectView.kt:166 | form removal: .opacity | MATCH | fadeOut |
| Features/Pairing/ConnectView.swift:41 | features/pairing/ConnectView.kt:166 | joined swap: .smooth(0.4) / easeInOut 0.2 RM | MATCH | shooSmooth(0.4) / shooEaseInOut(0.2) |
| Features/Pairing/ConnectView.swift:66 | features/pairing/ConnectView.kt:242 | Code/Scan content switch: default .opacity under withAnimation(.snappy(0.3)), page height follows | FIXED | cross-fade already matched; the height now follows with snappy 0.3 (SizeTransform, was default spring) |
| Features/Pairing/ConnectView.swift:73 | features/pairing/ConnectView.kt:267 | scanned code → tab = .code with no withAnimation | FIXED | was animated; now content, footer and thumb switch at once like iOS |
| Features/Pairing/ConnectView.swift:85 | features/pairing/ConnectView.kt:286 | "Just enter the code": withAnimation(.snappy(0.3)) tab = .code | MATCH | snappy 0.3 cross-fade |
| Features/Pairing/ConnectView.swift:91 | features/pairing/ConnectView.kt:274 | "Not a Shoo QR" block: StateMotion.transition(edge: .top) | MATCH | StateMotion.enter/exitTransition(fromBottom = false) |
| Features/Pairing/ConnectView.swift:93 | features/pairing/ConnectView.kt:292 | scan-tab problem line swapping with the refusal block (.opacity under StateMotion.enter) | APPROXIMATED | Android swaps it at once; only seen when a join problem and a refused scan coincide |
| Features/Pairing/ConnectView.swift:109 | features/pairing/ConnectView.kt:317 | ShakeOnProblem applied, off with Reduce Motion | MATCH | isEnabled = !reduceMotion |
| Features/Pairing/ConnectView.swift:119 | features/pairing/ConnectView.kt:322 | "Retype code": StateMotion.transition(edge: .top) | FIXED | insertion matched; removal when another problem replaces "invalid" now uses the StateMotion removal (was always instant) |
| Features/Pairing/ConnectView.swift:124 | features/pairing/ConnectView.kt:308 | .animation(problem == nil ? nil : StateMotion.enter) on the code column | FIXED | column height now grows with spring 0.32/0.18 (easeOut 0.2 RM) and snaps when cleared; was a jump |
| Features/Pairing/ConnectView.swift:136 | features/pairing/ConnectView.kt:347 | copy note opacity 0 while typing (no animation) | MATCH | snaps |
| Features/Pairing/ConnectView.swift:144 | features/pairing/ConnectView.kt:371 | footer "Back" .transition(.opacity) | MATCH | AnimatedContent fade |
| Features/Pairing/ConnectView.swift:148 | features/pairing/ConnectView.kt:371 | footer WaitButton .transition(.opacity) | MATCH | AnimatedContent fade |
| Features/Pairing/ConnectView.swift:157 | features/pairing/ConnectView.kt:401 | "Connect" label hidden + spinner while joining (no animation) | MATCH | snaps |
| Features/Pairing/ConnectView.swift:140 | features/pairing/ConnectView.kt:353 | code-only footer buttons appear/leave on tab switch (.opacity under .snappy(0.3), "Not now" moves) | FIXED | added expand/shrinkVertically(snappy 0.3, no clip) so "Not now" moves instead of jumping; instant for a scanned switch |
| Features/Pairing/ConnectView.swift:176 | features/pairing/ConnectView.kt:371 | .animation(.easeInOut(0.2), value: footerKind) | FIXED | cross-fade matched; footer size change now eases 0.2 too (SizeTransform, was default spring) |
| Features/Pairing/ConnectView.swift:177 | features/pairing/ConnectView.kt:260 | .animation(StateMotion.enter, value: scanRefused): page below moves with the block | FIXED | animateContentSize with StateMotion.enter on the scan column; was a jump |
| Features/Pairing/ConnectView.swift:219 | features/pairing/ConnectView.kt:449 | problem line .transition(.opacity): in with StateMotion.enter, out at once | MATCH | fadeIn spring 0.32/0.18 (easeOut 0.2 RM), ExitTransition.None |
| Features/Pairing/ConnectView.swift:263 | features/pairing/ConnectView.kt:509 | ConnectInlineLinkStyle press: opacity 0.6, scale 0.97 (leading), easeOut 0.12 | MATCH | scale off with RM |
| Features/Pairing/ConnectView.swift:282 | features/pairing/ConnectView.kt:550 | WaitButton TimelineView(.periodic by: 1) | MATCH | 1 s loop |
| Features/Pairing/ConnectView.swift:287 | features/pairing/ConnectView.kt:569 | countdown .numericText(countsDown: true) / RM .opacity, both under .snappy(0.3) | FIXED | NumericText (ConnectView.kt:605): only changed digits roll, down from above, snappy 0.3; RM fade now snappy 0.3 (was easeOut 0.2); was the whole label sliding. Residual: iOS also blurs rolling glyphs |
| Features/Pairing/ConnectView.swift:314 | features/pairing/ConnectView.kt:581 | keyframeAnimator shake: +6 (0.05), −6 (0.1), +6 (0.1), 0 (0.05), linear | MATCH | Animatable tweens, LinearEasing |
| Features/Pairing/ConnectView.swift:349 | features/pairing/ConnectView.kt:236 | segment tap: withAnimation(.snappy(0.3)) | MATCH | |
| Features/Pairing/ConnectView.swift:362 | features/pairing/ConnectView.kt:665 | segmented thumb matchedGeometryEffect under .snappy(0.3) | FIXED | offset animates with snappy 0.3; now snaps on a scanned switch (was always animated). Label weight swaps at once |
| Features/Pairing/ConnectView.swift:464 | features/pairing/ConnectView.kt:846 | code box ring: .animation(.easeOut(0.2), value: isWrong) | FIXED | only the red ring fades 0.2 s; focus ring moving between boxes now snaps (was eased on every change) |
| Features/Pairing/ConnectView.swift:491 | features/pairing/ConnectView.kt:870 | caret blink, 530 ms toggle, no fade, off with RM | MATCH | |
| Features/Pairing/InviteSheet.swift:58 | features/pairing/InviteSheet.kt:195 | footer swap .animation(.easeInOut(0.25), value: stateKind) | FIXED | cross-fade matched; footer height change now eases 0.25 too (SizeTransform) |
| Features/Pairing/InviteSheet.swift:99 | features/pairing/InviteSheet.kt:315 | body (loading / ready / unavailable / full) swap, no animation | MATCH | snaps |
| Features/Pairing/InviteSheet.swift:110 | features/pairing/InviteSheet.kt:320 | loading QR + code skeleton .shimmering() | MATCH | shared Shimmer (linear 1.3 s loop) |
| Features/Pairing/InviteSheet.swift:80 | features/pairing/InviteSheet.kt:389 | copied note in: withAnimation(StateMotion.enter) | FIXED | outgoing "Refresh code" now fades with the same spring (was easeOut 0.25); size follows the spring |
| Features/Pairing/InviteSheet.swift:83 | features/pairing/InviteSheet.kt:389 | copied note out after 2 s: withAnimation(.easeOut(0.25)) | MATCH | size change now also easeOut 0.25 |
| Features/Pairing/InviteSheet.swift:137 | features/pairing/InviteSheet.kt:379 | invite code .numericText() under .snappy(0.3) / RM .opacity under .easeInOut(0.2) | FIXED | per-digit roll up from below via NumericText (was the whole code sliding). Residual: no glyph blur |
| Features/Pairing/InviteSheet.swift:157 | features/pairing/InviteSheet.kt:389 | copied note insertion: opacity + scale 0.92 (RM opacity) | MATCH | |
| Features/Pairing/InviteSheet.swift:161 | features/pairing/InviteSheet.kt:389 | "Refresh code" + countdown .transition(.opacity) | FIXED | see :80 (its fade-out spec) |
| Features/Pairing/InviteSheet.swift:166 | features/pairing/InviteSheet.kt:425 | "Code can't be made yet" StateMessage entrance | MATCH | shared StateMessage |
| Features/Pairing/InviteSheet.swift:175 | features/pairing/InviteSheet.kt:433 | "Family is full" StateMessage entrance | MATCH | shared StateMessage |
| Features/Pairing/InviteSheet.swift:203 | features/pairing/InviteSheet.kt:457 | "Refresh code" link press: opacity 0.6, no animation | MATCH | snaps |
| Features/Pairing/InviteSheet.swift:206 | features/pairing/InviteSheet.kt:474 | "Valid for" countdown ticks with no transition | MATCH | |
| Features/Pairing/InviteSheet.swift:264 | features/pairing/InviteSheet.kt:505 | Copy → Copied title swap (no animation) | MATCH | snaps |
| Features/Pairing/InviteSheet.swift:362 | features/pairing/InviteSheet.kt:562 | tile symbol .contentTransition(.symbolEffect(.replace)) under .snappy(0.3) / RM .opacity under .easeInOut(0.2) | APPROXIMATED | no symbol morph in Compose: old icon scales to 0.6 and fades, new scales from 0.6 and fades in, snappy 0.3; RM matches |
| Features/Pairing/InviteSheet.swift:419 | features/pairing/InviteSheet.kt:632 | share row skeleton .shimmering() | MATCH | shared Shimmer |
| Features/Pairing/InviteSheet.swift:86 | features/pairing/InviteSheet.kt:700 | "More": .sheet(item:) with UIActivityViewController | APPROXIMATED | Android system chooser with its own system animation |
| Features/Pairing/FamilyCodeView.swift:33 | features/pairing/FamilyCodeView.kt:235 | remove confirmation .confirmationDialog | APPROXIMATED | iOS action sheet slides up from the bottom; Material AlertDialog fades/scales in the centre (system) |
| Features/Pairing/FamilyCodeView.swift:44 | features/pairing/FamilyCodeView.kt:253 | "Couldn't remove" .alert | APPROXIMATED | UIKit alert pop vs Material dialog animation (system) |
| Features/Pairing/FamilyCodeView.swift:58 | features/pairing/FamilyCodeView.kt:264 | ShieldPulseLoader → code swap (no animation) | MATCH | snaps; loader motion is the shared component |
| Features/Pairing/FamilyCodeView.swift:28 | features/pairing/FamilyCodeView.kt:131 | system buttons (Done, Copy invite link, Try again, Remove, reload row) press highlight | APPROXIMATED | was no feedback; now dims to 0.3 at once and eases back 0.2 s (systemButton, FamilyCodeView.kt:395). UIKit's exact highlight values aren't public; the list row's grey highlight is a dim here |
| Features/Pairing/FamilyCodeView.swift:118 | features/pairing/FamilyCodeView.kt:187 | member rows added/removed (no withAnimation) | MATCH | snaps |
| Features/Pairing/FamilyCodeView.swift:94 | features/pairing/FamilyCodeView.kt:338 | "Copy invite link" → "Copied" label/icon swap (no animation) | MATCH | snaps |
| Features/Pairing/InviteNoticeBanner.swift:82 | features/pairing/InviteNoticeBanner.kt:125 | notice buttons OnboardingPressButtonStyle: scale 0.94 (RM dim 0.8), easeOut 0.15 | MATCH | onboardingPress; the banner's own insertion is in MainTabView |

## Detail and Activity

| Swift (ios/ShooApp/…) | Kotlin (android/app/src/main/java/com/shoo/app/…) | Animation | Status | Note |
|---|---|---|---|---|
| Features/Detail/DetailView.swift:45 | features/detail/DetailView.kt:433 | loader / gone / failed / loaded swap, `.animation(.easeOut(duration: 0.2), value: model.state)` | MATCH | `Crossfade` keyed on the state, tween 200 ms easeOut (0, 0, 0.58, 1); same with Reduce Motion, like iOS |
| Features/Detail/DetailView.swift:102 | features/detail/DetailView.kt:439 | loading page `.transition(.opacity)` | MATCH | fades out inside the Crossfade |
| Features/Detail/DetailView.swift:128 | features/detail/DetailView.kt:457 | "This item is gone" `.transition(.opacity)` | MATCH | Crossfade; StateHeroPage's own entrance is in Components |
| Features/Detail/DetailView.swift:150 | features/detail/DetailView.kt:489 | "Couldn't load this item" `.transition(.opacity)` | MATCH | Crossfade |
| Features/Detail/DetailView.swift:154 | features/detail/DetailView.kt:529 | loaded page `LoaderReplacementFade` (easeOut 0.2 on appear) | MATCH | `Modifier.loaderReplacementFade()` on top of the Crossfade fade, as iOS stacks the default opacity transition with the modifier |
| Features/Detail/DetailView.swift:189 | features/detail/DetailView.kt:579 | status-bar material once the hero scrolled away | MATCH | not animated on either platform (plain state flip) |
| Features/Detail/DetailView.swift:205 | features/detail/SafeReasonSheet.kt:349 | `.sheet` present / dismiss (SafeReasonSheet) | APPROXIMATED | `ModalBottomSheet`: Material's sheet spring and scrim, no spec hook; UIKit sheet curve not reproducible |
| Features/Detail/DetailFooter.swift:139 | features/detail/DetailFooter.kt:211 | buttons ⇄ verified card hand-over, `.animation(reduceMotion ? .easeInOut(0.2) : .snappy(0.25), value: verdict?.value)` | FIXED | was an instant content swap + `animateContentSize` on every change; now `AnimatedContent` fading old/new face with the size on the same spec, keyed on the verdict only ("Ubah" swaps at once, like iOS) |
| Features/Detail/DetailFooter.swift:94 | features/detail/DetailFooter.kt:258 | "Shoo no longer blocks…" note `.opacity.combined(with: .offset(y: 4))` | FIXED | was default-spring `fadeIn` + slide with no exit offset; now the face fade (snappy 0.25 / easeInOut 0.2) plus a 4 dp rise in and drop out via `animateEnterExit`; opacity only with Reduce Motion |
| Features/Detail/DetailFooter.swift:107 | features/detail/DetailFooter.kt:280 | "Couldn't save" line appearing with the rolled-back verdict | FIXED | was an instant insert under an always-on size animation; now default opacity transition + height on the verdict spec, only when the verdict changed in the same update |
| Features/Detail/DetailFooter.swift:190 | features/detail/DetailFooter.kt:381 | Safe / Danger press 0.97, easeOut 0.15; none with Reduce Motion | MATCH | `animateFloatAsState(shooEaseOut(0.15))`, target 1 under Reduce Motion |
| Features/Detail/DetailHeader.swift:109 | features/detail/DetailHeader.kt:183 | hero shield `.scaleEffect(scale)` | MATCH | static scale; the shield's own breath/wave/sweep is HalftoneShield (Components) |
| Features/Detail/DetailHeader.swift:259 | features/detail/DetailHeader.kt:363 | hero rings breathe, `TimelineView(.animation)`, 4 s cosine, +1.2 %, anchor at ring centre; still with Reduce Motion | MATCH | `withFrameNanos` loop, same formula and transform origin (0.5, 170/360); phase origin differs (frame clock vs reference date), not visible |
| Features/Detail/DetailHeader.swift:268 | features/detail/DetailHeader.kt:372 | `SoftPulse(140 → 420, peak 0.1)` over the hero, hidden with Reduce Motion | MATCH | same parameters and offset; SoftPulse itself is in Components |
| Features/Detail/EvidenceCard.swift:191 | features/detail/EvidenceCard.kt:309 | page-scan line, `TimelineView(.animation)`, \|sin(π·t/2.4 s)\| × 196 − 46; removed with Reduce Motion | MATCH | same formula per frame |
| Features/Detail/EvidenceCard.swift:243 | features/detail/EvidenceCard.kt:389 | scan placeholder → page image, `.transition(.opacity)` + `.animation(.easeOut(0.2), value: image != nil)` | MATCH | `Crossfade` keyed on `image != null`, 200 ms easeOut |
| Features/Detail/EvidenceCard.swift:372 | features/detail/EvidenceCard.kt:560 | paged `TabView(.page)` swipe between marks | APPROXIMATED | `HorizontalPager`: Compose fling/snap physics instead of UIPageViewController's scroll deceleration |
| Features/Detail/EvidenceCard.swift:406 | features/detail/EvidenceCard.kt:592 | page dots width 6 ↔ 16 and fill, easeOut 0.2 on `page` | FIXED | width already animated; the fill colour snapped, now `animateColorAsState` 200 ms easeOut |
| Features/Detail/SafeReasonSheet.swift:100 | features/detail/SafeReasonSheet.kt:224 | scroll "Mark Safe" above the keyboard, `withAnimation(reduceMotion ? nil : .snappy(0.25))` | FIXED | `bringIntoView` used Compose's default scroll spring; now `LocalBringIntoViewSpec` with snappy 0.25, `snap()` with Reduce Motion (also applies to the note field's focus scroll) |
| Features/Detail/SafeReasonSheet.swift:111 | features/detail/SafeReasonSheet.kt:290 | "Couldn't save" banner, `.animation(reduceMotion ? nil : .snappy(0.25), value: failed)` + `.opacity.combined(with: .offset(y: 4))` | FIXED | was default-spring fade + 12 px slide, fade-only exit, and a fade even with Reduce Motion; now snappy 0.25 fade + 4 dp offset + height (the sheet grows on the same spring), instant with Reduce Motion |
| Features/Detail/SafeReasonSheet.swift:105 | features/detail/SafeReasonSheet.kt:349 | `.presentationDetents([.height(height)])` sheet resizing with its content | APPROXIMATED | ModalBottomSheet wraps its content; the height change follows the banner's expand spring rather than UIKit's detent animation |
| Features/Detail/SafeReasonSheet.swift:270 | features/detail/SafeReasonSheet.kt:521 | submit label "Mark Safe" → "Try again" and icon swap under the `failed` animation | APPROXIMATED | the label and icon swap at once; SwiftUI cross-fades the text/symbol in place over snappy 0.25 |
| Features/Detail/SafeReasonSheet.swift:289 | features/detail/SafeReasonSheet.kt:521 | submit button 35 % until a reason is picked | MATCH | not animated on either platform |
| Features/Activity/ActivityView.swift:65 | features/activity/ActivityView.kt:295 | content swap `.animation(.easeOut(duration: 0.2), value: model.state)` (loader `.transition(.opacity)`) | MATCH | loader item `animateItem` fade in/out, tween 200 ms easeOut |
| Features/Activity/ActivityView.swift:185 | features/activity/ActivityView.kt:303 | "Couldn't load activity" `.transition(.opacity)` | MATCH | `animateItem` fade 200 ms easeOut |
| Features/Activity/ActivityView.swift:206 | features/activity/ActivityView.kt:315 | empty state `.transition(.opacity)` | APPROXIMATED | fades 0.2 s on a state change like iOS; also fades when a refresh empties a loaded list, where iOS (animation keyed on `state`) cuts |
| Features/Activity/ActivityView.swift:209 | features/activity/ActivityView.kt:238 | rows `LoaderReplacementFade` (easeOut 0.2 each time the rows appear) | FIXED | faded only on state → LOADED and started a frame late (rows flashed at full alpha); now a fresh 0 → 1 fade every time the rows replace loader, message or empty state |
| Features/Activity/ActivityView.swift:217 | features/activity/ActivityView.kt:333 | refresh-failed banner `StateMotion.transition(edge: .top)` | MATCH | `StateMotion.enterTransition/exitTransition(fromBottom = false)`: fade + full-height move from top + 0.98 scale, spring(0.32, 0.18); fade easeOut 0.2 with Reduce Motion |
| Features/Activity/ActivityView.swift:250 | features/activity/ActivityView.kt:333 | rows shift with the banner, `.animation(StateMotion.enter, value: model.refreshFailed)` | FIXED | rows jumped; the banner item now also expands/shrinks its height on spring(0.32, 0.18) (easeOut 0.2 with Reduce Motion), unclipped like iOS's move |
| Features/Activity/ActivityView.swift:235 | features/activity/ActivityView.kt:362 | row insert / remove, "loading more" and retry rows | MATCH | not animated on either platform (no animation keyed on the items) |
| Features/Activity/ActivityView.swift:263 | features/activity/ActivityView.kt:376 | row `.buttonStyle(.plain)` press | APPROXIMATED | `.plain` dims while pressed with no animation; Android dims to 70 % over 0.12 s easeOut (`pressScale(scale = 1f)`) |
| Features/Activity/ActivityView.swift:107 | features/activity/ActivityView.kt:471 | Turn-on `.sheet` present / dismiss | APPROXIMATED | `ModalBottomSheet`: Material sheet spring, no spec hook |
| Features/Activity/ActivityView.swift:153 | features/activity/ActivityView.kt:439 | person picker open/close `withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15))` | MATCH | `AnimatedVisibility`; None / None with Reduce Motion |
| Features/Activity/ActivityView.swift:172 | features/activity/ActivityView.kt:444 | menu `.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity)` | MATCH | `scaleIn/scaleOut(0.6, TransformOrigin(1, 0))` + fade on shooSpring(0.3, 0.15) |
| Features/Activity/ActivityView.swift:339 | features/activity/ActivityView.kt:616 | filter thumb `withAnimation(.spring(duration: 0.3, bounce: 0.1)) { select }` + `matchedGeometryEffect` (side by side) | FIXED | animated any position/width change (new layout, model-set filter); now springs only after a tap, snaps otherwise; nil with Reduce Motion. iOS reads the system Reduce Motion here, Android `LocalReduceMotion` |
| Features/Activity/ActivityView.swift:359 | features/activity/ActivityView.kt:652 | filter thumb between stacked lines (accessibility sizes) `matchedGeometryEffect` | FIXED | the thumb jumped between lines; now one thumb layer between the tracks and the words slides y + height on spring(0.3, 0.1) |
| Features/Activity/ActivityView.swift:783 | features/activity/ActivityView.kt:1225 | "Try again" in refresh notice, `PressScaleButtonStyle` 0.96 / 70 %, easeOut 0.12 | MATCH | `pressScale(interaction)` |
| Features/Activity/ActivityView.swift:802 | features/activity/ActivityView.kt:1255 | notice icon `.symbolEffect(.wiggle.byLayer, .nonRepeating, value: nudge)` (iOS 18) on appear / after retry | APPROXIMATED | no SF symbol effects on Android: a rotation wiggle −12°, 10°, −8°, 6°, 0° at 0.08 s each; off with Reduce Motion like iOS |
| Features/Activity/ActivityView.swift:804 | features/activity/ActivityView.kt:1208 | notice icon `.symbolEffect(.bounce)` (iOS 17 fallback) | APPROXIMATED | Android always uses the iOS 18 branch (wiggle approximation) |
| Features/Activity/ActivityEmptyState.swift:196 | features/activity/ActivityEmptyState.kt:256 | blue button press 0.97 + 80 %, easeOut 0.15; dim only with Reduce Motion | MATCH | two `animateFloatAsState(shooEaseOut(0.15))` |

## Profile

| Swift (ios/ShooApp/…) | Kotlin (android/app/src/main/java/com/shoo/app/…) | Animation | Status | Note |
|---|---|---|---|---|
| Features/Profile/ProfileView.swift:50 | features/profile/ProfileView.kt:404 | family card height on member ids change, `.snappy(0.25)`, nil RM | MATCH | `animateContentSize(shooSnappy(0.25))`, none with RM; Kotlin also eases loader→failed height (iOS only on id changes) |
| Features/Profile/ProfileView.swift:253 | features/profile/ProfileView.kt:421 | member row + divider insertion `.opacity` under `.snappy(0.25)` | MATCH | rows present at first show don't fade; RM: snap |
| Features/Profile/ProfileView.swift:254 | features/profile/ProfileView.kt:435 | member row removal `.opacity` under `.snappy(0.25)` | FIXED | removed rows were dropped at once (forEach) with a default fadeOut; now `LeavingRows` keeps them until a snappy(0.25) fade-out ends |
| Features/Profile/ProfileView.swift:245 | features/profile/ProfileView.kt:409 | members-failed card `.transition(.opacity)` | MATCH | iOS only animates it on an ids change, which a failed load doesn't make: appears at once in both |
| Features/Profile/ProfileView.swift:75 | features/profile/ProfileView.kt:201 | TurnOn sheet present/dismiss | APPROXIMATED | ModalBottomSheet: Material sheet spring, no spec hook for the UIKit sheet curve |
| Features/Profile/ProfileView.swift:78 | features/profile/ProfileView.kt:208 | TurnOff sheet present/dismiss | APPROXIMATED | ModalBottomSheet: Material sheet spring |
| Features/Profile/ProfileView.swift:81 | features/profile/ProfileView.kt:215 | Invite sheet present/dismiss | APPROXIMATED | ModalBottomSheet: Material sheet spring |
| Features/Profile/ProfileView.swift:391 | features/profile/ProfileView.kt:598 | RemindButton Remind→Sent cross-fade `.easeInOut(0.2)` on `sent` | FIXED | was a Crossfade on (isWorking, sent); now fades only when `sent` changes |
| Features/Profile/ProfileView.swift:382 | features/profile/ProfileView.kt:598 | RemindButton spinner `.transition(.opacity)` | FIXED | no animation on isWorking in iOS: now snaps (was a 0.2 s fade) |
| Features/Profile/ProfileView.swift:385 | features/profile/ProfileView.kt:598 | "Remind"/"Sent" `.contentTransition(.opacity)` | MATCH | 0.2 s easeInOut fade |
| Features/Profile/ProfileStyle.swift:557 | features/profile/ProfileStyle.kt:708 | ProfilePillButtonStyle press 0.97 + 0.6 dim, `.easeOut(0.15)`, RM dim only | MATCH | |
| Features/Profile/ProfileStyle.swift:689 | features/profile/ProfileStyle.kt:916 | confirm sheet icon ↔ spinner `.easeInOut(0.2)` | MATCH | Crossfade |
| Features/Profile/ProfileStyle.swift:715 | features/profile/ProfileStyle.kt:821 | ProfileConfirmSheet presentation (height detent) | APPROXIMATED | shown in ProfileSheet (ModalBottomSheet), Material sheet spring |
| Features/Profile/MemberDetailView.swift:61 | features/profile/MemberDetailView.kt:143 | Back button `.transition(.opacity)` (no animation in transaction) | FIXED | was AnimatedVisibility with default fade; iOS state change is unanimated, now appears at once |
| Features/Profile/MemberDetailView.swift:70 | features/profile/MemberDetailView.kt:158 | disconnect confirm sheet | APPROXIMATED | ModalBottomSheet: Material sheet spring |
| Features/Profile/MemberDetailView.swift:256 | features/profile/MemberDetailView.kt:340 | off banner fill/line/tile colours `.easeInOut(0.25)` on `sent` | MATCH | animateColorAsState |
| Features/Profile/MemberDetailView.swift:208 | features/profile/MemberDetailView.kt:375 | symbol `.contentTransition(.symbolEffect(.replace))`, RM `.opacity` | APPROXIMATED | was Crossfade + extra bounce; now old shrinks/fades out, new grows from 0.5 + fades in, easeInOut 0.25; RM plain fade. iOS replace is a system symbol effect |
| Features/Profile/MemberDetailView.swift:256 | features/profile/MemberDetailView.kt:401 | banner title/message text swap under `.easeInOut(0.25)` | FIXED | texts swapped at once; now Crossfade easeInOut 0.25 |
| Features/Profile/MemberDetailView.swift:246 | features/profile/MemberDetailView.kt:408 | Remind button removal `.transition(.opacity)` 0.25 | APPROXIMATED | fade matches; iOS text column widens with the animation, Compose button keeps its slot during the fade then the column jumps |
| Features/Profile/MemberDetailView.swift:233 | features/profile/MemberDetailView.kt:438 | Remind label ↔ spinner on `isReminding` (no animation) | FIXED | was an easeOut 0.15 fade; iOS swaps at once |
| Features/Profile/ProfileCards.swift:36 | features/profile/ProfileCards.kt:138 | Connected capsule press 0.97 + 0.7 dim `.easeOut(0.15)`, RM dim only | MATCH | |
| Features/Profile/ProfileCards.swift:331 | features/profile/ProfileCards.kt:534 | load-failed symbol `.symbolEffect(.bounce)` on nudge, RM none | APPROXIMATED | `profileBounce`: scale 1.18 easeOut 0.12 then spring(0.3, 0.4) back; iOS system bounce |
| Features/Profile/ProfileCards.swift:371 | features/profile/ProfileCards.kt:553 | "Try Again" label opacity `.easeOut(0.15)` on isRetrying | MATCH | |
| Features/Profile/ProfileCards.swift:371 | features/profile/ProfileCards.kt:584 | retry spinner insertion under `.easeOut(0.15)` | FIXED | spinner popped in; now fades in/out easeOut 0.15 |
| Features/Profile/ProfileCards.swift:380 | features/profile/ProfileCards.kt:520 | ProfileLoadFailed `.stateEntrance()` | MATCH | shared modifier |
| Features/Profile/ProfilePages.swift:67 | features/profile/ProfilePages.kt:205 | ProfileRadio ring ↔ fill `.easeInOut(0.2)` | MATCH | Crossfade |
| Features/Profile/ProfilePages.swift:114 | features/profile/ProfilePages.kt:245 | RadioRow ProfileSelectionMotion (snappy 0.2 / RM easeInOut 0.2) + selection haptic | MATCH | only the radio changes look, it keeps its own easeInOut 0.2 |
| Features/Profile/ProfilePages.swift:358 | features/profile/ProfilePages.kt:534 | ModeCard fill/stroke/divider/check colours, snappy 0.2 / RM easeInOut 0.2 | MATCH | `selectionSpec` |
| Features/Profile/ProfilePages.swift:358 | features/profile/ProfilePages.kt:538 | ModeCard stroke width 1 ↔ 1.5 under the selection animation | FIXED | width jumped; now animateDpAsState with selectionSpec |
| Features/Profile/ProfilePages.swift:259 | features/profile/ProfilePages.kt:377 | locked join row opacity 0.45, StateMotion.enter | MATCH | |
| Features/Profile/ProfilePages.swift:265 | features/profile/ProfilePages.kt:447 | locked PageNote `.transition(.opacity)` (sibling of the animated card) | FIXED | had a default-spring fade; iOS insertion is unanimated, now appears at once |
| Features/Profile/ProfilePages.swift:296 | features/profile/ProfilePages.kt:497 | Join another family sheet | APPROXIMATED | ModalBottomSheet: Material sheet spring |
| Features/Profile/ProfilePages.swift:514 | features/profile/ProfilePages.kt:781 | avatar picker sheet | APPROXIMATED | ModalBottomSheet: Material sheet spring |
| Features/Profile/ProfilePages.swift:520 | features/profile/ProfilePages.kt:789 | edit name sheet | APPROXIMATED | ModalBottomSheet: Material sheet spring |
| Features/Profile/ProfilePages.swift:921 | features/profile/ProfilePages.kt:1266 | LinkDots TimelineView pulse (1.4 s pass + 0.6 s rest, absolute clock), paused RM/muted | MATCH | same phase formula; Compose ticks every frame (iOS caps at 30 fps) |
| Features/Profile/ProfilePages.swift:931 | features/profile/ProfilePages.kt:1266 | LinkDots scale 1 + 0.3·lift and colour lift | MATCH | |
| Features/Profile/ProfilePages.swift:1085 | features/profile/ProfilePages.kt:1491 | quiet hours sheet (`.medium` detent) | APPROXIMATED | ModalBottomSheet: Material sheet spring |
| Features/Profile/ProfilePages.swift:1158 | features/profile/ProfilePages.kt:1672 | compact DatePicker popover | APPROXIMATED | iOS opens the system wheel popover; Android unfolds a TimeInput in place (fade + expand), RM now a 0.2 s fade |
| Features/Profile/ProfilePages.swift:1310 | features/profile/ProfilePages.kt:1770 | ThemeOption ring opacity `.easeInOut(0.2)` (also with RM) | MATCH | |
| Features/Profile/ProfilePages.swift:1321 | features/profile/ProfilePages.kt:1768 | ThemeOption 3 ↔ 5 pt inset, snappy 0.2, RM snap (movesLayout) | MATCH | |
| Features/Profile/ProfilePages.swift:1435 | features/profile/ProfilePages.kt:1912 | text-size thumb + blue rail glide `.snappy(0.2)`, RM snap | MATCH | |
| Features/Profile/ProfilePages.swift:1435 | features/profile/ProfilePages.kt:1919 | text-size stop dots grey ↔ blue under the same animation | FIXED | dots jumped colour; now animated per stop with snappy 0.2 (RM snap) |
| Features/Profile/ProfileSheets.swift:88 | features/profile/ProfileSheets.kt:186 | ProfileSaveButtonStyle press 0.97 + 0.85 dim `.easeOut(0.15)`, RM dim only | MATCH | |
| Features/Profile/ProfileSheets.swift:156 | features/profile/ProfileSheets.kt:364 | avatar Save ↔ spinner `.easeInOut(0.2)` | MATCH | SaveLabel Crossfade |
| Features/Profile/ProfileSheets.swift:222 | features/profile/ProfileSheets.kt:501 | name Save ↔ spinner `.easeInOut(0.2)` | MATCH | SaveLabel Crossfade |
| Features/Profile/ProfileSheets.swift:105 | features/profile/ProfileSheets.kt:303 | ProfileSheetChrome height detent sheet | APPROXIMATED | ModalBottomSheet (`ProfileSheet`): Material sheet spring |
| Features/Profile/ProfileSheets.swift:269 | features/profile/ProfileSheets.kt:433 | name field focus ring (no animation) | MATCH | both snap |
| Features/Profile/ProfileSheets.swift:331 | features/profile/ProfileSheets.kt:528 | delete-account alert dim + card `.opacity`, `.easeOut(0.2)` | MATCH | |
| Features/Profile/ProfileSheets.swift:367 | features/profile/ProfileSheets.kt:583 | delete alert Delete ↔ spinner `.easeInOut(0.2)` | MATCH | |
