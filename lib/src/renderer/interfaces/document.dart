import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:pdfx_lite/src/renderer/interfaces/platform.dart';

import 'page.dart';

/// PDF page image renderer
abstract class PdfDocument {
  PdfDocument({
    required this.sourceName,
    required this.id,
    required this.pagesCount,
  });

  /// Needed for toString method
  /// Contains a method for opening a document (file, data or asset)
  final String sourceName;

  /// Document unique id.
  /// Generated when opening document.
  final String id;

  /// All pages count in document.
  /// Starts from 1.
  final int pagesCount;

  /// Is the document closed
  bool isClosed = false;

  Future<void> close();

  /// Whether this device can open encrypted PDFs at all.
  ///
  /// Always true on iOS. On Android it is true only from **API 35** (Android
  /// 15) — see [PdfPasswordUnsupportedException]. Ask this *before* prompting
  /// the user for a password, so you do not collect one that cannot be used.
  static Future<bool> isPasswordSupported() =>
      PdfxPlatform.instance.isPasswordSupported();

  /// Opening the specified file.
  ///
  /// [password] unlocks an encrypted document. Throws
  /// [PdfPasswordProtectedException] if the document needs a password and none
  /// was given or the given one is wrong, and
  /// [PdfPasswordUnsupportedException] if [password] is non-null on a device
  /// that cannot use one ([isPasswordSupported]).
  static Future<PdfDocument> openFile(String filePath, {String? password}) =>
      PdfxPlatform.instance.openFile(filePath, password: password);

  /// Opening the specified asset.
  ///
  /// See [openFile] for [password] and the exceptions it can throw.
  static Future<PdfDocument> openAsset(String name, {String? password}) =>
      PdfxPlatform.instance.openAsset(name, password: password);

  /// Opening the PDF on memory.
  ///
  /// See [openFile] for [password] and the exceptions it can throw.
  static Future<PdfDocument> openData(
    FutureOr<Uint8List> data, {
    String? password,
  }) =>
      PdfxPlatform.instance.openData(data, password: password);

  /// Get page object. The first page is 1.
  ///
  /// The returned [PdfPage] holds no native resource and needs no closing — it
  /// carries the page's size, and every later call re-opens the page by number.
  Future<PdfPage> getPage(int pageNumber);

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;

  @override
  String toString() =>
      '$runtimeType{document: $sourceName, id: $id, pagesCount: $pagesCount}';
}

class PdfDocumentAlreadyClosedException implements Exception {
  @override
  String toString() => '$runtimeType: Document already closed';
}

/// The document is encrypted, and the `password` given was absent or wrong.
///
/// Unlike [UnsupportedError] from `render(format: webp)` on iOS, this is a genuine `Exception`: whether a given PDF is
/// encrypted is a property of the *data*, unknowable until it is read, so a caller cannot avoid it up front and
/// catching it is the correct response. Re-prompt for the password and open again.
///
/// **"No password" and "wrong password" are not distinguished.** Android's `PdfRenderer` reports both as a single
/// `SecurityException`, so the platform genuinely cannot tell them apart, and iOS is made to match rather than
/// promising something only one platform can honour.
///
/// Only PDFs with a real user password throw. The common case of a PDF encrypted for *permissions* (no printing or
/// copying) with an empty user password opens normally, with no password needed.
class PdfPasswordProtectedException implements Exception {
  PdfPasswordProtectedException(this.sourceName);

  /// Which document — e.g. `file:/path/to.pdf`, `asset:doc.pdf`, `memory:binary`.
  final String sourceName;

  @override
  String toString() => '$runtimeType: $sourceName is password-protected';
}

/// The document is encrypted and a `password` was supplied, but this device cannot use one — see
/// [PdfDocument.isPasswordSupported].
///
/// Only Android throws this, and only below **API 35** (Android 15), which is where `PdfRenderer` first accepted a
/// password. iOS never throws it. Given `minSdk` is 24, expect it on a large share of Android devices in the field.
///
/// It is thrown only when the password was actually *needed*: `password` is a fallback, tried only once the document
/// has refused to open without one. Passing a password to a document that does not need it is harmless on every
/// platform and API level.
///
/// The plugin refuses rather than quietly dropping the password. Ignoring it would leave the file on the
/// password-less code path, which rejects *any* encrypted PDF — so supplying the **correct** password on Android 14
/// would come back as [PdfPasswordProtectedException], indistinguishable from getting it wrong, and a caller would
/// re-prompt forever. A silently-ignored `password` is precisely the bug that had the parameter removed in 3.0.0.
///
/// It is an `Exception`, not an `Error`, because it depends on the device rather than on the code: a caller cannot
/// rule it out at compile time the way `Platform.isIOS` rules out WebP. Either catch it, or call
/// [PdfDocument.isPasswordSupported] up front and offer a fallback (an external viewer, say) instead of a password
/// prompt that cannot lead anywhere.
class PdfPasswordUnsupportedException implements Exception {
  PdfPasswordUnsupportedException(this.sourceName);

  /// Which document — e.g. `file:/path/to.pdf`, `asset:doc.pdf`, `memory:binary`.
  final String sourceName;

  @override
  String toString() =>
      '$runtimeType: this device cannot open password-protected PDFs '
      '(Android 15 / API 35 and up only); $sourceName was not opened';
}
