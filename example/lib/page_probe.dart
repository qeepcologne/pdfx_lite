// Temporary harness: exercises every page-touching RPC now that pages are addressed by document + number.
// Run with: flutter run -t lib/page_probe.dart -d <device>
import 'package:flutter/material.dart';
import 'package:pdfx_lite/pdfx_lite.dart';

final _lines = ValueNotifier<List<String>>([]);

Future<void> _probe(String label, Future<String> Function() run) async {
  String outcome;
  try {
    outcome = await run();
  } catch (e) {
    outcome = 'THREW ${e.runtimeType}: $e';
  }
  final line = '${label.padRight(30)} | $outcome';
  debugPrint('PROBE | $line');
  _lines.value = [..._lines.value, line];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());

  final doc = await PdfDocument.openAsset('assets/hello.pdf');
  await _probe('open', () async => 'OK pages=${doc.pagesCount}');

  await _probe('getPage(1)', () async {
    final p = await doc.getPage(1);
    return 'OK ${p.width}x${p.height}';
  });

  // Used to be served from a (never-populated) cache; now it re-opens natively every time.
  await _probe('getPage(1) again', () async {
    final p = await doc.getPage(1);
    return 'OK ${p.width}x${p.height}';
  });

  await _probe('getPage(0) out of range', () async {
    await doc.getPage(0);
    return 'OK (should not happen)';
  });

  await _probe('render(png)', () async {
    final p = await doc.getPage(1);
    final img = await p.render(width: p.width, height: p.height);
    return 'OK ${img!.width}x${img.height} bytes=${img.bytes.length}';
  });

  await _probe('render(jpeg, cropped)', () async {
    final p = await doc.getPage(1);
    final img = await p.render(
      width: p.width,
      height: p.height,
      format: PdfPageImageFormat.jpeg,
      cropRect: const Rect.fromLTWH(0, 0, 50, 50),
    );
    return 'OK ${img!.width}x${img.height} bytes=${img.bytes.length}';
  });

  await _probe('texture updateRect', () async {
    final p = await doc.getPage(1);
    final tex = await p.createTexture();
    final ok = await tex.updateRect(
      documentId: doc.id,
      width: p.width.toInt(),
      height: p.height.toInt(),
      textureWidth: p.width.toInt(),
      textureHeight: p.height.toInt(),
    );
    await tex.dispose();
    return ok ? 'OK' : 'FAILED (updateRect returned false)';
  });

  // The reason `Document.withPage` is serialized on Android: `renderPage` runs on a background coroutine while
  // `updateTexture` runs on the platform thread, and `PdfRenderer` permits only one open page per document.
  //
  // The renders are deliberately big (2500x3000, ~30MB bitmaps plus a PNG encode) so each one holds its page open
  // long enough to still be rendering when a texture update tries to open a page on the same document. A quick
  // render finishes before the overlap can happen and the probe passes even with the lock removed — proving nothing.
  // Firing everything in one Future.wait does NOT overlap: the platform thread drains all the texture updates
  // before the first render coroutine is even launched. The render has to be in flight first.
  await _probe('overlap: big render + texture', () async {
    final p = await doc.getPage(1);
    final p2 = await doc.getPage(2);
    final tex = await p.createTexture();

    final render = p2.render(width: 2500, height: 3000);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final updates = await Future.wait([
      for (var i = 0; i < 40; i++)
        tex.updateRect(
          documentId: doc.id,
          width: p.width.toInt(),
          height: p.height.toInt(),
          textureWidth: p.width.toInt(),
          textureHeight: p.height.toInt(),
        ),
    ]);
    final img = await render;
    await tex.dispose();

    final bad = updates.where((ok) => !ok).length;
    return bad == 0 && img != null
        ? 'OK 40 updates + render ${img.width}x${img.height}'
        : 'FAILED $bad of 40 updates, render=${img?.width}';
  });

  await doc.close();
  await _probe('getPage after close', () async {
    await doc.getPage(1);
    return 'OK (should not happen)';
  });

  debugPrint('PROBE | DONE');
  _lines.value = [..._lines.value, 'DONE'];
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('page probe')),
          body: ValueListenableBuilder<List<String>>(
            valueListenable: _lines,
            builder: (_, lines, _) => ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final l in lines)
                  Text(
                    l,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: l.contains('THREW') || l.contains('FAILED')
                          ? Colors.red
                          : Colors.black,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
