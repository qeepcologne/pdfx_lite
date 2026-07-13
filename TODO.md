# TODO

Open issues for `pdfx_lite`, forked from `pdfx` 2.9.3 (2026-07-10). See `CHANGELOG.md` for what already changed.

## Blocking

- [ ] **iOS has never been built.** Android now builds and runs (`example/`, debug APK on a physical device), but no
      Xcode run has touched this package — and the `SwiftPdfxPlugin.swift` rewrite for pigeon 27 was done on Linux,
      so it is **reviewed, not compiled**. Build and run `example/` on a Mac before trusting the iOS half.
- [ ] **No tests.** All 8 upstream tests drove `PdfxPlatformMethodChannel`, which was removed (pigeon covers both
      remaining platforms). A pigeon-based suite needs `BasicMessageChannel` mocking and has not been written.

## Won't do

- **Upstreaming.** This fork drops platforms; `ScerIO/packages.flutter` would not take it. Bug fixes to the shared
  renderer/viewer code still belong upstream.
- **Restoring `RgbaData`** or the in-memory `getPixels(bytes:)` path. Both were reachable only from the web renderer.
