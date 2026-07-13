# pdfx_lite

Standalone PDF renderer & viewer for Flutter on **Android and iOS** — a replacement for [`pdfx`](https://github.com/ScerIO/packages.flutter/tree/main/packages/pdfx), with the Web, macOS and Windows renderers removed.

**Purpose:** minimal and legacy-free, for **current toolchains only** — no CocoaPods (SPM only), no `pdf.js`, no CMake, and built against the latest Flutter, AGP, Gradle, Android SDK and Xcode rather than older ones. If you need Web, desktop, or CocoaPods, use the upstream package instead.

> **Status: Android verified, iOS not yet built.** Android is built and driven on a real device (see `example/`).
> The iOS half — the pigeon 27 port *and* the Swift 6 strict-concurrency migration — was written on a Linux machine
> with no Xcode, so its Swift is **reviewed, not compiled**. Expect the first Mac build to find things; if strict
> concurrency fights back, `.swiftLanguageMode(.v5)` in `Package.swift` restores the old semantics without giving up
> the `Repository` lock. Don't ship iOS on this until someone has built it on a Mac.
>
> There are also **no tests** — the 8 upstream ones drove the method-channel implementation, which is gone.

Includes 2 APIs, unchanged from upstream:
- `renderer` — work with a PDF document, its pages, render a page to an image
- `viewer` — Flutter widgets & controllers to show the render result

## What changed vs upstream

| | pdfx | pdfx_lite |
|---|---|---|
| Platforms | Android, iOS, macOS, Windows, Web | **Android, iOS** |
| Platform channel | pigeon 4 (mobile) + method channel (web/Windows) | pigeon 27 only — generated Kotlin + Swift + Dart |
| Generated native bridge | 1479 lines of Java + a hand-translated `Messages.swift` | generated from one schema, no Java |
| **Android** | | |
| minSdk / compileSdk | 16 / 35 | 24 / 37 |
| Gradle | 8.10.2 | 9.6.1 |
| AGP | Groovy `build.gradle`, AGP 8.5.2 + `kotlin-android` | **9 only**, Kotlin DSL |
| **iOS** | | |
| Integration | CocoaPods podspec + SPM | **SPM only** |
| Deployment target | 13.0 | 15.0 |
| Swift / Swift-Tools | 5 / 5.9 | **6 / 6.2** — strict concurrency, Xcode 26+ |
| **Dart** | | |
| Dart / Flutter | >=3.3 / >=3.24 | ^3.12 / >=3.44 |
| Dependencies | + `flutter_web_plugins`, `web`, `universal_platform`, `uuid`, `extension`, `plugin_platform_interface` | those six dropped — only `meta`, `photo_view`, `synchronized`, `vector_math` remain |

Everything else — the public API, the pinch/simple viewers, the Android and iOS native renderers — is upstream's.

### Bug fixes not in upstream

- **Cropped rendering on Android was broken.** `renderPage` took the crop width from the *render* width instead of
  `cropWidth`, so a crop always spanned the full width — and because the native code then calls
  `Bitmap.createBitmap(bmp, cropX, cropY, cropW, cropH)`, which requires `cropX + cropW <= bitmap.width`, any crop with
  `cropX > 0` threw `IllegalArgumentException: x + width must be <= bitmap.width()`, surfacing in Dart as
  `PlatformException(pdf_renderer, Unexpected error, …)`. So `render(cropRect: …)` did not merely return the wrong
  region on Android, it failed outright whenever the crop was not flush to the left edge. iOS was always correct.
  Still broken in `pdfx` as of 2.9.3.
- **`renderPage` on iOS called its completion twice** on a render error (once in the `catch`, once again in the
  trailing `main.async`), and reported failure as `completion(nil, nil)` — a null reply with no error.

## Getting started

```yaml
dependencies:
  pdfx_lite:
    git:
      url: https://github.com/qeepcologne/pdfx_lite.git
```

```dart
import 'package:pdfx_lite/pdfx_lite.dart';

final controller = PdfControllerPinch(
  document: PdfDocument.openAsset('assets/hello.pdf'),
);
// ...
PdfViewPinch(controller: controller);
```

## Migrating from pdfx

1. Replace the dependency, and `package:pdfx/pdfx.dart` → `package:pdfx_lite/pdfx_lite.dart`.
2. Remove the `pdf.js` `<script>` tags from `web/index.html` — they existed only for the web renderer.
3. Guard any PDF viewing on web (`kIsWeb`) and fall back to the browser's native PDF viewer.
4. **Drop the `password:` argument** from `PdfDocument.openFile` / `openAsset` / `openData` — it no longer exists:

   ```diff
   - PdfDocument.openAsset('assets/doc.pdf', password: 'secret')
   + PdfDocument.openAsset('assets/doc.pdf')
   ```

   Upstream accepted it on all platforms but only the **web** renderer ever honoured it. On Android and iOS it was
   sent over the channel and silently ignored, so an encrypted PDF failed to open anyway (`Can't create PDF renderer`
   on Android, `Invalid PDF format` on iOS). Removing it turns a silent no-op into a compile error. If you need
   encrypted PDFs on mobile, this package cannot open them — and neither could `pdfx`.
5. **Drop `hasPdfSupport()`** — it no longer exists. It answered a question only the web renderer could fail: Android
   and iOS both render PDFs natively, so it was hardcoded `true`. Delete the check and the branch behind it.

## Upstream

Forked from [ScerIO/packages.flutter](https://github.com/ScerIO/packages.flutter) at `pdfx` 2.9.3. Bug fixes to the
shared renderer/viewer code belong upstream; this fork exists only to drop platforms and modernise the toolchain.
