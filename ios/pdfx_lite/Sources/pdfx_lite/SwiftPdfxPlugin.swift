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

/// `@unchecked Sendable`: `textures` is only touched on the platform thread (no pigeon task queue is set, so every
/// generated handler runs there), `registrar`/`dispQueue` are immutable, and the document map is lock-guarded by
/// `Repository` while each `CGPDFDocument` behind it is lock-guarded by `Document` itself — the latter matters,
/// because the repository's lock only ever protected the dictionary, not the documents it hands out.
/// Cannot be actor-isolated instead — the generated `PdfxApi` protocol is non-isolated, so an isolated type could
/// not conform to it.
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

    /// Release every document and texture when the engine goes away.
    ///
    /// Nothing else does: `documents` and `textures` are emptied only by an explicit `closeDocument` /
    /// `unregisterTexture` from Dart, which never arrives if the engine is torn down first (hot restart, or an
    /// add-to-app host dropping the engine). Each open `CGPDFDocument` retains the whole file's backing data.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        for texId in textures.keys {
            registrar.textures().unregisterTexture(texId)
        }
        textures.removeAll()
        documents.clear()
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
        guard let id = message.id else {
            throw renderError("Need call arguments: id!")
        }
        //Idempotent on both platforms: closing an unknown or already-closed id is a no-op, not an error.
        documents.close(id: id)
    }

    func getPage(message: GetPageMessage, completion: @escaping (Result<GetPageReply, Error>) -> Void) {
        guard let documentId = message.documentId, let pageNumber = message.pageNumber else {
            return completion(.failure(renderError("Need call arguments: documentId & pageNumber")))
        }
        do {
            let reply = try documents.get(id: documentId).withPage(pageNumber: Int(pageNumber)) { page in
                GetPageReply(width: page.width, height: page.height)
            }
            guard let reply else {
                return completion(.failure(renderError("No page \(pageNumber) in document")))
            }

            completion(.success(reply))
        } catch let err {
            completion(.failure(renderError("Unexpected error: \(err).")))
        }
    }

    func renderPage(message: RenderPageMessage, completion: @escaping (Result<RenderPageReply, Error>) -> Void) {
        guard let documentId = message.documentId,
              let pageNumber = message.pageNumber,
              let width = message.width,
              let height = message.height else {
            return completion(.failure(renderError("Missing render arguments")))
        }
        //Defaulted to match Android, which has always defaulted these. The schema declares them optional, so a call
        //that Android renders must not fail outright here.
        let format = message.format ?? Int64(CompressFormat.PNG.rawValue)
        let backgroundColor = message.backgroundColor ?? "#00FFFFFF"
        let quality = message.quality ?? 100
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
                //The whole render happens under the document's lock, so it cannot overlap a texture update touching
                //the same CGPDFDocument from the platform thread.
                let rendered = try self.documents.get(id: documentId).withPage(pageNumber: Int(pageNumber)) { page in
                    page.render(
                        width: Int(width),
                        height: Int(height),
                        crop: cropZone,
                        compressFormat: compressFormat,
                        backgroundColor: backgroundColor,
                        quality: Int(quality)
                    )
                }
                guard let rendered else {
                    return DispatchQueue.main.async {
                        boxed.value(.failure(renderError("No page \(pageNumber) in document")))
                    }
                }
                guard let data = rendered else {
                    return DispatchQueue.main.async {
                        boxed.value(.failure(renderError("Page render produced no image")))
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
        //`register` can start serving `copyPixelBuffer` immediately, so everything the texture needs must be set
        //before it is handed over — `texId` was previously assigned afterwards.
        let texId = registrar.textures().register(pageTex)
        pageTex.texId = texId
        textures[texId] = pageTex
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
            let drawn: Void? = try documents.get(id: documentId).withPage(pageNumber: Int(pageNumber)) { page in
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
            }
            guard drawn != nil else {
                return completion(.failure(renderError("No page \(pageNumber) in document")))
            }
            completion(.success(()))
        } catch {
            completion(.failure(renderError("Cannot render texture: \(error)")))
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
  /// Reused across updates of the same size. `updateTex` runs once per frame while pinch-zooming, and allocating a
  /// fresh several-megabyte buffer each time was pure churn; the pool hands the same memory back once the engine has
  /// released its reference.
  private var bufferPool: CVPixelBufferPool?
  private var poolWidth: Int = 0
  private var poolHeight: Int = 0
  weak var registrar: FlutterPluginRegistrar?
  var texId: Int64 = 0
  var texWidth: Int = 0
  var texHeight: Int = 0

  init(registrar: FlutterPluginRegistrar?) {
    self.registrar = registrar
  }

  /// A buffer of the current texture size, from the pool, recreating the pool when the size changes.
  private func obtainPixelBuffer() throws -> CVPixelBuffer {
    guard texWidth > 0, texHeight > 0 else {
      throw PdfRenderError.operationFailed("texture size not set (\(texWidth)x\(texHeight))")
    }
    if bufferPool == nil || poolWidth != texWidth || poolHeight != texHeight {
      let attrs = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        kCVPixelBufferWidthKey as String: texWidth,
        kCVPixelBufferHeightKey as String: texHeight,
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      ] as [String: Any]
      var pool: CVPixelBufferPool?
      let poolRet = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
      guard let pool else {
        throw PdfRenderError.operationFailed("CVPixelBufferPoolCreate failed: \(poolRet)")
      }
      bufferPool = pool
      poolWidth = texWidth
      poolHeight = texHeight
    }
    var buffer: CVPixelBuffer?
    let ret = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bufferPool!, &buffer)
    guard let buffer else {
      throw PdfRenderError.operationFailed("CVPixelBufferPoolCreatePixelBuffer failed: \(ret)")
    }
    return buffer
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

    let pixBuf = try obtainPixelBuffer()

    //The destination sub-rect must lie inside the buffer: `destX`/`destY`/`width`/`height` come straight from the
    //public `updateRect`, and CoreGraphics would otherwise write past the end of the pixel buffer.
    guard destX >= 0, destY >= 0, width > 0, height > 0,
          destX + width <= texWidth, destY + height <= texHeight else {
      throw PdfRenderError.operationFailed(
        "rect (\(destX),\(destY),\(width),\(height)) does not fit texture \(texWidth)x\(texHeight)")
    }

    let lockFlags = CVPixelBufferLockFlags(rawValue: 0)
    let _ = CVPixelBufferLockBaseAddress(pixBuf, lockFlags)

    let bufferAddress = CVPixelBufferGetBaseAddress(pixBuf)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixBuf)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: bufferAddress?.advanced(by: destX * 4 + destY * bytesPerRow),
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow,
                            space: rgbColorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)


    //A nil context used to be optional-chained into a series of no-ops and then reported as success, handing back a
    //blank texture with no error at all.
    guard let context else {
      CVPixelBufferUnlockBaseAddress(pixBuf, lockFlags)
      throw PdfRenderError.operationFailed("CGContext creation failed for \(width)x\(height)")
    }

    if let backgroundColor {
      context.setFillColor(UIColor(hexString: backgroundColor).cgColor)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    context.setAllowsAntialiasing(allowAntialiasing)

    context.translateBy(x: CGFloat(-srcX), y: CGFloat(Double(srcY + height) - fh))
    context.scaleBy(x: sx, y: sy)
    context.concatenate(page.getRotationTransform())
    context.drawPDFPage(page)
    context.flush()

    //Unlock BEFORE publishing: the engine's raster thread calls `copyPixelBuffer` as soon as it sees the buffer, and
    //it must not read one still locked for CPU access. The old `defer` released it only after both lines below.
    CVPixelBufferUnlockBaseAddress(pixBuf, lockFlags)

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
