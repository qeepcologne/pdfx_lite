part of 'renderer.dart';

/// A Flutter texture the native side draws a [PdfPage] into.
class PdfPageTexture {
  PdfPageTexture._({required this.id, required this.pageNumber});

  /// Texture unique id, from the platform's texture registry.
  /// Generated when the texture is created.
  final int id;

  /// Page number. The first page is 1.
  final int pageNumber;

  int? _texWidth;
  int? _texHeight;

  /// Width of the rendered area in pixels.
  int? get textureWidth => _texWidth;

  /// Height of the rendered area in pixels.
  int? get textureHeight => _texHeight;

  bool get hasUpdatedTexture => _texWidth != null;

  /// Release the object.
  Future<void> dispose() =>
      _api.unregisterTexture(UnregisterTextureMessage()..id = id);

  /// Update texture's sub-rectangle
  /// ([destinationX],[destinationY],[width],[height]) with
  /// the sub-rectangle ([sourceX],[sourceY],[width],[height]) of the PDF page
  ///  scaled to [fullWidth] x [fullHeight] size.
  /// The method can also resize the texture if you
  /// specify [textureWidth] and [textureHeight].
  /// Returns true if succeeded.
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
      other is PdfPageTexture &&
      other.id == id &&
      other.pageNumber == pageNumber;

  @override
  String toString() => '$runtimeType{'
      'id: $id, '
      'page: $pageNumber,  '
      'textureWidth: $textureWidth, '
      'textureHeight: $textureHeight}';
}
