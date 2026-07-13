# pdfx_lite

Standalone PDF renderer & viewer for Flutter on **Android and iOS** — a replacement for [`pdfx`](https://github.com/ScerIO/packages.flutter/tree/main/packages/pdfx), forked from [ScerIO/packages.flutter](https://github.com/ScerIO/packages.flutter) at `pdfx` 2.9.2, with the Web, macOS and Windows renderers removed.

**Purpose:** minimal and legacy-free, for **current toolchains only** — no CocoaPods (SPM only), no `pdf.js`, no CMake, and built against the latest Flutter, AGP, Gradle, Android SDK and Xcode rather than older ones. If you need Web, desktop, or CocoaPods, use the upstream package instead. Fixes to the shared renderer/viewer code belong upstream, not here.

> **No tests.** The 8 upstream ones drove the method-channel implementation, which is gone.

Includes the same 2 APIs as upstream:
- `renderer` — work with a PDF document, its pages, render a page to an image. Slightly reduced: `password`,
  `hasPdfSupport()` and `RgbaData` are gone (see *Migrating from pdfx*).
- `viewer` — Flutter widgets & controllers to show the render result. Unchanged.

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

### Bug fixes not in upstream

All still present in `pdfx` 2.9.2:

- **Cropped rendering on Android.** `render(cropRect: …)` did not just return the wrong region — it **threw** for any
  crop not flush to the left edge, because the crop width was read from the wrong field. iOS was always correct.
- **iOS `renderPage` called its completion twice** on a render error, and signalled failure as a null reply with no error.
- An unsynchronised **data race** in the iOS document/page repositories, and a **`CoroutineScope` leaked per render**
  on Android.

Details in the [CHANGELOG](CHANGELOG.md).

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
2. **Web:** drop the `pdf.js` `<script>` tags from `web/index.html`, and guard any PDF viewing behind `kIsWeb`,
   falling back to the browser's native viewer.
3. **Drop `password:`** from `PdfDocument.openFile` / `openAsset` / `openData`, and **drop `hasPdfSupport()`** — both
   are gone. Only the web renderer ever honoured a password (on mobile it was silently ignored, so encrypted PDFs
   failed to open anyway), and `hasPdfSupport()` was hardcoded `true`.
