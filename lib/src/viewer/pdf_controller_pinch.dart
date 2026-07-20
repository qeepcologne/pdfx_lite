part of 'pdf_view_pinch.dart';

/// Pages control
class PdfControllerPinch extends TransformationController {
  PdfControllerPinch({
    required this.document,
    this.initialPage = 1,
    this.viewportFraction = 1.0,
  }) : assert(viewportFraction > 0.0);

  final ValueNotifier<PdfLoadingState> loadingState =
      ValueNotifier(PdfLoadingState.loading);

  /// Document future for showing in [PdfViewPinch]
  Future<PdfDocument> document;

  /// The page to show when first creating the [PdfViewPinch].
  late int initialPage;

  int? _pendingInitialPage;

  int? get pendingInitialPage {
    final value = _pendingInitialPage;
    _pendingInitialPage = null;
    return value;
  }

  /// The fraction of the viewport that each page should occupy.
  ///
  /// Defaults to 1.0, which means each page fills the viewport in the scrolling
  /// direction.
  final double viewportFraction;

  _PdfViewPinchState? _state;
  PdfDocument? _document;

  // Provide document progress.
  // document start documentProgress = 0.0,
  // document end documentProgress = 1.0,
  double _documentProgress = 0;
  double get documentProgress => _documentProgress;

  /// Actual page number wrapped with ValueNotifier
  late final ValueNotifier<int> pageListenable = ValueNotifier(initialPage);

  /// Get the current page number by obtaining
  /// the page that has the largest area from [visiblePages].
  int get page {
    MapEntry<int, double>? max;
    for (final v in visiblePages.entries) {
      if (max == null || max.value < v.value) {
        max = v;
      }
    }
    return max?.key ?? initialPage;
  }

  late int _prevPage = initialPage;

  VoidCallback? _pageChangeListener;

  int? get pagesCount => _document?.pagesCount;

  /// Get page location. If the page is out of view,
  ///
  /// Returns null rather than throwing when the page list is empty or shorter than `pageNumber` -- which it is
  /// during a load, and which `animateToPage` could reach because its own guard checks `pagesCount` instead.
  Rect? getPageRect(int pageNumber) {
    final pages = _state?._pages;
    if (pages == null || pageNumber < 1 || pageNumber > pages.length) {
      return null;
    }
    return pages[pageNumber - 1].rect;
  }

  /// Load document
  Future<void> loadDocument(
    Future<PdfDocument> documentFuture, {
    int initialPage = 1,
  }) {
    //Release BEFORE announcing `loading`. The view's `loadingState` listener clears `_pages` synchronously, so
    //announcing first left `_releasePages()` with nothing to walk and every texture of the outgoing document was
    //dropped without `unregisterTexture`.
    _state?._releasePages();
    loadingState.value = PdfLoadingState.loading;
    return _loadDocument(documentFuture, initialPage: initialPage);
  }

  Future<void> _loadDocument(
    Future<PdfDocument> documentFuture, {
    int initialPage = 1,
  }) async {
    assert(_state != null);

    try {
      _state?._releasePages();

      _document = await documentFuture;
      if (_state == null) {
        //The view was disposed while the document was loading; there is nobody left to lay the pages out.
        return;
      }

      _state!._pages.clear();
      final List<_PdfPageState> pages = [];
      final firstPage = await _document!.getPage(1);
      final firstPageSize = Size(
        firstPage.width,
        firstPage.height,
      );
      for (int i = 0; i < _document!.pagesCount; i++) {
        pages.add(_PdfPageState._(
          pageNumber: i + 1,
          pageSize: firstPageSize,
        ));
      }
      _state!._firstControllerAttach = true;
      _state!._pages.addAll(pages);

      if (initialPage > 1) {
        _pendingInitialPage = initialPage;
      }

      loadingState.value = PdfLoadingState.success;
    } catch (error, stack) {
      //Wrap rather than replace: `Error`s (StateError, UnsupportedError, RangeError) used to be flattened to a bare
      //`Exception('Unknown error')`, which threw away the only diagnostic the caller's `errorBuilder` would ever see.
      _state?._loadingError =
          error is Exception ? error : PdfLoadingFailure(error, stack);
      loadingState.value = PdfLoadingState.error;
    }
  }

