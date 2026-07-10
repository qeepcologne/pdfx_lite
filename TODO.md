# TODO

Open issues for `pdfx_lite`, forked from `pdfx` 2.9.3 (2026-07-10). See `CHANGELOG.md` for what already changed.

## Blocking

- [ ] **Never built.** `flutter analyze` and `flutter pub get` pass, but no Gradle or Xcode run has touched this
      package. Build it against a real app (Android + iOS) before trusting anything below.
- [ ] **No tests.** All 8 upstream tests drove `PdfxPlatformMethodChannel`, which was removed (pigeon covers both
      remaining platforms). A pigeon-based suite needs `BasicMessageChannel` mocking and has not been written.

## Android

- [ ] `src/main/java/dev/flutter/pigeon/Pigeon.java` is 1479 lines of **Java**, because pigeon 4.2.14 could only emit
      Java for Android. iOS already escaped this: `Messages.swift` is a hand translation of the generated Obj-C.
      Regenerating with **pigeon 27** emits Kotlin + Swift + Dart natively and would delete `Pigeon.java`,
      `Messages.swift`, `lib/src/renderer/io/pigeon.dart` and the `src/main/java` source set. But the wire codec
      changed across nine majors, so all three sides must regenerate together and `Messages.kt`, `Document.kt`,
      `Page.kt` and `SwiftPdfxPlugin.swift` must adapt to the new generated interfaces. **Do this after a successful
      build, not before.**
- [ ] `PdfxPlugin.kt` is annotated `@TargetApi(Build.VERSION_CODES.LOLLIPOP)` — API 21, below the current `minSdk 24`.
      Dead annotation.
- [ ] `Pigeon.java` imports `androidx.annotation.NonNull` / `Nullable`, but `build.gradle.kts` declares no
      `androidx.annotation` dependency — it resolves transitively through the Flutter embedding. Latent break: declare
      it, or drop the annotations when the file is regenerated.
- [ ] `namespace` is `io.scer.pdf_renderer` while the plugin package is `io.scer.pdfx`. Left as upstream had it: the
      library ships no resources, so the namespace only names the manifest package, and renaming risks the plugin
      registrant for no gain. Revisit only if AGP starts caring.

## Repo

- [ ] Create `qeepcologne/pdfx_lite` on GitHub and push (4 local commits).
- [ ] Decide whether `pigeons/messages.dart` stays. It's the codegen input, currently excluded from analysis because
      `pigeon` is not a dev dependency. It becomes load-bearing again if the regeneration above happens.

## Won't do

- **Upstreaming.** This fork drops platforms; `ScerIO/packages.flutter` would not take it. Bug fixes to the shared
  renderer/viewer code still belong upstream.
- **Restoring `RgbaData`** or the in-memory `getPixels(bytes:)` path. Both were reachable only from the web renderer.
