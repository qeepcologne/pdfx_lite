# TODO

Work carried over from upstream [`ScerIO/packages.flutter`](https://github.com/ScerIO/packages.flutter) — bugs and PRs
still relevant now that `pdfx_lite` is Android + iOS only. Issue/PR numbers are upstream's.

**Done in 3.1.0:** the `documentProgress` NaN crash (#602, #604) and the self-contradicting default render format
(#581). See the CHANGELOG.

---

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

## 2. Needs Android API 35

Two features that are cheap on iOS and gated behind **Android 15** — `minSdk` is 24, so they would work for a small
minority of Android users. Grouped because they share the same constraint and the same decision.

### 2.1 Password / encrypted PDFs · #600, #618, #550

`password:` was **removed in 3.0.0** because it was a silent no-op: it crossed the wire and neither platform read it,
so encrypted PDFs failed to open regardless. Upstream is now implementing it for real (#600).

- **iOS — works on every version.** `CGPDFDocument.unlockWithPassword(password)`, then check `isUnlocked`.
- **Android — API 35+ only.** `PdfRenderer(fd, LoadParams.Builder().setPassword(…).build())`, gated on
  `SDK_INT >= 35` **and** `SdkExtensions.getExtensionVersion(S) >= 13`. Below that, upstream's own patch just throws.

### 2.2 Annotations not rendered · #592, #584

`Page.kt:25` and `Messages.kt:325` hardcode `RENDER_MODE_FOR_DISPLAY`, which does not draw annotations. Android 15
added `RenderParams` with `FLAG_RENDER_HIGHLIGHT_ANNOTATIONS` / `FLAG_RENDER_TEXT_ANNOTATIONS`. iOS (`CGPDFPage`)
draws annotations already, so this is Android-only catch-up.

### The decision, for both

Shipping either means: **works on all iPhones, fails on most Android phones in the field.** That asymmetry has to be
deliberate and documented, not a surprise — a half-working API is exactly what 3.0.0 removed `password` to escape.

1. **Leave both out** until Android 15 is widespread. Honest, nothing half-broken. ← default
2. **Add them, platform-gated**, throwing a *typed, catchable* error (not the generic "Can't create PDF renderer") so
   callers can detect and fall back.

Pick (2) only when something actually needs it — e.g. if `esim-app` ever has to open encrypted invoices.

---

## 3. Do not take

- **#583 "Replace `onSurfaceCleanup` with `onSurfaceDestroyed`"** — backwards. Flutter's engine marks
  `onSurfaceDestroyed` `@Deprecated(since = "Flutter 3.28", forRemoval = true)`; `onSurfaceCleanup` is the
  replacement and we already use it. Upstream issues #588 and #580 are the fallout of *not* being on it.
- **#620** (Windows ARM64), **#612** (Windows CMake), **#611** / **#610** (wasm), and the pdf.js/web issues —
  platforms dropped.
- **#609** (SPM support) — this fork's own upstream PR; already in.
- **#594 "Expose `InteractiveViewer` onInteraction-methods"** — three nullable callbacks that do nothing unless a
  caller passes them. Speculative public API for a use case nobody here has; it stays a 15-line change if one ever
  turns up. Add it when something needs it, not before.

---

## 4. Give back to upstream

Fixes `pdfx_lite` has that `pdfx` 2.9.2 does not. The first two are the ones that actually break people:

- **`PdfViewPinch(scrollDirection: Axis.horizontal)` throws and renders blank** — the NaN divide-by-zero above.
  Reproduced on device. Upstream has two partial patches open (#602, #604) but neither is merged.
- **Android crop bug** — `renderPage` reads the crop width from `message.width` instead of `message.cropWidth`, so
  `Bitmap.createBitmap(bmp, cropX, cropY, cropW, cropH)` violates `cropX + cropW <= bitmap.width` and **throws** for
  any crop not flush to the left edge. One-line fix.
- iOS `renderPage` calling its completion twice on error, reporting failure as `completion(nil, nil)`.
- An unsynchronised data race in the iOS document/page repositories.
- A `CoroutineScope` leaked per render on Android.
