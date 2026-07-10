import 'package:flutter/material.dart';
import 'package:pdfx_lite/pdfx_lite.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: PdfScreen());
}

class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key});

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  late final PdfControllerPinch _controller = PdfControllerPinch(
    document: PdfDocument.openAsset('assets/hello.pdf'),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: PdfPageNumber(
            controller: _controller,
            builder: (_, _, page, pagesCount) =>
                Text('Page $page of ${pagesCount ?? 0}'),
          ),
        ),
        body: PdfViewPinch(controller: _controller),
      );
}
