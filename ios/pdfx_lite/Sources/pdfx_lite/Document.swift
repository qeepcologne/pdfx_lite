import UIKit

/// `@unchecked Sendable`: immutable, but wraps a `CGPDFDocument`, which carries no Sendable conformance.
///
/// The lock below is what makes the "unchecked" honest. `Repository`'s own lock guards only the *dictionary* — once
/// it hands a `Document` out, two callers hold the same `CGPDFDocument`, and that is not safe for concurrent use:
/// `renderPage` rasterizes on the render queue while `updateTexture` and `getPage` touch the same document from the
/// platform thread, sharing its page cache and xref parser. Every use goes through [withPage] or [pagesCount].
///
/// This mirrors Android, where `Document.withPage` serializes for the same reason (there, because `PdfRenderer`
/// permits only one open page at a time).
final class Document: @unchecked Sendable {
    let id: String
    private let renderer: CGPDFDocument
    private let lock = NSLock()

    init(id: String, renderer: CGPDFDocument) {
        self.id = id
        self.renderer = renderer
    }

    var pagesCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return renderer.numberOfPages
    }

    /**
     * Open page [pageNumber] (not index!), hand it to `block`, and drop it again.
     *
     * The page is not retained anywhere: it lives for the duration of one call, mirroring Android, where
     * `PdfRenderer` permits only one open page per document and holding one across calls is impossible.
     */
    func withPage<T>(pageNumber: Int, _ block: (Page) throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let page = renderer.page(at: pageNumber) else { return nil }
        return try block(Page(renderer: page))
    }
}

/// `@unchecked Sendable`: immutable, but wraps a `CGPDFPage`. `render` runs on the background render queue.
final class Page: @unchecked Sendable {
    let renderer: CGPDFPage
    let boxRect: CGRect

    init(renderer: CGPDFPage) {
        self.renderer = renderer
        self.boxRect = renderer.getBoxRect(.mediaBox)
    }

    var rotationAngle: Int32 {
        //Normalised: /Rotate is permitted to be negative or beyond 360.
        let raw = renderer.rotationAngle % 360
        return raw < 0 ? raw + 360 : raw
    }

    /// The size the page is *displayed* at, i.e. with `/Rotate` applied.
    ///
    /// Reporting the raw mediaBox instead was the root of upstream #554: the texture path already worked in rotated
    /// space (`getRotatedSize`), so a rotated page was laid out with one aspect ratio and drawn with another.
    /// Android reports the rotated size too -- measured, not assumed: a 300x400 page with `/Rotate 90` reports
    /// 400x300 from `PdfRenderer.Page` and renders to exactly that.
    var displaySize: CGSize {
        (rotationAngle == 90 || rotationAngle == 270)
            ? CGSize(width: boxRect.height, height: boxRect.width)
            : boxRect.size
    }

    var width: Double { Double(displaySize.width) }

    var height: Double { Double(displaySize.height) }

    /// Render the page into a `width` x `height` bitmap and encode it.
    ///
    /// The page is stretched to fill exactly, never letterboxed, and the returned image is exactly the requested
    /// size -- which is what Android does (measured: a 300x400 page rendered at 200x100 comes back 200x100 there).
    ///
    /// The transform is built explicitly rather than via `getDrawingTransform`, which preserves aspect ratio and
    /// refuses to scale up. Working around that needed a documented hack that multiplied its scale on top of an
    /// already-scaled transform whenever the page did not fit -- double-scaling the page anisotropically -- and its
    /// guard tested only the width, so a bitmap narrower but much taller than the page skipped the correction
    /// entirely and drew the page small and centred in mostly-empty space.
    func render(width: Int, height: Int, crop: CGRect?, compressFormat: CompressFormat, backgroundColor: String = "#ffffff", quality: Int) -> Page.DataResult? {
        let display = displaySize
        guard width > 0, height > 0, display.width > 0, display.height > 0 else { return nil }

        let bitmapSize = CGSize(width: width, height: height)
        let stride = width * 4
        var tempData = Data(repeating: 0, count: stride * height)
        var data: Data?
        let compressionQuality = CGFloat(quality) / 100

        tempData.withUnsafeMutableBytes { (ptr) in
            guard let rawPtr = ptr.baseAddress else { return }
            let rgb = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: rawPtr,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: stride,
                space: rgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            //Fill the whole bitmap, under the identity transform. The old code filled only the mapped mediaBox, so
            //in every letterboxed case the margins kept the zero fill -- transparent for PNG, black for JPEG --
            //rather than the requested background.
            context.setFillColor(UIColor(hexString: backgroundColor).cgColor)
            context.fill(CGRect(origin: .zero, size: bitmapSize))

            //Applied outermost: page space -> normalised origin -> rotated into display space -> scaled to fill.
            context.scaleBy(x: bitmapSize.width / display.width, y: bitmapSize.height / display.height)
            switch rotationAngle {
            case 90:
                context.translateBy(x: 0, y: display.height)
                context.rotate(by: -.pi / 2)
            case 180:
                context.translateBy(x: display.width, y: display.height)
                context.rotate(by: .pi)
            case 270:
                context.translateBy(x: display.width, y: 0)
                context.rotate(by: .pi / 2)
            default:
                break
            }
            context.translateBy(x: -boxRect.origin.x, y: -boxRect.origin.y)
            context.drawPDFPage(renderer)

            //`makeImage` can fail; force-unwrapping it crashed the app where every other failure here returns nil and
            //surfaces as a clean error.
            guard let rendered = context.makeImage() else { return }
            var image = UIImage(cgImage: rendered)

            if let crop {
                //`cropping(to:)` returns nil when the rect does not intersect the image -- reachable from the public
                //`render(cropRect:)` with an out-of-bounds rect, and previously a guaranteed crash. The rect is in
                //top-left image coordinates, the same as Android's `Bitmap.createBitmap`, and the bitmap is no longer
                //transposed for rotated pages -- so the two platforms now crop the same region.
                guard let cutImageRef = image.cgImage?.cropping(to: crop) else { return }
                image = UIImage(cgImage: cutImageRef)
            }

            switch compressFormat {
            case .JPEG:
                data = image.jpegData(compressionQuality: compressionQuality)
            case .PNG:
                data = image.pngData()
            }
        }

        guard let bytes = data else { return nil }
        return Page.DataResult(
            width: (crop != nil) ? Int(crop!.width) : width,
            height: (crop != nil) ? Int(crop!.height) : height,
            bytes: bytes
        )
    }

    /// A value type, so it can be handed back from the render queue to the platform thread.
    struct DataResult: Sendable {
        let width: Int
        let height: Int
        let bytes: Data
    }
}

enum CompressFormat: Int {
    case JPEG = 0
    case PNG = 1
}
