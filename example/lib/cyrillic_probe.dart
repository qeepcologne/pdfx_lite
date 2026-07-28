// #557: does Cyrillic render on Android? Renders two fixtures through pdfx_lite and shows the pixels.
//   embedded  -> font glyphs are in the PDF; if this fails it's our/pdfium bug.
//   noembed   -> bare /Arial reference; renderer must substitute (poppler itself drops it).
//   flutter build apk --debug -t lib/cyrillic_probe.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx_lite/pdfx_lite.dart';

Future<Uint8List?> _render(String asset) async {
  try {
    final doc = await PdfDocument.openAsset('assets/$asset');
    final p = await doc.getPage(1);
    final img = await p.render(
      width: p.width * 2,
      height: p.height * 2,
      format: PdfPageImageFormat.png,
      backgroundColor: '#FFFFFF',
    );
    await doc.close();
    debugPrint('CYR | $asset ${p.width}x${p.height} -> ${img?.bytes.length} bytes');
    return img?.bytes;
  } catch (e) {
    debugPrint('CYR | $asset THREW $e');
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final embedded = await _render('cyrillic_embedded.pdf');
  final noembed = await _render('cyrillic_noembed.pdf');
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('EMBEDDED font:', style: TextStyle(fontWeight: FontWeight.bold)),
            if (embedded != null) Image.memory(embedded) else const Text('render failed'),
            const SizedBox(height: 12),
            const Text('NON-EMBEDDED font:', style: TextStyle(fontWeight: FontWeight.bold)),
            if (noembed != null) Image.memory(noembed) else const Text('render failed'),
          ]),
        ),
      ),
    ),
  ));
}
