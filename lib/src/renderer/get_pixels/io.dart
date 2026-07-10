import 'dart:io';
import 'dart:typed_data';

/// Android and iOS always render to a temp file. The in-memory `bytes` fallback
/// upstream carried existed only for the web/windows renderers.
Future<Uint8List> getPlatformPixels({
  required String path,
  bool removeTempFile = true,
}) async {
  final file = File(path);

  final Uint8List pixels = await file.readAsBytes();
  if (removeTempFile) {
    await file.delete();
  }
  return pixels;
}
