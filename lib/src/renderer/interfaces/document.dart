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
  /// [password] is accepted for source compatibility with `pdfx` but is
  /// ignored: it was only ever honoured by the web renderer. Encrypted
  /// documents fail to open on Android and iOS.
  static Future<PdfDocument> openFile(String filePath, {String? password}) =>
      PdfxPlatform.instance.openFile(filePath, password: password);

  /// Opening the specified asset.
  ///
  /// [password] is ignored — see [openFile].
  static Future<PdfDocument> openAsset(String name, {String? password}) =>
      PdfxPlatform.instance.openAsset(name, password: password);

  /// Opening the PDF on memory.
  ///
  /// [password] is ignored — see [openFile].
  static Future<PdfDocument> openData(FutureOr<Uint8List> data,
          {String? password}) =>
      PdfxPlatform.instance.openData(data, password: password);

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