  /// Associate a [_PdfViewPinchState] to the controller.
  void _setViewerState(_PdfViewPinchState? state) {
    _state = state;
    if (_state != null) {
      notifyListeners();
    }
  }

  void _attach(_PdfViewPinchState pdfViewState) {
    if (_state != null) {
      return;
    }

    _state = pdfViewState;

    //Held in a field so `_detach` can remove it. As an inline closure it could never be removed, so every attach left
    //another copy listening — and after a detach nulled `_state` they fired against it and threw.
    _pageChangeListener ??= () {
      if (_state == null) {
        return;
      }
      if (page != _prevPage) {
        _state!.widget.onPageChanged?.call(page);
        pageListenable.value = page;
        _prevPage = page;
      }
    };
    addListener(_pageChangeListener!);

    if (_document == null) {
      _loadDocument(document, initialPage: initialPage);
    } else {
      //Re-attached to a fresh view with the document already loaded. `_pages` lives on the view's State, so the new
      //one is empty and nothing else would ever fill it — the viewer stayed permanently blank. Rebuild the page list
      //without re-opening the document.
      _repopulatePages();
    }
  }

  /// Rebuild the per-page layout state for an already-open document.
  Future<void> _repopulatePages() async {
    final document = _document;
    if (document == null || _state == null) {
      return;
    }
    try {
      final firstPage = await document.getPage(1);
      final firstPageSize = Size(firstPage.width, firstPage.height);
      final state = _state;
      if (state == null) {
        return;
      }
      state._pages
        ..clear()
        ..addAll([
          for (int i = 0; i < document.pagesCount; i++)
            _PdfPageState._(pageNumber: i + 1, pageSize: firstPageSize),
        ]);
      state._firstControllerAttach = true;
      loadingState.value = PdfLoadingState.success;
    } catch (error, stack) {
      _state?._loadingError =
          error is Exception ? error : PdfLoadingFailure(error, stack);
      loadingState.value = PdfLoadingState.error;
    }
  }

  /// Changes which page is displayed in the controlled [PdfView].
  ///
  /// Jumps the page position from its current value to the given value,
  /// without animation, and without checking if the new value is in range.
  void jumpToPage(int page) => animateToPage(
        pageNumber: page + 1,
        duration: Duration.zero,
        curve: Curves.linear,
      );

  /// Go to the destination specified by the matrix.
  /// To go to a specific page, use [animateToPage] method or use
  ///  [calculatePageFitMatrix] method to calculate the page location matrix.
  /// If [destination] is null, the method does nothing.
  Future<void> goTo({
    Matrix4? destination,
    Duration duration = const Duration(milliseconds: 200),
    Curve curve = Curves.easeInOut,
  }) =>
      _state!._goTo(
        destination: destination,
        duration: duration,
        curve: curve,
      );

  /// Go to the specified page.
  Future<void> animateToPage({
    required int pageNumber,
    double? padding,
    Duration duration = const Duration(milliseconds: 500),
    Curve curve = Curves.easeInOut,
  }) {
    if (pageNumber < 1 || pageNumber > _document!.pagesCount) {
      return Future.value();
    }

    return goTo(
      destination: calculatePageFitMatrix(
        pageNumber: pageNumber,
        padding: padding,
      ),
      duration: duration,
    );
  }

  /// Animates the controlled [PdfViewPinch] to the next page.
  ///
  /// The animation lasts for the given duration and follows the given curve.
  /// The returned [Future] resolves when the animation completes.
  ///
  /// The `duration` and `curve` arguments must not be null.
  Future<void> nextPage({
    required Duration duration,
    required Curve curve,
  }) =>
      animateToPage(pageNumber: page + 1, duration: duration, curve: curve);

  /// Animates the controlled [PdfViewPinch] to the previous page.
  ///
  /// The animation lasts for the given duration and follows the given curve.
  /// The returned [Future] resolves when the animation completes.
  ///
  /// The `duration` and `curve` arguments must not be null.
  Future<void> previousPage({
    required Duration duration,
    required Curve curve,
  }) =>
      animateToPage(pageNumber: page - 1, duration: duration, curve: curve);

  /// Current view rectangle.
  /// If the controller is not ready([PdfViewPinch]), the property
  ///  throws an exception.
  Rect get viewRect => Rect.fromLTWH(
        -value.row0[3],
        -value.row1[3],
        _state!._lastViewSize!.width,
        _state!._lastViewSize!.height,
      );

