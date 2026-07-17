import Flutter
import UIKit
import CoreGraphics

private func renderError(_ message: String) -> PigeonError {
    PigeonError(code: "RENDER_ERROR", message: message, details: nil)
}

/// The error code for an encrypted PDF, shared verbatim with Android and with the Dart side, which turns it into
/// `PdfPasswordProtectedException`.
private func passwordProtectedError() -> PigeonError {
    PigeonError(code: "PDF_PASSWORD_PROTECTED", message: "The PDF is password-protected", details: nil)
}

/// Why a document would not open. Distinguishing the two matters: an encrypted PDF is a perfectly valid file that
/// simply needs a password, and reporting it as "Invalid PDF format" leaves the caller unable to tell the difference.
private enum OpenFailure: Error {
    case invalid
    case passwordProtected
}

private func openFailure(_ error: Error) -> PigeonError {
    if case OpenFailure.passwordProtected = error {
        return passwordProtectedError()
    }
    return renderError("Invalid PDF format")
}

/// Carries a non-Sendable value across a `@Sendable` closure boundary.
///
/// Needed because pigeon generates `PdfxApi` completions as plain `@escaping (Result<T, Error>) -> Void` — not
/// `@Sendable` — while `DispatchQueue.async` takes a `@Sendable` closure. Capturing the box (which is Sendable) and
/// calling `.value` inside is legal; capturing the closure directly is not. Safe here because the completion is
/// invoked exactly once, back on the main queue.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}

/// `@unchecked Sendable`: the repositories are lock-guarded (see `Repository`), `textures` is only touched on the
/// platform thread, and `registrar`/`dispQueue` are immutable. Cannot be actor-isolated instead — the generated
/// `PdfxApi` protocol is non-isolated, so an isolated type could not conform to it.
public final class SwiftPdfxPlugin: NSObject, FlutterPlugin, PdfxApi, @unchecked Sendable {
    let registrar: FlutterPluginRegistrar
    let dispQueue = DispatchQueue(label: "io.scer.pdf_renderer")

    let documents = DocumentRepository()
    var textures: [Int64: PdfPageTexture] = [:]

    init(registrar: FlutterPluginRegistrar) {
      self.registrar = registrar
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        PdfxApiSetup.setUp(
            binaryMessenger: registrar.messenger(),
            api: SwiftPdfxPlugin(registrar: registrar)
        )
    }

    func openDocumentData(message: OpenDataMessage, completion: @escaping (Result<OpenReply, Error>) -> Void) {
        guard let data = message.data else {
            return completion(.failure(renderError("Arguments not sended")))
        }
        let renderer: CGPDFDocument
        do {
            renderer = try openDataDocument(data: data.data, password: message.password)
        } catch {
            return completion(.failure(openFailure(error)))
        }

        let document = documents.register(renderer: renderer)
        completion(.success(OpenReply(
            id: document.id,
            pagesCount: Int64(document.pagesCount)
        )))
    }

    func openDocumentFile(message: OpenPathMessage, completion: @escaping (Result<OpenReply, Error>) -> Void) {
        guard let pdfFilePath = message.path else {
            return completion(.failure(renderError("Arguments not sended")))
        }
        let renderer: CGPDFDocument
        do {
            renderer = try openFileDocument(pdfFilePath: pdfFilePath, password: message.password)
        } catch {
            return completion(.failure(openFailure(error)))
        }

        let document = documents.register(renderer: renderer)
        completion(.success(OpenReply(
            id: document.id,
            pagesCount: Int64(document.pagesCount)
        )))
    }

    func openDocumentAsset(message: OpenPathMessage, completion: @escaping (Result<OpenReply, Error>) -> Void) {
        guard let name = message.path else {
            return completion(.failure(renderError("Arguments not sended")))
        }
        let renderer: CGPDFDocument
        do {
            renderer = try openAssetDocument(name: name, password: message.password)
        } catch {
            return completion(.failure(openFailure(error)))
        }

        let document = documents.register(renderer: renderer)
        completion(.success(OpenReply(
            id: document.id,
            pagesCount: Int64(document.pagesCount)
        )))
    }

    func closeDocument(message: IdMessage) throws {
        if let id = message.id {
            documents.close(id: id)
        }
    }

    func getPage(message: GetPageMessage, completion: @escaping (Result<GetPageReply, Error>) -> Void) {
        guard let documentId = message.documentId, let pageNumber = message.pageNumber else {
            return completion(.failure(renderError("Need call arguments: documentId & pageNumber")))
        }
        do {
            guard let page = try documents.get(id: documentId).openPage(pageNumber: Int(pageNumber)) else {
                return completion(.failure(renderError("No page \(pageNumber) in document")))
            }

            completion(.success(GetPageReply(
                width: page.width,
                height: page.height
            )))
        } catch let err {
            completion(.failure(renderError("Unexpected error: \(err).")))
        }
    }

