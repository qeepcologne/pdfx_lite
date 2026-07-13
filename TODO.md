# TODO

Open issues for `pdfx_lite`, forked from `pdfx` 2.9.3 (2026-07-10). See `CHANGELOG.md` for what already changed.

## Blocking

- [ ] **iOS has never been built.** Android builds and runs (`example/`, debug APK on a physical device), but no Xcode
      run has touched this package. Two large Swift changes were written on Linux, with **no compiler**, and are
      therefore **reviewed, not compiled**:
      1. the pigeon 27 rewrite of `SwiftPdfxPlugin.swift`;
      2. the **Swift 6 language mode** migration (`Package.swift` → `swift-tools-version: 6.0` +
         `.swiftLanguageMode(.v6)`), with `@unchecked Sendable` on the plugin / `Document` / `Page` /
         `PdfPageTexture`, an `NSLock` inside `Repository`, and an `UncheckedSendable` box to carry pigeon's
         non-`@Sendable` completions across the render queue.

      Expect the first Mac build to surface strict-concurrency errors — that is the *point* of v6, and I could not
      iterate against a compiler. If it fights back, the escape hatch is `.swiftLanguageMode(.v5)` in `Package.swift`,
      which restores today's semantics without reverting anything else.
- [ ] **No tests.** All 8 upstream tests drove `PdfxPlatformMethodChannel`, which was removed (pigeon covers both
      remaining platforms). A pigeon-based suite needs `BasicMessageChannel` mocking and has not been written.

## Won't do

- **Upstreaming.** This fork drops platforms; `ScerIO/packages.flutter` would not take it. Bug fixes to the shared
  renderer/viewer code still belong upstream.
- **Restoring `RgbaData`** or the in-memory `getPixels(bytes:)` path. Both were reachable only from the web renderer.
