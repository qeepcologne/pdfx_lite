import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show PlatformException;
import 'package:meta/meta.dart';
import 'package:pdfx_lite/src/renderer/pigeon.dart';
import 'package:synchronized/synchronized.dart';

part 'document.dart';
part 'page.dart';
part 'page_image.dart';
part 'page_texture.dart';

//The renderer is one library across four files, rather than an abstract interface plus an implementation of it.
//Upstream split them so a third party could register its own platform, and so that web and desktop could each bring
//one; with Android and iOS both served by the single pigeon bridge below, the indirection had exactly one implementor
//and bought nothing. `part`, not separate libraries, so `_api` and `_lock` below can stay private.

/// Serializes a document's use against its close.
///
/// Not for the native side's benefit — both platforms guard their own state. It closes the gap in
/// `if (isClosed) throw; await _api.something()`: the check and the call sit either side of an `await`, so without
/// this a `close()` can land between them and the native call arrives at a document that is already gone.
final _lock = Lock();
final _api = PdfxApi();

/// Error codes both native sides use for an encrypted PDF. Kept in sync by hand with `Messages.kt` and
/// `SwiftPdfxPlugin.swift` — pigeon generates the message types, not the error codes.
const _passwordProtectedCode = 'PDF_PASSWORD_PROTECTED';
const _passwordUnsupportedCode = 'PDF_PASSWORD_UNSUPPORTED';
