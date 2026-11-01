import Testing

/// Fase 23a K4: every unit test that loads a real `WKWebView` runs inside this suite, one at a time,
/// so two WebContent processes never start together on a slow CI runner (flake F2). The suites
/// themselves are `extension WebKitTests` in `PageCopyTests.swift` and `ReplicaViewTests.swift`.
@MainActor
@Suite(.serialized)
struct WebKitTests {}
