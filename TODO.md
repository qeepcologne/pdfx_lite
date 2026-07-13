# TODO

Open issues for `pdfx_lite`, forked from `pdfx` 2.9.3 (2026-07-10). See `CHANGELOG.md` for what already changed.

## Blocking

- [ ] **iOS has never been built.** Android now builds and runs (`example/`, debug APK on a physical device), but no
      Xcode run has touched this package — and the `SwiftPdfxPlugin.swift` rewrite for pigeon 27 was done on Linux,
      so it is **reviewed, not compiled**. Build and run `example/` on a Mac before trusting the iOS half.
- [ ] **No tests.** All 8 upstream tests drove `PdfxPlatformMethodChannel`, which was removed (pigeon covers both
      remaining platforms). A pigeon-based suite needs `BasicMessageChannel` mocking and has not been written.

## API

- [ ] Decide whether `password` stays. `PdfDocument.openFile/openAsset/openData` accept it and it travels all the way
      over the wire, but **neither Android nor iOS reads it** — only the web renderer ever honoured it, and encrypted
      documents just fail to open. It is currently kept, and documented as ignored, for source compatibility with
      `pdfx`. Removing it from the public API and the schema would be honest but breaking; a caller relying on it today
      is silently getting nothing.

## Repo

- [ ] Create `qeepcologne/pdfx_lite` on GitHub and push (6 local commits).
- [ ] Report the Android crop bug (`cropW` read from `width` instead of `cropWidth`, fixed here) upstream against
      `ScerIO/packages.flutter` — it is still broken in `pdfx` and affects every Android user of `render(cropRect:)`.

## Won't do

- **Upstreaming.** This fork drops platforms; `ScerIO/packages.flutter` would not take it. Bug fixes to the shared
  renderer/viewer code still belong upstream.
- **Restoring `RgbaData`** or the in-memory `getPixels(bytes:)` path. Both were reachable only from the web renderer.
