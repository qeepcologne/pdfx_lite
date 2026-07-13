## 2.9.3 (pdfx_lite fork)

* **Regenerated the pigeon bridge with pigeon 27.** pigeon 4.2.14 could only emit Java (Android) and Obj-C (iOS), so
  the fork carried 1479 lines of generated `Pigeon.java` plus a hand-written `Messages.swift` — a manual translation
  of the Obj-C output that pigeon could no longer regenerate. Pigeon 27 emits Kotlin, Swift and Dart natively from the
  same `pigeons/messages.dart`, so all three sides are generated again from one schema:
  - Deleted `android/src/main/java/` (the whole Java source set) and `ios/.../Messages.swift`; added the generated
    `Pigeon.g.kt` and `Pigeon.g.swift`.
  - `SwiftPdfxPlugin.swift` now sees native `Int64`/`Double`/`Bool` and `Result`-based completions instead of
    `NSNumber`, `as! Int` force-casts and `AutoreleasingUnsafeMutablePointer<FlutterError?>`.
  - `Messages.kt` implements the generated Kotlin `PdfxApi`; the hand-rolled `PdfRendererException` is gone in favour
    of pigeon's `FlutterError`, which carries the same code/message/details to Dart.
  - The message schema is unchanged, so no Dart call site moved. The wire codec did change, but all three sides are
    generated and ship together.
  - `pigeon: ^27.1.1` is a **dev** dependency — dev deps are not resolved transitively, so nothing reaches consumers.
    The old analyzer conflict is gone: pigeon 4 pinned `analyzer` 4.x and Dart `<3.0.0`; pigeon 27 wants
    `analyzer >=10 <13`, which resolves against our `sdk: ^3.12.0`.
* **Fixed cropped rendering on Android** (upstream bug, still present in `pdfx`). `Messages.kt` `renderPage` took the
  crop width from `message.width` instead of `message.cropWidth`, so the crop always spanned the full render width.
  Worse, `Page.render` then calls `Bitmap.createBitmap(bmp, cropX, cropY, cropW, cropH)`, which requires
  `cropX + cropW <= bitmap.width` — so any crop with `cropX > 0` threw `IllegalArgumentException: x + width must be
  <= bitmap.width()`, surfacing in Dart as `PlatformException(pdf_renderer, Unexpected error, ...)`. iOS was always
  correct. Verified on device: `render(cropRect: Rect.fromLTWH(150, 0, 150, 200))` on a 300x400 page now returns a
  150x200 image of the correct region, where it previously threw.
* Added a real `example/` host app (the old `example/main.dart` was a snippet, not a buildable project) with a 2-page
  `assets/hello.pdf`, so the plugin can actually be built and driven on a device.
* Android: pinned `compileOptions` and the Kotlin `jvmTarget` to 17. Neither was declared, so javac defaulted to 11
  while Kotlin followed the JDK toolchain, and AGP 9 fails the build on the mismatch.
* Forked from pdfx 2.9.3 as `pdfx_lite`: Android + iOS only.
* Removed the Web (`pdf.js`), macOS and Windows renderers, and the CocoaPods podspec — SPM only.
* Removed the method-channel platform implementation; pigeon covers both remaining platforms.
* Dropped `flutter_web_plugins`, `web` and `universal_platform` dependencies.
* Migrated deprecated `vector_math` `translate`/`scale` to `translateByDouble`/`scaleByDouble`.
* Dropped unused `uuid` and `extension` dependencies (they served the web renderer only).
* Dropped the `pigeon` dev dependency — v4 pins `analyzer` 4.x; the generated files are checked in and the message API
  is frozen. Add it back temporarily to regenerate from `pigeons/messages.dart`.
* Bumped `flutter_lints` to 6; `synchronized` to ^3.4.1.
* Android: minSdk 16 → 24, compileSdk 35 → 37, Gradle 8.10.2 → 9.6.1, kotlinx-coroutines 1.8.1 → 1.10.2.
  Dropped the `agpVersion < 9` compat guard (AGP 9's built-in Kotlin), the `sourceSets`/`compileOptions` blocks, and
  `gradle.properties` (`enableJetifier` is gone in AGP 9, `useAndroidX` is the default).
* Android: dropped the `@TargetApi`/`@RequiresApi(LOLLIPOP)` annotations (and their now-unused `android.os.Build`
  imports) from all six Kotlin sources. They gated on API 21, below the current `minSdk 24`.
* iOS: deployment target 13.0 → 15.0. Stripped every `#if os(iOS)` / `#elseif os(macOS)` block from the Swift sources
  (incl. the whole `NSColor` extension) — the SPM package is iOS-only, so the macOS branches were unreachable.
* **Breaking:** removed the exported `RgbaData` type. Nothing produced or consumed it once the web texture renderer
  was gone.
* `getPixels`/`getPlatformPixels` now take a required `String path`; the optional in-memory `bytes` fallback had no
  caller left. A null path from the native renderer throws `StateError` instead of being silently tolerated.
* **Removed the test suite.** All 8 tests drove `PdfxPlatformMethodChannel`, which no longer exists. A pigeon-based
  suite has not been written — the fork currently ships with no tests.
* Requires Dart ^3.12 / Flutter >=3.44.

## 2.9.3

* Added Swift Package Manager support for iOS.

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

