import 'dart:async';

/// pdfx_lite ships Android + iOS only, and both render PDFs natively.
Future<bool> hasPdfSupport() async => true;
