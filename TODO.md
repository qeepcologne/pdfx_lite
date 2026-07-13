# TODO

Open issues for `pdfx_lite`, forked from `pdfx` 2.9.3 (2026-07-10). See `CHANGELOG.md` for what already changed.

## Blocking

- [ ] **iOS has never been built.** Android now builds and runs (`example/`, debug APK on a physical device), but no
      Xcode run has touched this package — and the `SwiftPdfxPlugin.swift` rewrite for pigeon 27 was done on Linux,
      so it is **reviewed, not compiled**. Build and run `example/` on a Mac before trusting the iOS half.
- [ ] **No tests.** All 8 upstream tests drove `PdfxPlatformMethodChannel`, which was removed (pigeon covers both
      remaining platforms). A pigeon-based suite needs `BasicMessageChannel` mocking and has not been written.

## Android

- [ ] `namespace` is `io.scer.pdf_renderer` while the plugin package is `io.scer.pdfx`. Left as upstream had it: the
      library ships no resources, so the namespace only names the manifest package, and renaming risks the plugin
      registrant for no gain. Revisit only if AGP starts caring.

## Repo

- [ ] Create `qeepcologne/pdfx_lite` on GitHub and push (8 local commits).
- [ ] Report the Android crop bug (`cropW` read from `width` instead of `cropWidth`, fixed here) upstream against
      `ScerIO/packages.flutter` — it is still broken in `pdfx` and affects every Android user of `render(cropRect:)`.

## Won't do

- **Upstreaming.** This fork drops platforms; `ScerIO/packages.flutter` would not take it. Bug fixes to the shared
  renderer/viewer code still belong upstream.
- **Restoring `RgbaData`** or the in-memory `getPixels(bytes:)` path. Both were reachable only from the web renderer.
