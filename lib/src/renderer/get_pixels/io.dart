import 'dart:io';
import 'dart:typed_data';

/// Android and iOS always render to a temp file, so [path] is never null here.
/// The in-memory [bytes] fallback existed only for the web/windows renderers.
Future<Uint8List> getPlatformPixels({
  String? path,
  List<int>? bytes,
  bool removeTempFile = true,
}) async {
  if (path == null) {
    throw StateError('pdfx_lite: native renderer returned no file path');
  }
  final file = File(path);

  final Uint8List pixels = await file.readAsBytes();
  if (removeTempFile) {
    await file.delete();
  }
  return pixels;
}