  /// Current view zoom ratio.
  double get zoomRatio => value.row0[0];

  /// Get list of the page numbers of the pages visible inside the viewport.
  /// The map keys are the page numbers.
  /// And each page number is associated to the page area (width x height)
  ///  exposed to the viewport;
  Map<int, double> get visiblePages => _state!._visiblePages;

  /// Calculate the matrix that corresponding to the page position.
  Matrix4? calculatePageFitMatrix({required int pageNumber, double? padding}) {
    final rect = getPageRect(pageNumber)?.inflate(padding ?? _state!._padding);
    if (rect == null) {
      return null;
    }
    final scale = _state!._lastViewSize!.width / rect.width;
    final left = max(
        0.0,
        min(
          rect.left,
          _state!._docSize!.width - _state!._lastViewSize!.width,
        ));
    final top = max(
        0.0,
        min(
          rect.top,
          _state!._docSize!.height - _state!._lastViewSize!.height,
        ));
    return Matrix4.compose(
      math64.Vector3(-left, -top, 0),
      math64.Quaternion.identity(),
      math64.Vector3(scale, scale, 1),
    );
  }

  void _detach() {
    if (_pageChangeListener != null) {
      removeListener(_pageChangeListener!);
    }
    _state = null;
  }

  @override
  void dispose() {
    if (_pageChangeListener != null) {
      removeListener(_pageChangeListener!);
      _pageChangeListener = null;
    }
    loadingState.dispose();
    pageListenable.dispose();
    super.dispose();
  }
}

/// Wraps a non-[Exception] failure from document loading so the original object and its stack survive.
class PdfLoadingFailure implements Exception {
  PdfLoadingFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => 'PdfLoadingFailure: $error';
}

enum _PdfPageLoadingStatus {
  notInitialized,
  initializing,
  initialized,
  pageLoading,
  pageLoaded,
  disposed
}

/// Internal page control structure.
class _PdfPageState {
  _PdfPageState._({
    required this.pageNumber,
    required this.pageSize,
  });

  /// Page number (started at 1).
  final int pageNumber;

  /// [PdfPage] corresponding to the page if available.
  late final PdfPage pdfPage;

  /// Where the page is layed out if available. It can be null to not show
  /// in the view.
  Rect? rect;

  /// Size at 72-dpi. During the initialization, the size may be just a
  ///  copy of the size of the first page.
  Size pageSize;

  /// Preview image of the page rendered at low resolution.
  PdfPageTexture? preview;

  /// Relative position of the realSize overlay. null to not show
  /// realSize overlay.
  Rect? realSizeOverlayRect;

  /// realSize overlay.
  PdfPageTexture? realSize;

  /// Whether the page is visible within the view or not.
  bool isVisibleInsideView = false;

  _PdfPageLoadingStatus status = _PdfPageLoadingStatus.notInitialized;

  final _previewNotifier = ValueNotifier<int>(0);
  final _realSizeNotifier = ValueNotifier<int>(0);

  void updatePreview() {
    if (status != _PdfPageLoadingStatus.disposed) {
      _previewNotifier.value++;
    }
  }

  void _updateRealSizeOverlay() {
    if (status != _PdfPageLoadingStatus.disposed) {
      _realSizeNotifier.value++;
    }
  }

  bool releaseRealSize() {
    realSize?.dispose();
    realSize = null;
    return true;
  }

  /// Release allocated textures.
  /// It's always safe to call the method. If all the textures were already
  ///  released, the method does nothing.
  /// Returns true if textures are really released; otherwise if the method
  /// does nothing and returns false.
  bool releaseTextures() => _releaseTextures(_PdfPageLoadingStatus.initialized);

  bool _releaseTextures(_PdfPageLoadingStatus newStatus) {
    preview?.dispose();
    preview = null;
    releaseRealSize();
    status = newStatus;
    return true;
  }

  void dispose() {
    _releaseTextures(_PdfPageLoadingStatus.disposed);
    _previewNotifier.dispose();
    _realSizeNotifier.dispose();
  }
}

/// Where a [PdfControllerPinch] is in loading its document.
enum PdfLoadingState {
  loading,
  error,
  success,
}