    func renderPage(message: RenderPageMessage, completion: @escaping (Result<RenderPageReply, Error>) -> Void) {
        guard let documentId = message.documentId,
              let pageNumber = message.pageNumber,
              let width = message.width,
              let height = message.height,
              let format = message.format,
              let backgroundColor = message.backgroundColor,
              let quality = message.quality else {
            return completion(.failure(renderError("Missing render arguments")))
        }
        guard let compressFormat = CompressFormat(rawValue: Int(format)) else {
            return completion(.failure(renderError("Unsupported format: \(format)")))
        }

        //Set crop if required. A `let`, not a `var`: the render closure below is @Sendable and cannot capture a
        //mutable local.
        let cropZone: CGRect? = {
            guard message.crop == true,
                  let cropWidth = message.cropWidth,
                  let cropHeight = message.cropHeight,
                  cropWidth != width || cropHeight != height else {
                return nil
            }
            return CGRect(x: Int(message.cropX ?? 0),
                          y: Int(message.cropY ?? 0),
                          width: Int(cropWidth),
                          height: Int(cropHeight))
        }()

        //The completion is not @Sendable (pigeon generates it plain), so it rides across the queue in a box.
        let boxed = UncheckedSendable(value: completion)

        dispQueue.async {
            do {
                guard let page = try self.documents.get(id: documentId).openPage(pageNumber: Int(pageNumber)) else {
                    return DispatchQueue.main.async {
                        boxed.value(.failure(renderError("No page \(pageNumber) in document")))
                    }
                }
                guard let data = page.render(
                    width: Int(width),
                    height: Int(height),
                    crop: cropZone,
                    compressFormat: compressFormat,
                    backgroundColor: backgroundColor,
                    quality: Int(quality)
                ) else {
                    return DispatchQueue.main.async {
                        boxed.value(.failure(renderError("Page render produced no file")))
                    }
                }

                let reply = RenderPageReply(
                    width: Int64(data.width),
                    height: Int64(data.height),
                    bytes: FlutterStandardTypedData(bytes: data.bytes)
                )
                DispatchQueue.main.async {
                    boxed.value(.success(reply))
                }
            } catch {
                DispatchQueue.main.async {
                    boxed.value(.failure(renderError("Unexpected error: \(error).")))
                }
            }
        }
    }

    func registerTexture() throws -> RegisterTextureReply {
        let pageTex = PdfPageTexture(registrar: registrar)
        let texId = registrar.textures().register(pageTex)
        textures[texId] = pageTex
        pageTex.texId = texId
        return RegisterTextureReply(id: texId)
    }

    func unregisterTexture(message: UnregisterTextureMessage) throws {
        guard let texId = message.id else {
            throw renderError("Need call arguments: id")
        }
        registrar.textures().unregisterTexture(texId)
        textures[texId] = nil
    }

    func resizeTexture(message: ResizeTextureMessage, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let texId = message.textureId, let width = message.width, let height = message.height else {
            return completion(.failure(renderError("Need call arguments: textureId, width, height")))
        }
        guard let pageTex = textures[texId] else {
            return completion(.failure(renderError("No texture of texId=\(texId)")))
        }
        pageTex.resize(width: Int(width), height: Int(height))
        completion(.success(()))
    }

    func updateTexture(message: UpdateTextureMessage, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let texId = message.textureId, let pageTex = textures[texId] else {
            return completion(.failure(renderError("No texture of texId=\(String(describing: message.textureId))")))
        }
        guard let documentId = message.documentId, let pageNumber = message.pageNumber else {
            return completion(.failure(renderError("Need call arguments: documentId & pageNumber")))
        }

        if let tw = message.textureWidth, let th = message.textureHeight {
            pageTex.resize(width: Int(tw), height: Int(th))
        }

        guard let width = message.width, let height = message.height else {
            return completion(.failure(renderError("width/height nil")))
        }

        do {
            guard let page = try documents.get(id: documentId).openPage(pageNumber: Int(pageNumber)) else {
                return completion(.failure(renderError("No page \(pageNumber) in document")))
            }

            try pageTex.updateTex(
                page: page.renderer,
                destX: Int(message.destinationX ?? 0),
                destY: Int(message.destinationY ?? 0),
                width: Int(width),
                height: Int(height),
                srcX: Int(message.sourceX ?? 0),
                srcY: Int(message.sourceY ?? 0),
                fullWidth: message.fullWidth,
                fullHeight: message.fullHeight,
                backgroundColor: message.backgroundColor,
                allowAntialiasing: message.allowAntiAliasing ?? true
            )
            completion(.success(()))
        } catch {
            completion(.failure(renderError("Cannot render texture")))
        }
    }

    /// `CGPDFDocument.unlockWithPassword` has existed since iOS 2.0, so unlike Android there is no version gate here
    /// and `isPasswordSupported` is unconditionally true.
    func isPasswordSupported() throws -> Bool {
        true
    }

