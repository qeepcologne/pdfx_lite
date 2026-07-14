# pdfx_lite

Standalone PDF renderer & viewer for Flutter on **Android and iOS** — a replacement for [`pdfx`](https://github.com/ScerIO/packages.flutter/tree/main/packages/pdfx), forked from [ScerIO/packages.flutter](https://github.com/ScerIO/packages.flutter) at `pdfx` 2.9.2, with the Web, macOS and Windows renderers removed.

**Purpose:** minimal and legacy-free, for **current toolchains only** — no CocoaPods (SPM only), no `pdf.js`, no CMake, and built against the latest Flutter, AGP, Gradle, Android SDK and Xcode rather than older ones. If you need Web, desktop, or CocoaPods, use the upstream package instead.

Same 2 APIs as upstream, both slightly reduced (see *Migrating from pdfx*):
- `renderer` — work with a PDF document, its pages, render a page to an image
- `viewer` — `PdfViewPinch`, the texture-backed viewer with pinch-to-zoom. Upstream's second, image-backed `PdfView`
  is gone, and with it the `photo_view` dependency.

## Getting started

```yaml
dependencies:
  pdfx_lite: ^3.6.0
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
3. **Drop `hasPdfSupport()`** — it was hardcoded `true`.
4. **`PdfView` → `PdfViewPinch`** (and `PdfController` → `PdfControllerPinch`). The image-backed viewer is gone with
   the unmaintained `photo_view` it wrapped. To rebuild it: `PdfPageImageProvider` is still exported.
5. **Drop `page.close()` and `getPage(autoCloseAndroid:)`** — a `PdfPage` holds no native resource. Only the document
   is closed.

## Encrypted PDFs

```dart
final doc = await PdfDocument.openFile(path, password: 'secret');
```

`password:` is a **fallback**, used only if the document demands one — passing it to a document that opens without one
is harmless. (A permissions-only PDF, restricted but with an empty user password, needs none.)

| | |
|---|---|
| iOS | supported on every version |
| Android 15+ (API 35) | supported |
| Android below API 35 | **not supported** |

`PdfDocument.isPasswordSupported()` reports that up front, so you can skip a prompt the device cannot honour.
Otherwise catch:

- **`PdfPasswordProtectedException`** — needs a password, and none was given or the given one is wrong. The two are
  not distinguished; the platform cannot tell them apart. Re-prompt.
- **`PdfPasswordUnsupportedException`** — encrypted, and this Android device cannot take a password at all. Never a
  wrong password. Fall back, e.g. to an external viewer.

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
| Viewers | `PdfView` (image, via `photo_view`) + `PdfViewPinch` (texture) | **`PdfViewPinch` only** — `photo_view` is unmaintained |
| Dependencies | + `photo_view`, `flutter_web_plugins`, `web`, `universal_platform`, `uuid`, `extension`, `plugin_platform_interface` | those seven dropped — only `meta`, `synchronized`, `vector_math` remain |
| Encrypted PDFs | `password:` accepted, then **silently ignored** | **honoured** on iOS and Android 15+ |

Plus bug fixes `pdfx` 2.9.2 still has — a crash in `PdfViewPinch`, broken cropping on Android, an iOS data race, and
more. See the [CHANGELOG](CHANGELOG.md).
