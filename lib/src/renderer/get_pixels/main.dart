import 'dart:typed_data';

import 'io.dart';

Future<Uint8List> getPixels({
  required String path,
  bool removeTempFile = true,
}) =>
    getPlatformPixels(path: path, removeTempFile: removeTempFile);
