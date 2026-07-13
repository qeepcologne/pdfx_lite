# TODO

Work carried over from upstream [`ScerIO/packages.flutter`](https://github.com/ScerIO/packages.flutter) — bugs and PRs
still relevant now that `pdfx_lite` is Android + iOS only. Issue/PR numbers are upstream's.

## 1. Needs verification

Upstream reports that plausibly still apply to us, but which nobody has reproduced against this codebase. **Reproduce
before fixing** — several may already be dead, or may not be ours to fix.

| # | Report | Where to look | Repro needed |
|---|---|---|---|
| #554 | iOS: aspect-ratio distortion on landscape PDFs | `ios/.../Document.swift:58,66` — `isLandscape` swaps width/height and feeds the drawing transform | A rotated / landscape page on iOS, compared against the same page on Android |
| #560 | Android: blurry/broken text since Flutter 3.27 | `Messages.kt` `onDocumentOrSurfaceChanged` — the texture `Matrix` is built from `fullWidth / page.width` | High-DPI device; suspect we render at texture size, not device pixel ratio |
| #585 | Blurry text when pinch-zooming in landscape | same texture path as #560 — probably the same bug | Zoom in hard on a landscape page |
| #532 | Wrong height returned for certain documents | `getPage` returns the native renderer's `width`/`height` verbatim | Needs the reporter's PDF |
| #557 | Cyrillic characters not displayed on Android | Platform `PdfRenderer` font embedding — quite possibly **not ours** | Needs the reporter's PDF |

## 2. Password / encrypted PDFs — blocked on Android API 35 · #600, #618, #550

`password:` was **removed in 3.0.0** because it was a silent no-op: it crossed the wire and neither platform read it,
so encrypted PDFs failed to open regardless. Upstream is now implementing it for real (#600).

- **iOS — free, works on every version we support.** `CGPDFDocument.unlockWithPassword(password)`, then check
  `isUnlocked`. Available since iOS 2.0.
- **Android — API 35+ only.** `PdfRenderer(fd, LoadParams.Builder().setPassword(…).build())`, gated on
  `SDK_INT >= 35` **and** `SdkExtensions.getExtensionVersion(S) >= 13`. Below that, upstream's own patch just throws.
  `minSdk` is 24, so that is most devices in the field.

Shipping it means: **works on every iPhone, fails on most Android phones.** That asymmetry has to be deliberate and
documented — a half-working API is exactly what 3.0.0 removed `password` to escape.

1. **Leave it out** until Android 15 is widespread. ← default
2. **Add it, platform-gated**, throwing a *typed, catchable* error (not the generic "Can't create PDF renderer") so
   callers can detect it and fall back.

Pick (2) only when something actually needs it — e.g. if `esim-app` ever has to open encrypted invoices.

## 3. Annotations are not rendered — on either platform · #592, #584

Bigger than it looks. Neither side draws annotations today, and the fixes are unrelated:

- **Android** — `Page.kt:25` and `Messages.kt:325` hardcode `RENDER_MODE_FOR_DISPLAY`, which skips annotations.
  Android 15 added `RenderParams` with `FLAG_RENDER_HIGHLIGHT_ANNOTATIONS` / `FLAG_RENDER_TEXT_ANNOTATIONS` — so this
  half carries the same **API 35** gate as §2.
- **iOS** — we draw with Core Graphics (`context.drawPDFPage`, `Document.swift:100` and `SwiftPdfxPlugin.swift:358`),
  which renders the page content stream only; annotations are separate PDF objects and are skipped. Rendering them
  means moving to **PDFKit** (`PDFPage.draw(with:to:)`) — available since iOS 11, so on every version we support, but
  it is a **renderer rewrite** touching both the image path and the texture path, not a flag.

So: Android is blocked on Android 15, iOS is a rewrite. Do neither speculatively.

---

## 4. Do not take

- **PR #594 "Expose `InteractiveViewer` onInteraction-methods"** — a *feature* PR, not a bug: nothing is broken. It
  adds three nullable callbacks that do nothing unless a caller passes them. Speculative public API for someone else's
  use case; it stays a 15-line change if one ever turns up here. Add it when something needs it, not before.
- **Upstreaming our fixes.** `ScerIO/packages.flutter` is dormant: no release since `pdfx` 2.9.2 (June 2025), no
  commit to the repo since December 2025, ~200 open issues and PRs unmerged for over a year — including the two
  partial patches for the NaN crash we fixed in 3.1.0. Patches sent there would sit. Our fixes are recorded in the
  README and CHANGELOG instead, which is where anyone who lands on this fork will actually find them.
