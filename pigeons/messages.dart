import 'package:pigeon/pigeon.dart';

/// Regenerate all three sides with:
///   dart run pigeon --input pigeons/messages.dart
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/renderer/io/pigeon.dart',
  kotlinOut: 'android/src/main/kotlin/io/scer/pdfx/Pigeon.g.kt',
  kotlinOptions: KotlinOptions(
    package: 'io.scer.pdfx',
  ),
  swiftOut: 'ios/pdfx_lite/Sources/pdfx_lite/Pigeon.g.swift',
))
/// [password] unlocks an encrypted document. iOS honours it on every version we
/// support; Android needs API 35. See `PdfxApi.isPasswordSupported`.
class OpenDataMessage {
  Uint8List? data;
  String? password;
}

class OpenPathMessage {
  String? path;
  String? password;
}

class OpenReply {
  String? id;
  int? pagesCount;
}

class IdMessage {
  String? id;
}

class GetPageMessage {
  String? documentId;
  int? pageNumber;
  bool? autoCloseAndroid;
}

class GetPageReply {
  String? id;
  double? width;
  double? height;
}

class RenderPageMessage {
  String? pageId;
  int? width;
  int? height;
  int? format;
  String? backgroundColor;
  bool? crop;
  int? cropX;
  int? cropY;
  int? cropHeight;
  int? cropWidth;
  int? quality;
  bool? forPrint;
}

/// Android and iOS both render to a temp file; the in-memory `data` field this
/// carried upstream served the web/windows renderers and is gone with them.
class RenderPageReply {
  int? width;
  int? height;
  String? path;
}

class RegisterTextureReply {
  int? id;
}

class UpdateTextureMessage {
  // For android
  String? documentId;
  int? pageNumber;
  // For ios
  String? pageId;
  int? textureId;
  int? width;
  int? height;
  String? backgroundColor;
  int? sourceX;
  int? sourceY;
  int? destinationX;
  int? destinationY;
  double? fullWidth;
  double? fullHeight;
  int? textureWidth;
  int? textureHeight;
  bool? allowAntiAliasing;
}

class ResizeTextureMessage {
  int? textureId;
  int? width;
  int? height;
}

class UnregisterTextureMessage {
  int? id;
}

@HostApi()
abstract class PdfxApi {
  /// Whether this device can open an encrypted PDF at all — always true on iOS,
  /// but only Android 15 (API 35) upwards. Passing a `password` on a device that
  /// says false fails with `PDF_PASSWORD_UNSUPPORTED` rather than being ignored.
  bool isPasswordSupported();

  @async
  OpenReply openDocumentData(OpenDataMessage message);
  @async
  OpenReply openDocumentFile(OpenPathMessage message);
  @async
  OpenReply openDocumentAsset(OpenPathMessage message);
  void closeDocument(IdMessage message);

  @async
  GetPageReply getPage(GetPageMessage message);
  @async
  RenderPageReply renderPage(RenderPageMessage message);
  void closePage(IdMessage message);

  RegisterTextureReply registerTexture();
  @async
  void updateTexture(UpdateTextureMessage message);
  @async
  void resizeTexture(ResizeTextureMessage message);
  void unregisterTexture(UnregisterTextureMessage message);
}
