import 'dart:async';
import 'dart:typed_data';

import 'package:pdfx_lite/src/renderer/interfaces/document.dart';
import 'package:pdfx_lite/src/renderer/io/platform_pigeon.dart';

/// Abstraction layer to isolate [PdfDocument] implementation
/// from the public interface.
///
/// This is a plain abstract class, not a `PlatformInterface`. The token /
/// settable-instance machinery exists so third parties can register their own
/// platform implementation; this package has exactly one ([PdfxPlatformPigeon],
/// which serves both Android and iOS), so it only cost a dependency.
abstract class PdfxPlatform {
  /// The instance of [PdfxPlatform] to use.
  static final PdfxPlatform instance = PdfxPlatformPigeon();

  Future<PdfDocument> openFile(String filePath);

  Future<PdfDocument> openAsset(String name);

  Future<PdfDocument> openData(FutureOr<Uint8List> data);
}
