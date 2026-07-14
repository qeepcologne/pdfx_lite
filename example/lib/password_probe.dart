// Temporary harness: probes every (source x fixture x password) combination and prints one line each.
// Run with: flutter run -t lib/password_probe.dart -d <device>
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfx_lite/pdfx_lite.dart';

Future<String> _outcome(Future<PdfDocument> Function() open) async {
  try {
    final doc = await open();
    final pages = doc.pagesCount;
    await doc.close();
    return 'OK pages=$pages';
  } catch (e) {
    // By runtimeType, so this harness compiles against versions without the new exception types too.
    return '${e.runtimeType}';
  }
}

Future<void> _probe(String label, Future<PdfDocument> Function() open) async {
  debugPrint('PROBE | ${label.padRight(42)} | ${await _outcome(open)}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('PROBE | isPasswordSupported                      | '
      '${await PdfDocument.isPasswordSupported()}');

  for (final name in ['hello', 'locked', 'perms_only']) {
    final asset = 'assets/$name.pdf';
    final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    final file = File('${Directory.systemTemp.path}/$name.pdf')
      ..writeAsBytesSync(bytes);

    for (final pw in [null, 'secret', 'wrong']) {
      final tag = pw == null ? 'no-pw' : 'pw=$pw';
      await _probe('asset  $name ($tag)',
          () => PdfDocument.openAsset(asset, password: pw));
      await _probe(
          'file   $name ($tag)',
          () => PdfDocument.openFile(file.path, password: pw));
      await _probe('data   $name ($tag)',
          () => PdfDocument.openData(bytes, password: pw));
    }
  }

  debugPrint('PROBE | DONE');
  exit(0);
}
