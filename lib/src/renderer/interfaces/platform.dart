import 'dart:async';
import 'dart:typed_data';

import 'package:pdfx_lite/src/renderer/interfaces/document.dart';
import 'package:pdfx_lite/src/renderer/io/platform_pigeon.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Abstraction layer to isolate [PdfDocument] implementation
/// from the public interface.
abstract class PdfxPlatform extends PlatformInterface {
  /// Constructs a PdfxPlatform.
  PdfxPlatform() : super(token: _token);

  static final Object _token = Object();

  //Android and iOS both speak pigeon; the method-channel implementation existed only for Windows/web.
  static PdfxPlatform _instance = PdfxPlatformPigeon();

  /// The default instance of [PdfxPlatform] to use.
  ///
  /// Defaults to [PdfxPlatformPigeon].
  static PdfxPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [PdfxPlatform] when they register themselves.
  static set instance(PdfxPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<PdfDocument> openFile(String filePath, {String? password});

  Future<PdfDocument> openAsset(String name, {String? password});

  Future<PdfDocument> openData(FutureOr<Uint8List> data, {String? password});
}

class PdfNotSupportException implements Exception {
  PdfNotSupportException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}
