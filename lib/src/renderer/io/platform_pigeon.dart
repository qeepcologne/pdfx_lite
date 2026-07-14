import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:meta/meta.dart';
import 'package:pdfx_lite/src/renderer/get_pixels.dart';
import 'package:pdfx_lite/src/renderer/interfaces/document.dart';
import 'package:pdfx_lite/src/renderer/interfaces/page.dart';
import 'package:pdfx_lite/src/renderer/interfaces/platform.dart';
import 'package:pdfx_lite/src/renderer/io/pigeon.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:io';

/// Serializes a document's use against its close.
///
/// Not for the native side's benefit — both platforms guard their own state. It closes the gap in
/// `if (isClosed) throw; await _api.something()`: the check and the call sit either side of an `await`, so without
/// this a `close()` can land between them and the native call arrives at a document that is already gone.
final _lock = Lock();
final _api = PdfxApi();

/// Error codes both native sides use for an encrypted PDF. Kept in sync by hand with `Messages.kt` and
/// `SwiftPdfxPlugin.swift` — pigeon generates the message types, not the error codes.
const _passwordProtectedCode = 'PDF_PASSWORD_PROTECTED';
const _passwordUnsupportedCode = 'PDF_PASSWORD_UNSUPPORTED';

class PdfxPlatformPigeon extends PdfxPlatform {
  @override
  Future<bool> isPasswordSupported() => _api.isPasswordSupported();

  /// Awaits an open, mapping the native password codes to typed exceptions. Every other failure stays a
  /// [PlatformException] — this only rescues the cases a caller can act on.
  Future<PdfDocument> _open(
    Future<OpenReply> reply,
    String sourceName,
  ) async {
    final OpenReply result;
    try {
      result = await reply;
    } on PlatformException catch (e) {
      switch (e.code) {
        case _passwordProtectedCode:
          throw PdfPasswordProtectedException(sourceName);
        case _passwordUnsupportedCode:
          throw PdfPasswordUnsupportedException(sourceName);
      }
      rethrow;
    }
    return PdfDocumentPigeon._(
      sourceName: sourceName,
      id: result.id!,
      pagesCount: result.pagesCount!,
    );
  }

  /// Open PDF document from filesystem path
  ///
  /// Throws [PdfPasswordProtectedException] if the document needs a password and [password] is absent or wrong, and
  /// [PdfPasswordUnsupportedException] if [password] is given on a device that cannot use one.
  @override
  Future<PdfDocument> openFile(String filePath, {String? password}) => _open(
        _api.openDocumentFile(OpenPathMessage()
          ..path = filePath
          ..password = password),
        'file:$filePath',
      );

  /// Open PDF document from application assets
  ///
  /// See [openFile] for the exceptions [password] can raise.
  @override
  Future<PdfDocument> openAsset(String name, {String? password}) => _open(
        _api.openDocumentAsset(OpenPathMessage()
          ..path = name
          ..password = password),
        'asset:$name',
      );

  /// Open PDF file from memory (Uint8List)
  ///
  /// See [openFile] for the exceptions [password] can raise.
  @override
  Future<PdfDocument> openData(
    FutureOr<Uint8List> data, {
    String? password,
  }) async =>
      _open(
        _api.openDocumentData(OpenDataMessage()
          ..data = await data
          ..password = password),
        'memory:binary',
      );
}

/// Handles PDF document loaded on memory.
class PdfDocumentPigeon extends PdfDocument {
  PdfDocumentPigeon._({
    required super.sourceName,
    required super.id,
    required super.pagesCount,
  });

  @override
  Future<void> close() => _lock.synchronized(() async {
        if (isClosed) {
          throw PdfDocumentAlreadyClosedException();
        } else {
          isClosed = true;
        }
        return _api.closeDocument(IdMessage()..id = id);
      });

  /// Get page object. The first page is 1.
  @override
  Future<PdfPage> getPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > pagesCount) {
      throw RangeError.range(pageNumber, 1, pagesCount);
    }
    return _lock.synchronized<PdfPage>(() async {
      if (isClosed) {
        throw PdfDocumentAlreadyClosedException();
      }
      final result = await _api.getPage(
        GetPageMessage()
          ..documentId = id
          ..pageNumber = pageNumber,
      );

      return PdfPagePigeon(
        document: this,
        pageNumber: pageNumber,
        width: result.width!,
        height: result.height!,
      );
    });
  }

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentPigeon && other.id == id;

  @override
  int get hashCode => identityHashCode(id);
}

