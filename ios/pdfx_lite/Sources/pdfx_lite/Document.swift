import UIKit

/// `@unchecked Sendable`: immutable, but wraps a `CGPDFDocument`, which carries no Sendable conformance.
/// Reached from the platform thread and the render queue; see `Repository`, which holds the lock.
final class Document: @unchecked Sendable {
    let id: String
    let renderer: CGPDFDocument

    init(id: String, renderer: CGPDFDocument) {
        self.id = id
        self.renderer = renderer
    }

    var pagesCount: Int {
        get {
            return renderer.numberOfPages
        }
    }

    /**
     * Open page by page number (not index!)
     *
     * The page is not retained anywhere: it is fetched for the duration of one call and dropped, mirroring Android,
     * where `PdfRenderer` permits only one open page per document and holding one across calls is impossible.
     */
    public func openPage(pageNumber: Int) -> Page? {
        guard let page = renderer.page(at: pageNumber) else { return nil }
        return Page(renderer: page)
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

    var width: Double {
        get {
            return Double(boxRect.width)
        }
    }

    var height: Double {
        get {
            return Double(boxRect.height)
        }
    }

    var rotationAngle: Int32 {
        get {
            return renderer.rotationAngle
        }
    }

    var isLandscape: Bool {
        get {
            return Bool(rotationAngle == 90 || rotationAngle == 270)
        }
    }

    func render(width: Int, height: Int, crop: CGRect?, compressFormat: CompressFormat, backgroundColor: String = "#ffffff", quality: Int) -> Page.DataResult? {
        let box = renderer.getBoxRect(.mediaBox)
        let bitmapSize = isLandscape ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let stride = Int(bitmapSize.width * 4)
        var tempData = Data(repeating: 0, count: stride * Int(bitmapSize.height))
        var data: Data?
        var success = false
        var transform = renderer.getDrawingTransform(.mediaBox, rect: CGRect(origin: CGPoint.zero, size: bitmapSize), rotate: 0, preserveAspectRatio: true)
        let compressionQuality = CGFloat(quality) / 100
        tempData.withUnsafeMutableBytes { (ptr) in
            let rawPtr = ptr.baseAddress
            let rgb = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(data: rawPtr, width: Int(bitmapSize.width), height: Int(bitmapSize.height), bitsPerComponent: 8, bytesPerRow: stride, space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            if context != nil {
                // Credit: https://stackoverflow.com/a/35985236
                // We change the context scale to fill completely the destination size (scale-down is handled by getDrawingTransform)
                if box.width < bitmapSize.width {
                    let sx = CGFloat(width) / box.width
                    let sy = CGFloat(height) / box.height
                    transform = transform.scaledBy(x: sx, y: sy)

                    transform.tx = -(box.origin.x * transform.a + box.origin.y * transform.b)
                    transform.ty = -(box.origin.x * transform.c + box.origin.y * transform.d)

                    // Rotation handling
                    if rotationAngle == 180 || rotationAngle == 270 {
                        transform.tx += bitmapSize.width
                    }
                    if rotationAngle == 90 || rotationAngle == 180 {
                        transform.ty += bitmapSize.height
                    }
                }
                context!.concatenate(transform)
                context!.setFillColor(UIColor(hexString: backgroundColor).cgColor)
                context!.fill(box)
                context!.drawPDFPage(renderer)
                var image = UIImage(cgImage: context!.makeImage()!)

                if (crop != nil) {
                    // Perform cropping in Core Graphics
                    let cutImageRef: CGImage = (image.cgImage?.cropping(to:crop!))!
                    image = UIImage(cgImage: cutImageRef)
                }

                switch(compressFormat) {
                    case CompressFormat.JPEG:
                        data = image.jpegData(compressionQuality: compressionQuality) as Data?
                        break;
                    case CompressFormat.PNG:
                        data = image.pngData() as Data?
                        break;
                }

                success = true
            }
        }
        guard success, let bytes = data else { return nil }
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