    /// Test `isUnlocked`, never `isEncrypted`. A PDF encrypted with an *empty* user password -- permission
    /// restrictions only, no password to type, very common for invoices and statements -- is unlocked automatically
    /// by Core Graphics and reads fine. It is `isEncrypted == true` and `isUnlocked == true` at the same time, so
    /// rejecting on `isEncrypted` throws away readable documents.
    ///
    /// Try [password] only when the document did *not* come back already unlocked: `unlockWithPassword` on an
    /// already-unlocked document is pointless, and on a permissions-only PDF it would fail against the *owner*
    /// password and tell us nothing. A wrong password leaves `isUnlocked` false and surfaces as
    /// `.passwordProtected`, exactly as a missing one does -- Android's `PdfRenderer` cannot tell those two apart
    /// either, so neither platform promises to.
    private func unlocked(_ document: CGPDFDocument?, password: String?) throws -> CGPDFDocument {
        guard let document else { throw OpenFailure.invalid }
        if !document.isUnlocked, let password {
            _ = document.unlockWithPassword(password)
        }
        guard document.isUnlocked else { throw OpenFailure.passwordProtected }
        return document
    }

    func openDataDocument(data: Data, password: String?) throws -> CGPDFDocument {
        guard let provider = CGDataProvider(data: data as CFData) else { throw OpenFailure.invalid }
        return try unlocked(CGPDFDocument(provider), password: password)
    }

    func openFileDocument(pdfFilePath: String, password: String?) throws -> CGPDFDocument {
        try unlocked(CGPDFDocument(URL(fileURLWithPath: pdfFilePath) as CFURL), password: password)
    }

    func openAssetDocument(name: String, password: String?) throws -> CGPDFDocument {
        guard let path = Bundle.main.path(
            forResource: "Frameworks/App.framework/flutter_assets/" + name,
            ofType: ""
        ) else {
            throw OpenFailure.invalid
        }
        return try openFileDocument(pdfFilePath: path, password: password)
    }
}

enum PdfRenderError : Error {
  case operationFailed(String)
}

/// `@unchecked Sendable`: Flutter calls `copyPixelBuffer` from its own raster thread while `updateTex` runs on the
/// platform thread, so `pixBuf` is genuinely shared — and already guarded by `lock`. The remaining state is only
/// touched from the platform thread.
final class PdfPageTexture : NSObject, @unchecked Sendable {
  private var pixBuf : CVPixelBuffer?
  private let lock = NSLock()
  weak var registrar: FlutterPluginRegistrar?
  var texId: Int64 = 0
  var texWidth: Int = 0
  var texHeight: Int = 0

  init(registrar: FlutterPluginRegistrar?) {
    self.registrar = registrar
  }

  func resize(width: Int, height: Int) {
    if self.texWidth == width && self.texHeight == height {
      return
    }
    self.texWidth = width
    self.texHeight = height
  }

  func updateTex(
    page: CGPDFPage,
    destX: Int,
    destY: Int,
    width: Int,
    height: Int,
    srcX: Int,
    srcY: Int,
    fullWidth: Double?,
    fullHeight: Double?,
    backgroundColor: String?,
    allowAntialiasing: Bool = true
  ) throws {

    let rotatedSize = page.getRotatedSize()
    let fw = fullWidth ?? Double(rotatedSize.width)
    let fh = fullHeight ?? Double(rotatedSize.height)
    let sx = CGFloat(fw) / rotatedSize.width
    let sy = CGFloat(fh) / rotatedSize.height

    var pixBuf: CVPixelBuffer?
    let options = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:]
      ] as [String : Any]
    let cvRet = CVPixelBufferCreate(kCFAllocatorDefault, texWidth, texHeight, kCVPixelFormatType_32BGRA, options as CFDictionary?, &pixBuf)
    if pixBuf == nil {
      throw PdfRenderError.operationFailed("CVPixelBufferCreate failed: result code=\(cvRet)")
    }

    let lockFlags = CVPixelBufferLockFlags(rawValue: 0)
    let _ = CVPixelBufferLockBaseAddress(pixBuf!, lockFlags)
    defer {
      CVPixelBufferUnlockBaseAddress(pixBuf!, lockFlags)
    }

    let bufferAddress = CVPixelBufferGetBaseAddress(pixBuf!)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixBuf!)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: bufferAddress?.advanced(by: destX * 4 + destY * bytesPerRow),
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow,
                            space: rgbColorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)


    if backgroundColor != nil {
            context?.setFillColor(UIColor(hexString: backgroundColor!).cgColor)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    context?.setAllowsAntialiasing(allowAntialiasing)

    context?.translateBy(x: CGFloat(-srcX), y: CGFloat(Double(srcY + height) - fh))
    context?.scaleBy(x: sx, y: sy)
    context?.concatenate(page.getRotationTransform())
    context?.drawPDFPage(page)
    context?.flush()

    lock.lock()
    self.pixBuf = pixBuf
    lock.unlock()
      registrar?.textures().textureFrameAvailable(texId)
  }
}

extension PdfPageTexture : FlutterTexture {
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    let buf = pixBuf
    lock.unlock()
    return buf != nil ? Unmanaged<CVPixelBuffer>.passRetained(buf!) : nil
  }
}