class PdfPagePigeon extends PdfPage {
  PdfPagePigeon({
    required super.document,
    required super.pageNumber,
    required super.width,
    required super.height,
  });

  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.png,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    @visibleForTesting bool removeTempFile = true,
  }) =>
      _lock.synchronized<PdfPageImage?>(() async {
        if (document.isClosed) {
          throw PdfDocumentAlreadyClosedException();
        }

        return PdfPageImagePigeon.render(
          documentId: document.id,
          pageNumber: pageNumber,
          width: width,
          height: height,
          format: format,
          backgroundColor: backgroundColor,
          crop: cropRect,
          quality: quality,
          forPrint: forPrint,
          removeTempFile: removeTempFile,
        );
      });

  @override
  Future<PdfPageTexture> createTexture() async {
    final result = await _api.registerTexture();

    return PdfPageTexturePigeon(
      id: result.id!,
      pageNumber: pageNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfPagePigeon &&
      other.document.hashCode == document.hashCode &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;
}

class PdfPageImagePigeon extends PdfPageImage {
  PdfPageImagePigeon({
    required super.pageNumber,
    required super.width,
    required super.height,
    required super.bytes,
    required super.format,
    required super.quality,
  });

  /// Render a full image of specified PDF file.
  ///
  /// [width], [height] specify resolution to render in pixels.
  /// As default PNG uses transparent background. For change it you can set
  /// [backgroundColor] property like a hex string ('#000000')
  /// [format] - image type, all types can be seen here [PdfPageImageFormat]
  /// [crop] - render only the necessary part of the image
  /// [quality] - hint to the JPEG and WebP compression algorithms (0-100)
  static Future<PdfPageImage?> render({
    required String documentId,
    required int pageNumber,
    required double width,
    required double height,
    required PdfPageImageFormat format,
    required String? backgroundColor,
    required Rect? crop,
    required int quality,
    required bool forPrint,
    required bool removeTempFile,
  }) async {
    //A caller bug, not a runtime failure: iOS has no WebP encoder at all, so this is knowable up front from
    //`Platform.isIOS` and should be branched on, not caught. Hence `UnsupportedError` (an `Error`) rather than an
    //exception. Without this guard the native side still refuses -- `CompressFormat(rawValue: 2)` is nil -- but it
    //surfaces as an opaque PlatformException("Unsupported format: 2").
    if (format == PdfPageImageFormat.webp && Platform.isIOS) {
      throw UnsupportedError(
        'PdfPageImageFormat.webp is not supported on iOS: the platform has no '
        'WebP encoder. Use PdfPageImageFormat.png or .jpeg instead.',
      );
    }

    backgroundColor ??=
        (format == PdfPageImageFormat.jpeg) ? '#FFFFFF' : '#00FFFFFF';

    final result = await _api.renderPage(RenderPageMessage()
      ..documentId = documentId
      ..pageNumber = pageNumber
      ..width = width.toInt()
      ..height = height.toInt()
      ..format = format.value
      ..backgroundColor = backgroundColor
      ..crop = crop != null
      ..cropX = crop?.left.toInt()
      ..cropY = crop?.top.toInt()
      ..cropWidth = crop?.width.toInt()
      ..cropHeight = crop?.height.toInt()
      ..quality = quality
      ..forPrint = forPrint);

    final retWidth = result.width, retHeight = result.height;
    //android + ios both render to a temp file; the in-memory `result.data` path served windows/web
    final path = result.path;
    if (path == null) {
      throw StateError('pdfx_lite: native renderer returned no file path');
    }
    final Uint8List pixels = await getPixels(
      path: path,
      removeTempFile: removeTempFile,
    );

    return PdfPageImagePigeon(
      pageNumber: pageNumber,
      width: retWidth,
      height: retHeight,
      bytes: pixels,
      format: format,
      quality: quality,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfPageImagePigeon &&
      other.bytes.lengthInBytes == bytes.lengthInBytes;

  @override
  int get hashCode => Object.hash(pageNumber, bytes.lengthInBytes);
}

class PdfPageTexturePigeon extends PdfPageTexture {
  PdfPageTexturePigeon({
    required super.id,
    required super.pageNumber,
  });

  int? _texWidth;
  int? _texHeight;

  @override
  int? get textureWidth => _texWidth;

  @override
  int? get textureHeight => _texHeight;

  @override
  bool get hasUpdatedTexture => _texWidth != null;

  @override
  Future<void> dispose() =>
      _api.unregisterTexture(UnregisterTextureMessage()..id = id);

  @override
  Future<bool> updateRect({
    required String documentId,
    int destinationX = 0,
    int destinationY = 0,
    int? width,
    int? height,
    int sourceX = 0,
    int sourceY = 0,
    int? textureWidth,
    int? textureHeight,
    double? fullWidth,
    double? fullHeight,
    String? backgroundColor,
    bool allowAntiAliasing = true,
  }) async {
    try {
      final params = UpdateTextureMessage()
        ..documentId = documentId
        ..pageNumber = pageNumber
        ..textureId = id
        ..destinationX = destinationX
        ..destinationY = destinationY
        ..width = width
        ..height = height
        ..sourceX = sourceX
        ..sourceY = sourceY
        ..textureWidth = textureWidth
        ..textureHeight = textureHeight
        ..fullWidth = fullWidth
        ..fullHeight = fullHeight
        ..backgroundColor = backgroundColor
        ..allowAntiAliasing = allowAntiAliasing;
      await _api.updateTexture(params);
      _texWidth = textureWidth ?? _texWidth;
      _texHeight = textureHeight ?? _texHeight;
      return true;
    } catch (error) {
      return false;
    }
  }

  @override
  int get hashCode => Object.hash(id, pageNumber);

  @override
  bool operator ==(Object other) =>
      other is PdfPageTexturePigeon &&
      other.id == id &&
      other.pageNumber == pageNumber;
}
