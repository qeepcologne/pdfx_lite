# TODO

Work carried over from upstream [`ScerIO/packages.flutter`](https://github.com/ScerIO/packages.flutter) — bugs and PRs
still relevant now that `pdfx_lite` is Android + iOS only. Issue/PR numbers are upstream's.

## 1. Needs verification

Upstream reports that plausibly still apply to us, but which nobody has reproduced against this codebase. **Reproduce
before fixing** — several may already be dead, or may not be ours to fix.

| # | Report | Where to look | Repro needed |
|---|---|---|---|
| #560 | Android: blurry/broken text since Flutter 3.27 | `Messages.kt` `onDocumentOrSurfaceChanged` — the texture `Matrix` is built from `fullWidth / page.width` | High-DPI device; suspect we render at texture size, not device pixel ratio |
| #585 | Blurry text when pinch-zooming in landscape | same texture path as #560 — probably the same bug | Zoom in hard on a landscape page |
| #532 | Wrong height returned for certain documents | possibly **already fixed** in 3.8.0 — iOS's `getPage` used to report the raw mediaBox, so any rotated page came back with height and width swapped | Needs the reporter's PDF to confirm |

## 2. Annotations are not rendered — on either platform · #592, #584

Bigger than it looks. Neither side draws annotations today, and the fixes are unrelated:

- **Android** — `Page.kt:25` and `Messages.kt:325` hardcode `RENDER_MODE_FOR_DISPLAY`, which skips annotations.
  Android 15 added `RenderParams` with `FLAG_RENDER_HIGHLIGHT_ANNOTATIONS` / `FLAG_RENDER_TEXT_ANNOTATIONS` — so this
  half is gated on **API 35**, and would simply not render annotations below it.
- **iOS** — we draw with Core Graphics (`context.drawPDFPage`, `Document.swift:100` and `SwiftPdfxPlugin.swift:358`),
  which renders the page content stream only; annotations are separate PDF objects and are skipped. Rendering them
  means moving to **PDFKit** (`PDFPage.draw(with:to:)`) — available since iOS 11, so on every version we support, but
  it is a **renderer rewrite** touching both the image path and the texture path, not a flag.

So: Android is blocked on Android 15, iOS is a rewrite. Do neither speculatively.

### Should iOS move to PDFKit at all?

**The driver is gone.** #554 was the experiment that would have decided it, and it turned out to be a sizing bug, not
a rendering-engine one: `getPage` reported the unrotated mediaBox while the texture path worked in rotated space.
Fixed in 3.8.0 without leaving Core Graphics, and the hand-rolled `getDrawingTransform` workaround that PDFKit would
have replaced is gone too — `Document.render` now builds its transform explicitly and handles rotation itself.

PDFKit is Apple's modern PDF API (`CGPDFDocument` is the low-level legacy one), and it would still render annotations,
links and form fields. But with #554 closed, nothing broken is waiting on it.

(It would *not* buy encrypted-document support — `CGPDFDocument.unlockWithPassword` already gives us that on iOS.)

Against it, today:

1. **It would make the platforms render differently.** Android's `PdfRenderer` skips annotations too (pre-API 35), so
   both platforms are currently consistent. PDFKit on iOS alone means the same PDF looks different on iOS and Android
   — for a cross-platform plugin that is arguably worse than both being equally limited.
2. **It is a rewrite of the half we cannot compile locally** — both the image path (`Document.swift`) and the texture
   path (`SwiftPdfxPlugin.updateTex`) go through `drawPDFPage`.
3. **Nothing needs it.** No caller here wants annotations.

If it is ever done: `PDFDocument` is **not thread-safe** for concurrent access, and `renderPage` runs on `dispQueue` —
the draw has to stay serialised (the `Repository` lock covers the lookup, not the render).

---

## 3. Do not take

- **#557 "Cyrillic not displayed on Android"** — not ours. Embedded-font Cyrillic renders correctly on Android
  (verified via `example/lib/cyrillic_probe.dart` + `cyrillic_embedded.pdf`); only a PDF with a non-embedded `/Arial`
  reference drops it, and poppler drops that same file too. Renderer font-substitution, not fixable from the plugin —
  the reporter's PDF just needs its font embedded.
- **Upstreaming our fixes.** `ScerIO/packages.flutter` released `pdfx` 2.10.0 and 2.11.0 in a single day
  (2026-08-20) after 14 months without a release, and nothing has landed for `pdfx` since; none of the reports above
  were touched. Nothing from those two releases was missing here except #594 (taken in 3.12.0): the NaN crash was
  already fixed in 3.1.0, and SPM, AGP 9 and the `Matrix4` deprecations were covered too. Patches sent there would
  sit. Our fixes are recorded in the README and CHANGELOG instead, which is where anyone who lands on this fork will
  actually find them.
