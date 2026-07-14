import 'package:flutter/widgets.dart';
import 'package:pdfx_lite/src/viewer/pdf_view_pinch.dart';

typedef PdfPageNumberBuilder = Widget Function(
  BuildContext context,
  PdfLoadingState loadingState,
  int page,
  int? pagesCount,
);

class PdfPageNumber extends StatelessWidget {
  const PdfPageNumber({
    required this.controller,
    required this.builder,
    super.key,
  });

  final PdfControllerPinch controller;
  final PdfPageNumberBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PdfLoadingState>(
      valueListenable: controller.loadingState,
      builder: (context, loadingState, child) => ValueListenableBuilder<int>(
        valueListenable: controller.pageListenable,
        builder: (context, page, child) => builder(
          context,
          loadingState,
          page,
          controller.pagesCount,
        ),
      ),
    );
  }
}
