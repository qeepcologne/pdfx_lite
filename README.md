# pdfx_lite

Standalone PDF renderer & viewer for Flutter on **Android and iOS** — a replacement for [`pdfx`](https://github.com/ScerIO/packages.flutter/tree/main/packages/pdfx), with the Web, macOS and Windows renderers removed.

**Purpose:** minimal and legacy-free, for **current toolchains only** — no CocoaPods (SPM only), no `pdf.js`, no CMake, and built against the latest Flutter, AGP, Gradle, Android SDK and Xcode rather than older ones. If you need Web, desktop, or CocoaPods, use the upstream package instead.

Includes 2 APIs, unchanged from upstream:
- `renderer` — work with a PDF document, its pages, render a page to an image
- `viewer` — Flutter widgets & controllers to show the render result

## What changed vs upstream

| | pdfx | pdfx_lite |
|---|---|---|
| Platforms | Android, iOS, macOS, Windows, Web | Android, iOS |
| iOS integration | CocoaPods podspec + SPM | **SPM only** |
| Web renderer | `pdf.js` (needs CDN scripts in `index.html`) | **removed** |
| Desktop | macOS (podspec), Windows (CMake) | **removed** |
| Platform channel | pigeon (mobile) + method channel (web/Windows) | **pigeon only** |
| Dart / Flutter | >=3.3 / >=3.24 | ^3.12 / >=3.44 |
| **Android** | | |
| minSdk / compileSdk | 16 / 35 | **24 / 37** |
| Gradle | 8.10.2 | **9.6.1** |
| AGP | 8 or 9 (compat guard) | **9 only** (built-in Kotlin) |
| **iOS** | | |
| Deployment target | 13.0 | **15.0** |
| **Dart** | | |
| Dependencies | + `flutter_web_plugins`, `web`, `universal_platform`, `uuid`, `extension` | those five dropped |
| `vector_math` | deprecated `translate` / `scale` | `translateByDouble` / `scaleByDouble` |
| Tests | 8 (method-channel) | **none** — the implementation they covered is gone |

Everything else — the public API, the pinch/simple viewers, the Android and iOS native renderers — is upstream's.

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

`hasPdfSupport()` always returns `true`: both supported platforms render PDFs natively.

## Migrating from pdfx

1. Replace the dependency, and `package:pdfx/pdfx.dart` → `package:pdfx_lite/pdfx_lite.dart`.
2. Remove the `pdf.js` `<script>` tags from `web/index.html` — they existed only for the web renderer.
3. Guard any PDF viewing on web (`kIsWeb`) and fall back to the browser's native PDF viewer.

## Upstream

Forked from [ScerIO/packages.flutter](https://github.com/ScerIO/packages.flutter) at `pdfx` 2.9.3. Bug fixes to the
shared renderer/viewer code belong upstream; this fork exists only to drop platforms and modernise the toolchain.
