# TODO

Work carried over from upstream [`ScerIO/packages.flutter`](https://github.com/ScerIO/packages.flutter) — bugs and PRs
that are still relevant now that `pdfx_lite` is Android + iOS only. Upstream issue/PR numbers are theirs.

Items marked **confirmed** were verified against this codebase. The rest are upstream reports that plausibly apply and
need reproducing first — don't fix what you haven't reproduced.

---

## 1. Bugs

### 1.1 `documentProgress` NaN crash — **confirmed**, throws · #602, #604

`lib/src/viewer/pinch/pdf_view_pinch.dart:287`

```dart
final rawDocumentProgress =
    ((exposed.bottom / r - _lastViewSize!.height) /
        (_docSize!.height - _lastViewSize!.height));   // denominator == 0 when the doc fits the viewport
...
((rawDocumentProgress * precisionFactor).round() / precisionFactor)   // .round() THROWS on NaN/Infinity
```

When the document is exactly as tall as the viewport — an ordinary single-page PDF — the denominator is zero, giving
`NaN` or `Infinity`, and Dart's `.round()` raises `UnsupportedError` on both. Not a cosmetic glitch: it throws.

Upstream has two competing patches: #602 clamps a non-finite result to `0.0`; #604 skips the update when
`_docSize.height == _lastViewSize.height`. Take the *guard* (#604 — don't compute a meaningless ratio) **and** keep a
non-finite fallback, since `r` could in principle be degenerate too.

Ship as **3.0.1**. Repro: open a single-page PDF that fits the viewport in `PdfViewPinch`.

### 1.2 Default render format disagrees with itself — **confirmed** · #581

| Declaration | Default |
|---|---|
| `lib/src/renderer/interfaces/page.dart:69` — `PdfPage.render()`, the abstract API callers see | `jpeg` |
| `lib/src/renderer/io/platform_pigeon.dart:130` — `PdfPagePigeon.render()`, the implementation | `png` |
| Android `Messages.kt:185` / iOS `CompressFormat` — native fallback when `format` is null | `png` |

Dart resolves a default argument from the **static type at the call site**, and `PdfDocument.getPage()` returns
`PdfPage` — so callers get `jpeg` while every other layer assumes `png`. It also silently flips the background:
`platform_pigeon.dart` picks `#FFFFFF` for jpeg and `#00FFFFFF` (transparent) for png.

Align on `png`, as upstream #581 does. **Behaviour change** for anyone calling `render()` without `format:` (bigger
files, transparent background), so **3.1.0**, called out in the changelog.

### 1.3 iOS landscape aspect-ratio distortion · #554

`ios/.../Document.swift:66` swaps width/height when `isLandscape` (rotation 90/270) and derives the drawing transform
from that. Suspect, but unverified here. **Reproduce first** with a rotated/landscape PDF on iOS, comparing against
the same page on Android.

### 1.4 Android blurry / broken text · #560 (since Flutter 3.27), #585 (pinch-zoom, landscape)

Both point at the texture path — `Messages.kt` `onDocumentOrSurfaceChanged`, which builds the `Matrix` from
`fullWidth/page.width` and renders into a `SurfaceProducer` bitmap. Plausible: we render at the *texture* size rather
than at device-pixel-ratio, so a zoomed page resamples. **Reproduce** on a device at high zoom before touching it.

### 1.5 Wrong height reported for some documents · #532

`getPage` returns `page.width/height` straight from the native renderer. Needs the reporter's PDF to reproduce.

### 1.6 Annotations not rendered · #592, #584

`Page.kt:25` and `Messages.kt:325` hardcode `RENDER_MODE_FOR_DISPLAY`, which does not draw annotations. Android 15
(API 35) added `RenderParams` with `FLAG_RENDER_HIGHLIGHT_ANNOTATIONS` / `FLAG_RENDER_TEXT_ANNOTATIONS`. Same API-35
gate as password support (§3) — so it is opt-in and only on new devices. Do it *with* §3 or not at all.

### 1.7 Cyrillic not displayed on Android · #557

Font-embedding issue in the platform `PdfRenderer`; may not be ours to fix. Needs the reporter's PDF.

---

## 2. Port from upstream PRs

### 2.1 Expose `InteractiveViewer`'s interaction callbacks · #594 — small

Add `onInteractionStart` / `onInteractionUpdate` / `onInteractionEnd` to `PdfViewPinch` and forward them. **Nearly
free now**: since we dropped the vendored viewer, `PdfViewPinch` builds Flutter's `InteractiveViewer`, which already
takes all three. Purely additive → **3.1.0**.

---

## 3. Password / encrypted PDFs — decision needed · #600, #618, #550

`password:` was **removed** in 3.0.0 because it was a silent no-op: it crossed the wire and neither platform read it,
so encrypted PDFs failed to open anyway. Upstream is now implementing it for real (#600), and users keep asking
(#618, #550). Re-adding it is possible — but the two platforms are not equal:

- **iOS — works everywhere.** `CGPDFDocument.unlockWithPassword(password)`, then check `isUnlocked`. Clean.
- **Android — API 35+ only.** Needs `PdfRenderer(fd, LoadParams.Builder().setPassword(…).build())`, gated on
  `SDK_INT >= 35` **and** `SdkExtensions.getExtensionVersion(S) >= 13`. Below that, upstream's own patch just throws.
  With `minSdk 24`, that is *most devices in the field*.

So "password support" would mean: works on all iPhones, fails on the large majority of Android phones. That
asymmetry has to be a deliberate, documented choice, not a surprise.

**Options:**
1. **Leave it out** (status quo). Honest, and no half-working API. Revisit when Android 15 is widespread.
2. **Add it, platform-gated**, and document plainly that Android needs API 35 + extension 13 — throwing a *typed*,
   catchable error (not the generic "Can't create PDF renderer") when unsupported, so callers can fall back.

Recommend **(2) only if `esim-app` actually needs encrypted invoices**; otherwise **(1)**. Do not ship it silently
half-working — that is the exact trap 3.0.0 removed.

---

## 4. Do not take

- **#583 "Replace `onSurfaceCleanup` with `onSurfaceDestroyed`"** — backwards. Flutter's engine marks
  `onSurfaceDestroyed` `@Deprecated(since = "Flutter 3.28", forRemoval = true)`; `onSurfaceCleanup` is the
  replacement, and we already use it. Upstream issues #588 and #580 are the fallout of *not* being on it — already
  fixed here.
- **#620** (Windows ARM64), **#612** (Windows CMake), **#611** / #610 (wasm), pdf.js/web issues — platforms dropped.
- **#609** (SPM support) — that is this fork's own upstream PR; already in.

---

## 5. Give back to upstream

Four fixes `pdfx_lite` has that `pdfx` 2.9.2 does not. The first one breaks people:

- **Android crop bug** — `renderPage` reads the crop width from `message.width` instead of `message.cropWidth`, so
  `Bitmap.createBitmap(bmp, cropX, cropY, cropW, cropH)` violates `cropX + cropW <= bitmap.width` and **throws** for
  any crop not flush to the left edge. One-line fix. Worth an issue + PR on its own.
- iOS `renderPage` calling its completion twice on error, and reporting failure as `completion(nil, nil)`.
- Unsynchronised data race in the iOS document/page repositories.
- A `CoroutineScope` leaked per render on Android.
