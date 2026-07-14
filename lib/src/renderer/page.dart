part of 'renderer.dart';

/// Image compression format
enum PdfPageImageFormat {
  jpeg(0),
  png(1),

  /// **Android only.** [PdfPage.render] throws [UnsupportedError] for this on iOS.
  ///
  /// iOS has no first-party WebP *encoder*: `UIImage` offers only `jpegData` /
  /// `pngData`, and ImageIO's `CGImageDestination` rejects `org.webmproject.webp`
  /// (it can read WebP since iOS 14, but not write it). Producing WebP there
  /// would mean linking Google's `libwebp`.
  ///
  /// Branch on the platform rather than catching — on iOS this is a caller bug,
  /// not a runtime failure:
  ///
  /// ```dart
  /// format: Platform.isIOS ? PdfPageImageFormat.png : PdfPageImageFormat.webp,
  /// ```
  webp(2);

  const PdfPageImageFormat(this.value);
  final int value;
}

/// An integral part of a document is its page,
/// which contains a method [render] for rendering into an image
///
/// A page holds no native resource and needs no closing: [render] and
/// [PdfPageTexture.updateRect] each open the page natively, use it, and close
/// it again. Android leaves no choice — `PdfRenderer` permits only one open
/// page per document — and iOS follows the same shape so the two match.
/// The object is just the page's number and its size.
class PdfPage {
  PdfPage._({
    required this.document,
    required this.pageNumber,
    required this.width,
    required this.height,
  });

  final PdfDocument document;

  /// Page number in document.
  /// Starts from 1.
  final int pageNumber;

  /// Page source width in pixels
  final double width;

  /// Page source height in pixels
  final double height;

  /// Render a full image of specified PDF file.
  ///
  /// [width], [height] specify resolution to render in pixels.
  /// As default PNG uses transparent background. For change it you can set
  /// [backgroundColor] property like a hex string ('#FFFFFF')
  /// [format] - image type, all types can be seen here [PdfPageImageFormat]
  /// [cropRect] - render only the necessary part of the image
  /// [quality] - hint to the JPEG and WebP compression algorithms (0-100)
  /// [forPrint] - hint to the rendering quality (Android only)
  Future<PdfPageImage> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.png,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    @visibleForTesting bool removeTempFile = true,
  }) =>
      _lock.synchronized<PdfPageImage>(() async {
        if (document.isClosed) {
          throw PdfDocumentAlreadyClosedException();
        }

        return PdfPageImage._render(
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

  /// Create a new Flutter `Texture`. The object should be released by
  /// calling `dispose` method after use it.
  Future<PdfPageTexture> createTexture() async {
    final result = await _api.registerTexture();

    return PdfPageTexture._(id: result.id!, page: this);
  }

  @override
  bool operator ==(Object other) =>
      other is PdfPage &&
      other.document.hashCode == document.hashCode &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;

  @override
  String toString() => '$runtimeType{'
      'document: $document, '
      'page: $pageNumber,  '
      'width: $width, '
      'height: $height}';
}
