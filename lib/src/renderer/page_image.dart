part of 'renderer.dart';

/// Object containing a rendered image of [PdfPage]
class PdfPageImage {
  const PdfPageImage._({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.bytes,
    required this.format,
    required this.quality,
  });

  /// Page number. The first page is 1.
  final int pageNumber;

  /// Width of the rendered area in pixels.
  final int? width;

  /// Height of the rendered area in pixels.
  final int? height;

  /// Image bytes
  final Uint8List bytes;

  /// Target compression format
  final PdfPageImageFormat format;

  /// Target compression format quality
  final int quality;

  /// Render a full image of specified PDF file.
  ///
  /// [width], [height] specify resolution to render in pixels.
  /// As default PNG uses transparent background. For change it you can set
  /// [backgroundColor] property like a hex string ('#000000')
  /// [format] - image type, all types can be seen here [PdfPageImageFormat]
  /// [crop] - render only the necessary part of the image
  /// [quality] - hint to the JPEG and WebP compression algorithms (0-100)
  static Future<PdfPageImage?> _render({
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

    return PdfPageImage._(
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
      other is PdfPageImage &&
      other.bytes.lengthInBytes == bytes.lengthInBytes;

  @override
  int get hashCode => Object.hash(pageNumber, bytes.lengthInBytes);

  @override
  String toString() => '$runtimeType{'
      'page: $pageNumber,  '
      'width: $width, '
      'height: $height, '
      'bytesLength: ${bytes.lengthInBytes}}';
}
