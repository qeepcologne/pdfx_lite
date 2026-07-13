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

  /// Opening the specified file.
  ///
  /// Encrypted documents are not supported: upstream's `password` parameter
  /// was only ever honoured by the web renderer, so it is gone.
  static Future<PdfDocument> openFile(String filePath) =>
      PdfxPlatform.instance.openFile(filePath);

  /// Opening the specified asset.
  static Future<PdfDocument> openAsset(String name) =>
      PdfxPlatform.instance.openAsset(name);

  /// Opening the PDF on memory.
  static Future<PdfDocument> openData(FutureOr<Uint8List> data) =>
      PdfxPlatform.instance.openData(data);

  /// Get page object. The first page is 1.
  Future<PdfPage> getPage(
    int pageNumber, {
    bool autoCloseAndroid = false,
  });

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

/// The document is encrypted and needs a password, which [PdfDocument] cannot supply.
///
/// Unlike [UnsupportedError] from `render(format: webp)` on iOS, this is a genuine `Exception`: whether a given PDF is
/// encrypted is a property of the *data*, unknowable until it is read, so a caller cannot avoid it up front and
/// catching it is the correct response.
///
/// Both platforms detect this, but neither can open the document: Android's `PdfRenderer` takes a password only from
/// API 35 (with SDK extension 13), and the plugin exposes no `password:` argument. So the useful thing a caller can do
/// is *report* it — telling the user their PDF is password-protected beats "unknown error".
///
/// Only PDFs with a real user password throw. The common case of a PDF encrypted for *permissions* (no printing or
/// copying) with an empty user password opens normally.
class PdfPasswordProtectedException implements Exception {
  PdfPasswordProtectedException(this.sourceName);

  /// Which document — e.g. `file:/path/to.pdf`, `asset:doc.pdf`, `memory:binary`.
  final String sourceName;

  @override
  String toString() => '$runtimeType: $sourceName is password-protected';
}
