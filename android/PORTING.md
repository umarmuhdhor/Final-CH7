# Porting the iOS app to Android — rules for everyone working on it

Goal: the Android app (`android/app`) looks and behaves **identically** to the iOS app (`ios/ShooApp`). Same screens,
same layout numbers (1 pt = 1 dp, 1 pt text = 1 sp), same colours, same images, same copy, same flows, same motion.
The Swift source is the spec. When in doubt, read the Swift file and do what it does.

Only these may differ, because Apple licenses forbid them on Android or Android has no such thing:
- Font: SF Pro / SF Pro Rounded / SF Pro Text → **Inter** (`R.font.inter_variable`, variable `wght` + `opsz`). See `components/FigmaFont.kt`.
- SF Symbols → the closest **Material Symbols** icon (`androidx.compose.material:material-icons-extended`, Rounded set first).
  All mappings live in ONE place: `components/Symbols.kt` (`sfSymbol("exclamationmark.triangle.fill")`). Add missing names there.
- Safari Web Extension → the **Shoo add-on in Firefox for Android** (`firefox-addon/`, `bridge/AddonBridge.kt`). Screens about
  turning the Safari extension on keep their iOS layout, but their copy and steps describe Firefox (see "Copy" below).
- APNs push → `notify/GuardianCheckJob.kt` (polling + local notifications) until FCM exists.
- iOS system UI (share sheet, alerts, system permission prompts) → the Android equivalent.

## Layout of the Kotlin code (mirror the Swift folders, same file and type names)

```
com.shoo.app
  app/         AppEnvironment, Router, AppSettings, AppConfig, DeepLink        (ios/ShooApp/App)
  data/        Models, ShooRepository, ApiRepository, ApiClient, MockRepository, MockScenarios,
               SessionStore, CheckStats, ExtensionStatus (= Firefox add-on status), LinkedAccountSettings, LossyList
  support/     L10n, AppLanguage, Formatters, ScoreLevel, DeviceInfo, NotificationPermission, NotificationRouter
  components/  every file of ios/ShooApp/Components + Symbols.kt + Images.kt
  features/onboarding|shield|activity|detail|pairing|profile|main   (ios/ShooApp/Features/*)
  bridge/      AddonBridge (keep)            notify/  GuardianCheckJob (keep, adapt to the new data layer)
```
One Swift file → one Kotlin file with the same name (`GuardianHomeView.swift` → `GuardianHomeView.kt`). Keep the Swift
type and function names (Kotlin casing). Keep the Swift doc comments that explain *why* (shortened is fine).

## SwiftUI → Compose

| SwiftUI | Compose |
|---|---|
| `@Observable final class X` | class with `var a by mutableStateOf(...)` fields |
| `@State`, `@Binding` | `remember { mutableStateOf() }`, value + `(T) -> Unit` |
| `@Environment(AppEnvironment.self)` | `LocalAppEnvironment.current` |
| `@Environment(\.locale)` / language | `LocalAppLanguage.current` |
| `\.shooReduceMotion`, `\.shooReduceGlass` | `LocalReduceMotion.current`, `LocalReduceGlass.current` |
| `VStack(spacing: 8)` | `Column(verticalArrangement = Arrangement.spacedBy(8.dp))` |
| `.padding(.horizontal, 24)` | `Modifier.padding(horizontal = 24.dp)` (order matters: SwiftUI modifiers apply outside-in like Compose) |
| `.frame(width:height:)`, `.frame(maxWidth: .infinity)` | `Modifier.size()`, `fillMaxWidth()` |
| `RoundedRectangle(cornerRadius: r, style: .continuous)` | `RoundedCornerShape(r.dp)` |
| `Capsule()` | `RoundedCornerShape(50)` / `CircleShape` |
| `.shadow(color:radius:y:)` | `Modifier.shooShadow(...)` in `components/CardShadow.kt` (draws a real blurred shadow, radius = Figma blur / 2) |
| `LinearGradient` | `Brush.linearGradient / verticalGradient` |
| `TimelineView(.animation)` | `withInfiniteAnimationFrameMillis` loop / `rememberInfiniteTransition` |
| `Canvas` | `Canvas` |
| `.spring(duration: d, bounce: b)` | `shooSpring(d, b)` in `components/Motion.kt` |
| `withAnimation(.easeOut(duration:))` | `animateXAsState(tween(ms, easing = EaseOut))` |
| `.sheet`, `.presentationDetents` | `ModalBottomSheet` (match the corner radius and height of the iOS sheet) |
| `.fullScreenCover` | a full-screen route / `Dialog(usePlatformDefaultWidth = false)` |
| `NavigationStack(path:)` | `Router` back stacks (`shieldPath`, `activityPath`) rendered by `MainTabView` |
| `.task { }`, `.onAppear` | `LaunchedEffect(Unit) { }` |
| `.accessibilityLabel/Identifier` | `Modifier.semantics { contentDescription = ...; testTag = "<same identifier>" }` |
| `ProgressView()` | `CircularProgressIndicator` sized like iOS (20 dp) |
| `Image("Name")` | `painterResource(R.drawable.<snake_case(Name)>)` — e.g. `HeroGradientBlue` → `R.drawable.hero_gradient_blue` |

Never invent a layout. Port the numbers. If something has no Compose equivalent, get as close as possible and leave a
one-line `// iOS: …` comment saying what differs.

## Copy (strings)

- All copy comes from `ios/ShooApp/Resources/Localizable.xcstrings`, copied into the APK at build time. The key is the
  English source text, exactly as in Swift: `Text("Recent activity")` → `Text(t("Recent activity"))`.
- `@Composable fun t(key: String, vararg args: Any): String` and `L10n.string(key, language, vararg args)` (support/L10n.kt).
  Swift interpolation `Text("\(name) opened a risky page")` has key `"%@ opened a risky page"` in the catalog: pass
  `t("%@ opened a risky page", name)`. Integers: `%lld`. Look the key up in the catalog to be sure.
- The app starts in Bahasa Indonesia (`AppLanguage.defaultLanguage`), changeable in Profile, like iOS.
- Android-only copy (Firefox instead of Safari, Android permission wording) goes into
  `android/app/src/main/l10n/android.xcstrings` (same format, en + id). Never edit the iOS catalog.

## Data and behaviour

- Same contracts (`contracts/`). `MockRepository` + `MockScenarios` mirror the iOS ones (Debug default backend = mock).
- Keep privacy rules from `ios/ShooApp/CLAUDE.md` and `plan/alief/SECURITY.md` §3: token in the Keystore-encrypted
  `SessionStore`, no third-party analytics, nothing about scans written to disk caches, favicons only from our Worker.

## Working together

- Only touch the files of your assignment. Shared files (`components/`, `support/`, `app/`, `data/`) belong to the
  foundation; if you need something there, write it in your own feature file as `private` and report it.
- Do **not** run Gradle (several people edit at once; the integrator builds). Re-read your code for compile errors:
  imports, nullability, `@Composable` context, `remember` keys.
- Never edit anything under `ios/`, `contracts/`, `chrome/`, `detector/`, `backend/`, `ai/`.
