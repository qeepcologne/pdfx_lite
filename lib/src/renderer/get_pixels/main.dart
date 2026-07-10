import 'dart:typed_data';

import 'io.dart';

Future<Uint8List> getPixels({
  String? path,
  List<int>? bytes,
  bool removeTempFile = true,
}) =>
    getPlatformPixels(
      path: path,
      bytes: bytes,
      removeTempFile: removeTempFile,
    );
