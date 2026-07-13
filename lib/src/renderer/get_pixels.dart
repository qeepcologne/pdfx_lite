import 'dart:io';
import 'dart:typed_data';

/// Reads a rendered page back from the temp file the native renderer wrote.
///
/// Android and iOS always render to a temp file. The in-memory `bytes` fallback
/// upstream carried existed only for the web/windows renderers.
Future<Uint8List> getPixels({
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
