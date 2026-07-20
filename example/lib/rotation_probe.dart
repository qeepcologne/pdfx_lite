// Ground truth for how each platform reports a rotated page.
//   flutter build apk --debug -t lib/rotation_probe.dart
import 'package:flutter/material.dart';
import 'package:pdfx_lite/pdfx_lite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final name in ['hello.pdf', 'rotated90.pdf']) {
    try {
      final doc = await PdfDocument.openAsset('assets/$name');
      final p = await doc.getPage(1);
      final img = await p.render(width: p.width, height: p.height);
      debugPrint('ROT | $name getPage=${p.width}x${p.height} '
          'render=${img.width}x${img.height} bytes=${img.bytes.length}');
      final img2 = await p.render(width: 200, height: 100);
      debugPrint('ROT | $name render(200x100)=${img2.width}x${img2.height}');
      await doc.close();
    } catch (e) {
      debugPrint('ROT | $name THREW $e');
    }
  }
  debugPrint('ROT | DONE');
  runApp(const SizedBox());
}
