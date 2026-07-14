# TODO

Work carried over from upstream [`ScerIO/packages.flutter`](https://github.com/ScerIO/packages.flutter) — bugs and PRs
still relevant now that `pdfx_lite` is Android + iOS only. Issue/PR numbers are upstream's.

## 1. Needs verification

Upstream reports that plausibly still apply to us, but which nobody has reproduced against this codebase. **Reproduce
before fixing** — several may already be dead, or may not be ours to fix.

| # | Report | Where to look | Repro needed |
|---|---|---|---|
| #554 | iOS: aspect-ratio distortion on landscape PDFs — **do this one first**, it decides the PDFKit question in §2 | `ios/.../Document.swift` — `isLandscape` swaps width/height and feeds the drawing transform | A rotated / landscape page on iOS, compared against the same page on Android |
| #560 | Android: blurry/broken text since Flutter 3.27 | `Messages.kt` `onDocumentOrSurfaceChanged` — the texture `Matrix` is built from `fullWidth / page.width` | High-DPI device; suspect we render at texture size, not device pixel ratio |
| #585 | Blurry text when pinch-zooming in landscape | same texture path as #560 — probably the same bug | Zoom in hard on a landscape page |
| #532 | Wrong height returned for certain documents | `getPage` returns the native renderer's `width`/`height` verbatim | Needs the reporter's PDF |
| #557 | Cyrillic characters not displayed on Android | Platform `PdfRenderer` font embedding — quite possibly **not ours** | Needs the reporter's PDF |

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

Probably, eventually — but it needs a driver, and **#554 is the experiment that decides it.**

PDFKit is Apple's modern PDF API (`CGPDFDocument` is the low-level legacy one). It would render annotations, links and
form fields. It also handles page rotation and display boxes itself, which is *exactly* the hand-rolled `isLandscape` /
`getDrawingTransform` code that #554 blames. So if #554 reproduces, PDFKit stops being a speculative modernisation and
becomes the fix for a confirmed bug, with annotations riding along.

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

- **PR #594 "Expose `InteractiveViewer` onInteraction-methods"** — a *feature* PR, not a bug: nothing is broken. It
  adds three nullable callbacks that do nothing unless a caller passes them. Speculative public API for someone else's
  use case; it stays a 15-line change if one ever turns up here. Add it when something needs it, not before.
- **Upstreaming our fixes.** `ScerIO/packages.flutter` is dormant: no release since `pdfx` 2.9.2 (June 2025), no
  commit to the repo since December 2025, ~200 open issues and PRs unmerged for over a year — including the two
  partial patches for the NaN crash we fixed in 3.1.0. Patches sent there would sit. Our fixes are recorded in the
  README and CHANGELOG instead, which is where anyone who lands on this fork will actually find them.
