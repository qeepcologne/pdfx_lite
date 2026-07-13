## 3.3.0

### Breaking

Breaking in a minor again, same reasoning as 3.2.0 — the fork has essentially one consumer.

* **Removed `PdfNotSupportException`; `PdfPage.render(format: webp)` on iOS now throws `UnsupportedError`.** It had one
  throw site: WebP on iOS. Whether that is an `Exception` or an `Error` decides the type, and it is an `Error` —
  a caller can know the answer up front from `Platform.isIOS`, with no I/O and no data dependence, so passing `webp`
  there is a precondition violation to be branched on, not a runtime failure to be caught:

  ```dart
  format: Platform.isIOS ? PdfPageImageFormat.png : PdfPageImageFormat.webp,
  ```

  `UnsupportedError` is dart:core's type for exactly this ("an instance cannot implement one of the methods in its
  signature"). Not `PlatformException`: that models an error which *crossed* the method channel, and this check runs in
  Dart and never reaches Swift — an opaque `PlatformException("Unsupported format: 2")` from the native side is what
  you get *without* the guard, and is what it exists to prevent.

* **`PdfPageImageFormat.webp` is documented as Android-only again.** The warning was lost when upstream migrated to an
  enhanced enum — the old `static const` line was commented out and took the doc comment with it, so the value
  advertised nothing in autocomplete. iOS has no first-party WebP *encoder* at all (`UIImage` does JPEG/PNG only, and
  ImageIO's `CGImageDestination` rejects `org.webmproject.webp` — it reads WebP since iOS 14 but cannot write it), so
  this is a platform gap, not something the plugin can close without linking `libwebp`.

### Fixes not in upstream

* **iOS rejected readable PDFs that carry permission restrictions.** `openFile` / `openAsset` tested
  `CGPDFDocument.isEncrypted`, but `openData` tested `isUnlocked` — and those are not the same question. A PDF
  encrypted with an *empty user password* (permissions only: no printing, no copying — very common for invoices and
  statements) is unlocked automatically by Core Graphics: `isEncrypted == true` **and** `isUnlocked == true`. So the
  same document opened fine through `openData` and failed through `openFile` / `openAsset` as "Invalid PDF format".
  All three paths now test `isUnlocked`. Android was never affected.

* **An encrypted PDF now throws `PdfPasswordProtectedException`, not "Unknown error".** On Android, `PdfRenderer`
  signals a password-protected document with `SecurityException` — a `RuntimeException`, so absent from the
  constructor's `throws` clause and easy to miss. Nothing caught it, so it fell through to the catch-all and surfaced
  as `PlatformException(code: pdf_renderer, message: "Unknown error")`, indistinguishable from any other failure.
  Both platforms now report the shared code `PDF_PASSWORD_PROTECTED`, which the Dart side turns into a typed,
  catchable exception. This is *detection*, not support — the plugin still cannot open an encrypted PDF (see
  `TODO.md` §2) — but a caller can now tell the user why instead of showing "unknown error".

  Unlike the WebP case above, this one is a true `Exception` rather than an `Error`: whether a PDF is encrypted is a
  property of the data, unknowable until it is read, so it cannot be avoided up front and catching it is correct.

## 3.2.0+1

* Docs only, no code change. Shortened the `PdfView` → `PdfViewPinch` migration step in the README; the detail it
  carried is already in 3.2.0 below.

## 3.2.0

### Breaking

Breaking, in a minor version — deliberate, while the fork still has essentially one consumer. If you use `PdfView`,
pin `pdfx_lite: 3.1.0+1` and migrate when convenient.

* **Removed `PdfView` and `PdfController`** — the image-backed viewer. Use **`PdfViewPinch` / `PdfControllerPinch`**,
  which render through a platform texture and already zoom and page. Gone with them: `PdfViewBuilders`,
  `PdfViewPageBuilder` and `PDfViewPageRenderer`. The pinch viewer's own builders (`PdfViewPinchBuilders`) are
  unchanged, as are `PdfPageNumber` and the whole `renderer` API.
* **Removed the `photo_view` dependency, and it is no longer re-exported.** `PdfView` was its only user — it wrapped
  `PhotoViewGallery` — and `photo_view` is unmaintained: last release 0.15.0 (April 2024), last commit September 2024,
  119 open issues. It had no transitive dependencies, so it was not a resolution risk, but it was a Flutter upgrade
  away from being one, with nobody upstream to fix it. If you imported `PhotoView`, `PhotoViewComputedScale` or
  `PhotoViewGalleryPageOptions` *through* `package:pdfx_lite/pdfx_lite.dart`, depend on `photo_view` directly.

  `pdfx_lite` now has no third-party runtime dependencies beyond `meta`, `synchronized` and `vector_math`.

  Rebuilding the image-backed viewer yourself is a `PageView` of `InteractiveViewer`s over `PdfPageImageProvider`,
  which is still exported — that is essentially what `photo_view` was doing.

## 3.1.0+1

* Docs only, no code change. Trimmed the README (the bug-fix list lived here and in the CHANGELOG; the CHANGELOG keeps
  it) and linked the upstream reports.

## 3.1.0

Two bugs inherited from upstream, both still present in `pdfx` 2.9.2.

* **`PdfViewPinch(scrollDirection: Axis.horizontal)` was completely broken** — it threw
  `Unsupported operation: Infinity or NaN toInt` on the first frame and rendered a blank page. The horizontal layout
  sets the document height to *exactly* the viewport height, so `documentProgress`'s
  `(docHeight - viewHeight)` divisor is always zero; the resulting `NaN` then hit `.round()`, which throws. Vertical
  scrolling hit the same thing whenever a document happened to be no taller than the viewport. Now guarded: a document
  with nothing to scroll reports progress `0.0`. Upstream has two partial patches open, neither merged:
  [#602](https://github.com/ScerIO/packages.flutter/pull/602), [#604](https://github.com/ScerIO/packages.flutter/pull/604)
  — both describe only the vertical case; the horizontal one was not reported.
* **Breaking-ish: `PdfPage.render()` now defaults to `format: png`**, not `jpeg`. The default contradicted itself —
  the implementation (`PdfPagePigeon.render`) and both native sides already defaulted to PNG, and the doc comment said
  so, but the abstract `PdfPage.render()` that callers actually bind to said JPEG. Since `backgroundColor` is derived
  from the format, a plain `render()` also silently produced a white background instead of a transparent one. If you
  relied on the JPEG default, pass `format: PdfPageImageFormat.jpeg` explicitly. `PdfView` is unaffected — it always
  passed both arguments. Upstream: [#581](https://github.com/ScerIO/packages.flutter/pull/581), unmerged.

## 3.0.0

First `pdfx_lite` release, forked from `pdfx` **2.9.2** (upstream's latest). **3.0.0**, because the public API breaks
and three platforms are gone — it is not compatible with any `pdfx` release. Versions below the line are upstream's
history, kept for reference.

### Breaking

* **Android + iOS only.** The Web (`pdf.js`), macOS and Windows renderers are gone, along with the CocoaPods podspec —
  **SPM only**. The method-channel implementation went with them; pigeon covers both remaining platforms.
* **Removed `password:`** from `PdfDocument.openFile` / `openAsset` / `openData`. Only the web renderer ever honoured
  it — on mobile it was sent over the channel and ignored, so encrypted PDFs failed to open regardless.
* **Removed `hasPdfSupport()`.** It was hardcoded `true` once web was gone.
* **Removed `RgbaData`** and the in-memory `getPixels(bytes:)` path — both were reachable only from the web renderer.
  `getPixels` now takes a required `String path`, and a null path from the native renderer throws `StateError`.
* **`PdfNotSupportException` is now exported.** It is thrown to callers (webp on iOS) but lived in an unexported file,
  so it could not be caught by type.
* **`PdfViewPinch` now uses Flutter's `InteractiveViewer`** instead of a vendored 1670-line copy, which upstream
  carried for one custom knob: making a scroll event pan rather than zoom. **Touch is unaffected** — pan, pinch, fling
  and paging go through `GestureDetector` and never produce a scroll event, and Flutter's defaults match the copy's
  hardcoded ones (same friction constant, `PanAxis.free` ≡ `alignPanAxis: false`). The one change is a **mouse wheel**,
  which now zooms instead of panning — reachable only on a device with a mouse attached (or an emulator). In exchange
  the viewer picks up ~3 years of upstream fixes; the copy predated `panAxis`, `trackpadScrollCausesScale` and
  `scaleFactor`, and still used `alignPanAxis`, which Flutter has removed. `PdfControllerPinch` now extends Flutter's
  `TransformationController`, so it can be used anywhere one is expected.

### Fixes not in upstream

None of these have an upstream issue — they were found here, and are still live in `pdfx` 2.9.2.

* **Cropped rendering on Android was broken.** `renderPage` took the crop width from the render width instead of
  `cropWidth`. Since the native code calls `Bitmap.createBitmap(bmp, cropX, cropY, cropW, cropH)`, which requires
  `cropX + cropW <= bitmap.width`, any crop with `cropX > 0` threw `IllegalArgumentException` — so `render(cropRect:)`
  failed outright unless the crop was flush to the left edge. iOS was always correct.
* **iOS `renderPage` called its completion twice** on a render error, and signalled failure as `completion(nil, nil)` —
  a null reply with no error.
* **Data race in the iOS repositories.** `DocumentRepository` / `PageRepository` were plain dictionaries written on the
  platform thread and read from the render queue, unsynchronised. `Repository` now holds an `NSLock`.
* **`renderPage` leaked a `CoroutineScope` per call on Android** and never cancelled it, so a render outliving engine
  detach kept going and replied on a dead channel. One `SupervisorJob` scope now dies with the engine.

### Native bridge

* **Regenerated with pigeon 27**: Kotlin, Swift and Dart from one schema. pigeon 4 could only emit Java and Obj-C, so
  the fork had been carrying 1479 lines of generated `Pigeon.java` plus a hand-translated `Messages.swift` that pigeon
  could no longer regenerate at all. Swift now gets native `Int64`/`Double`/`Bool` and `Result`-based completions
  instead of `NSNumber`, `as!` casts and `AutoreleasingUnsafeMutablePointer<FlutterError?>`.
* `pigeon` is a **dev** dependency, so nothing reaches consumers.

### Toolchain

* Requires Dart ^3.12 / Flutter >=3.44.
* **Android:** minSdk 24, compileSdk 37, AGP 9 (Kotlin DSL), Gradle 9.6.1, Java/Kotlin target 17, kotlinx-coroutines
  1.10.2. `namespace` is `io.scer.pdfx`. `Bitmap.CompressFormat.WEBP` (deprecated at API 30) gives way to
  `WEBP_LOSSLESS` / `WEBP_LOSSY`.
* **iOS:** Swift Package Manager support, deployment target 15.0, and **Swift 6 language mode**
  (`swift-tools-version: 6.2`, needs Xcode 26+).
* **Dependencies dropped:** `flutter_web_plugins`, `web`, `universal_platform`, `uuid`, `extension`,
  `plugin_platform_interface`. Only `meta`, `photo_view`, `synchronized` and `vector_math` remain.
* Added a runnable `example/` app (upstream's `example/main.dart` was a snippet, not a buildable project).

## 2.9.2

* Fixed PdfViewPinch when compiling to WASM [pull#586](https://github.com/ScerIO/packages.flutter/pull/586)

## 2.9.1

* Fixed Android [pull#564](https://github.com/ScerIO/packages.flutter/pull/564)
* Fixed iOS [pull#565](https://github.com/ScerIO/packages.flutter/pull/565)

## 2.9.0

* Implemented document progress feature [pull#537](https://github.com/ScerIO/packages.flutter/pull/537)
* Migrated to SurfaceProducer in PDFX [pull#543](https://github.com/ScerIO/packages.flutter/pull/543)
* Updated Messages.kt [pull#541](https://github.com/ScerIO/packages.flutter/pull/541)
* Removed device_info_plus dependency [pull#544](https://github.com/ScerIO/packages.flutter/pull/544)
* Updated iOS and macOS projects to remove warnings [pull#562](https://github.com/ScerIO/packages.flutter/pull/562)
* Updated device_info_plus version [pull#536](https://github.com/ScerIO/packages.flutter/pull/536)

## 2.8.0

* Added zoom scale customizable [pull#529](https://github.com/ScerIO/packages.flutter/pull/529)
* Fixed web [pull#533](https://github.com/ScerIO/packages.flutter/pull/533)
* Fixed avoid resetting to initialPage each view [pull#530](https://github.com/ScerIO/packages.flutter/pull/530)

## 2.7.0

* Fixed pageSnapping option [pull#435](https://github.com/ScerIO/packages.flutter/pull/435)
* Migrated to package:web [pull#493](https://github.com/ScerIO/packages.flutter/pull/493)
* Bumped device_info_plus dependency to ^10.0.1 [pull#487](https://github.com/ScerIO/packages.flutter/pull/487)
* Adjusted default zoom parameters [pull#487](https://github.com/ScerIO/packages.flutter/pull/487)
* Fixed memory leak (Web) [pull#484](https://github.com/ScerIO/packages.flutter/pull/484)
* Upgrade dependencies

## 2.6.0

* Flutter 3.16 compatibility

## 2.5.0

* Upgrade dependencies

## 2.4.0

* Upgrade dependencies
* Dart 3, Flutter 3.10 compatibility [pull#404](https://github.com/ScerIO/packages.flutter/pull/404)
* Transfer Pdf support check from viewer to renderer [pull#392](https://github.com/ScerIO/packages.flutter/pull/392)
* Added reverse option in `PdfView`  [pull#412](https://github.com/ScerIO/packages.flutter/pull/412)
* Fixup rendering issues in chromium based web-browsers [pull#402](https://github.com/ScerIO/packages.flutter/pull/402)

## 2.3.0

* Added option `forPrint` in image render [pull#301](https://github.com/ScerIO/packages.flutter/pull/301)
* Added password support (web only) [pull#354](https://github.com/ScerIO/packages.flutter/pull/354)
* Updated dependencies

## 2.2.0

* Upgrade dependency `device_info_plus` to v4
* Fixed flutter 3.0 build
* Fixed web install script 
* Fixed some bugs

## 2.1.0

* Update `[photo_view]` dependency to 0.14.0 [pull#306](https://github.com/ScerIO/packages.flutter/pull/306)
* Fixed render crop [pull#305](https://github.com/ScerIO/packages.flutter/pull/305)

## 2.0.1+2

* Fixed broken links at pub.dev
* Fixed readme
* Update pdfjs version in installation script

## 2.0.1+1

* Update readme
## 2.0.1

* Fixed android launch

## 2.0.0

* Provide more docs
* Fixed windows support 
* Added `builders` argument for `PdfViewPinch` & `PdfView`. Example: 
```dart
PdfViewPinch(
  builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
    options: const DefaultBuilderOptions(
      loaderSwitchDuration: const Duration(seconds: 1),
      transitionBuilder: SomeWidget.transitionBuilder,
    ),
    documentLoaderBuilder: (_) =>
        const Center(child: CircularProgressIndicator()),
    pageLoaderBuilder: (_) =>
        const Center(child: CircularProgressIndicator()),
    errorBuilder: (_, error) => Center(child: Text(error.toString())),
    builder: SomeWidget.builder,
  ),
)
```
* Added  widget `PdfPageNumber` for show actual page number & all pages count. Example:
```dart
PdfPageNumber(
  controller: _pdfController,
  // When `loadingState != PdfLoadingState.success`  `pagesCount` equals null_
  builder: (_, state, loadingState, pagesCount) => Container(
    alignment: Alignment.center,
    child: Text(
      '$page/${pagesCount ?? 0}',
      style: const TextStyle(fontSize: 22),
    ),
  ),
)
```
* Added listenable page number `pageListenable` in `PdfController` & `PdfControllerPinch`. Example:
```dart
ValueListenableBuilder<int>(
  valueListenable: controller.pageListenable,
  builder: (context, actualPageNumber, child) => Text(actualPageNumber.toString()),
)
```
* Added listenable loading state `loadingState` in `PdfController` & `PdfControllerPinch`. Example:
```dart
ValueListenableBuilder<PdfLoadingState>(
  valueListenable: controller.loadingState,
  builder: (context, loadingState, loadingState) => (){
    switch (loadingState) {
      case PdfLoadingState.loading:
        return const CircularProgressIndicator();
      case PdfLoadingState.error:
        return  const Text('Pdf load error');
      case PdfLoadingState.success:
        return const Text('Pdf loaded');
    }
  }(),
)
```
* Removed `documentLoader`, `pageLoader`, `errorBuilder`m `loaderSwitchDuration` arguments from `PdfViewPinch` & `PdfView`
* Removed `pageSnapping`, `physics` arguments from `PdfViewPinch`
* Rename `PdfControllerPinch` page control methods like a `PdfController` control names

## 1.0.1+1

* Updated readme

## 1.0.1

* Fixed platforms plugin 

## 1.0.0

* Initial release 

