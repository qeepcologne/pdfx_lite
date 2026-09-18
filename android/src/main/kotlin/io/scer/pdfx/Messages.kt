package io.scer.pdfx

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.LoadParams
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import android.util.SparseArray
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.view.TextureRegistry
import io.flutter.view.TextureRegistry.SurfaceProducer.Callback
import io.scer.pdfx.document.renderToByteArray
import io.scer.pdfx.resources.DocumentRepository
import io.scer.pdfx.resources.RepositoryItemNotFoundException
import io.scer.pdfx.utils.randomFilename
import io.scer.pdfx.utils.toFile
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val CHANNEL = "pdf_renderer"

/**
 * The generic failure code, shared verbatim with iOS. Android previously reported [CHANNEL] ("pdf_renderer") here
 * while iOS reported "RENDER_ERROR", so a caller switching on `PlatformException.code` had to special-case both.
 */
private const val RENDER_ERROR = "RENDER_ERROR"

/**
 * The error code for an encrypted PDF whose password was absent or wrong, shared verbatim with iOS and with the Dart
 * side, which turns it into `PdfPasswordProtectedException`. [PdfRenderer] reports both cases as [SecurityException]
 * and does not distinguish them, so neither do we.
 *
 * Every other failure here reports [RENDER_ERROR].
 */
private const val PASSWORD_PROTECTED = "PDF_PASSWORD_PROTECTED"

/**
 * The error code for "a password was supplied, but this device cannot use one" — see [PasswordUnsupportedException].
 * The Dart side turns it into `PdfPasswordUnsupportedException`.
 */
private const val PASSWORD_UNSUPPORTED = "PDF_PASSWORD_UNSUPPORTED"

/**
 * The document really is encrypted and a `password` was supplied, but [PdfRenderer] only accepts one from API 35
 * ([Build.VERSION_CODES.VANILLA_ICE_CREAM]) via the [LoadParams] constructor overload. `minSdk` is 24, so this is
 * most devices in the field.
 *
 * We refuse rather than dropping the password silently. Ignoring it would leave the file on the one-argument
 * [PdfRenderer] constructor, which throws [SecurityException] on any encrypted PDF -- so a caller who supplied the
 * *correct* password would be told the document is password-protected, indistinguishable from having supplied the
 * wrong one, and would re-prompt forever. A silently-ignored `password` is the exact bug that got the parameter
 * removed in 3.0.0; failing loudly lets a caller fall back (to an external viewer, say) instead of chasing a
 * password that was never going to be read.
 *
 * Reaching API 30-34 is possible but not cheap: it needs [android.graphics.pdf.PdfRendererPreV], a separate class
 * with its own incompatible `Page` type, so the whole render path would have to abstract over both. See TODO.md.
 */
class PasswordUnsupportedException : Exception()

/**
 * [ParcelFileDescriptor.open] returned null. Its stub carries no `@NonNull`, so the contract permits this, but in
 * practice it signals failure by throwing [FileNotFoundException] -- so this is defensive, not a path we expect.
 * The failures that genuinely cannot build a renderer come from the [PdfRenderer] constructor: [IOException] for a
 * corrupt file, [SecurityException] for an encrypted one.
 */
class CreateRendererException : Exception()

class Messages(private val binding : FlutterPlugin.FlutterPluginBinding,
               private val documents: DocumentRepository) : PdfxApi {

    //Reused: allocating a Paint per texture update would allocate on every frame of a scroll.
    private val antiAliasPaint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG)

    private val surfaceProducers: SparseArray<TextureRegistry.SurfaceProducer> = SparseArray()
    private val documentStatesPerSurface: SparseArray<UpdateTextureMessage> = SparseArray()

    //One scope for the plugin's lifetime, cancelled on detach. Launching from a fresh CoroutineScope per call leaves
    //a render running after the engine goes away, which then replies on a dead channel.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Called from [PdfxPlugin.onDetachedFromEngine]. Abandons any in-flight render. */
    fun dispose() {
        scope.cancel()
        //The producers outlive the engine otherwise: only an explicit `unregisterTexture` from Dart ever released
        //them, which never arrives if the engine goes away first.
        for (i in 0 until surfaceProducers.size()) {
            surfaceProducers.valueAt(i).let {
                it.setCallback(null)
                it.release()
            }
        }
        surfaceProducers.clear()
        documentStatesPerSurface.clear()
    }

    /**
     * Parse a `#RRGGBB`/`#AARRGGBB` string, falling back instead of throwing.
     *
     * [Color.parseColor] throws on anything it cannot read, so a typo'd colour used to fail the whole render on
     * Android while iOS's `UIColor(hexString:)` quietly fell back and rendered. Now both degrade the same way.
     */
    private fun parseColorOrTransparent(value: String): Int = try {
        Color.parseColor(value)
    } catch (e: IllegalArgumentException) {
        Log.w(CHANNEL, "Unparseable backgroundColor '$value'; falling back to transparent")
        Color.TRANSPARENT
    }

    override fun isPasswordSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM

    override fun openDocumentData(
        message: OpenDataMessage,
        callback: (Result<OpenReply>) -> Unit
    ) {
        try {
            val documentRenderer = openDataDocument(message.data!!, message.password)
            val document = documents.register(documentRenderer)
            callback(Result.success(OpenReply(
                id = document.id,
                pagesCount = document.pagesCount.toLong(),
            )))
        } catch (e: PasswordUnsupportedException) {
            callback(Result.failure(FlutterError(
                PASSWORD_UNSUPPORTED,
                "Opening a password-protected PDF needs Android 15 (API 35); this device runs API ${Build.VERSION.SDK_INT}"
            )))
        } catch (e: SecurityException) {
            callback(Result.failure(FlutterError(PASSWORD_PROTECTED, "The PDF is password-protected")))
        } catch (e: IOException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Can't open file")))
        } catch (e: CreateRendererException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Can't create PDF renderer")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Unknown error")))
        }
    }

    override fun openDocumentFile(
        message: OpenPathMessage,
        callback: (Result<OpenReply>) -> Unit
    ) {
        try {
            val documentRenderer = openFileDocument(File(message.path!!), message.password)
            val document = documents.register(documentRenderer)
            callback(Result.success(OpenReply(
                id = document.id,
                pagesCount = document.pagesCount.toLong(),
            )))
        } catch (e: NullPointerException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Need call arguments: path")))
        } catch (e: FileNotFoundException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "File not found")))
        } catch (e: PasswordUnsupportedException) {
            callback(Result.failure(FlutterError(
                PASSWORD_UNSUPPORTED,
                "Opening a password-protected PDF needs Android 15 (API 35); this device runs API ${Build.VERSION.SDK_INT}"
            )))
        } catch (e: SecurityException) {
            callback(Result.failure(FlutterError(PASSWORD_PROTECTED, "The PDF is password-protected")))
        } catch (e: IOException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Can't open file")))
        } catch (e: CreateRendererException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Can't create PDF renderer")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Unknown error")))
        }
    }

    override fun openDocumentAsset(
        message: OpenPathMessage,
        callback: (Result<OpenReply>) -> Unit
    ) {
        try {
            val documentRenderer = openAssetDocument(message.path!!, message.password)
            val document = documents.register(documentRenderer)
            callback(Result.success(OpenReply(
                id = document.id,
                pagesCount = document.pagesCount.toLong(),
            )))
        } catch (e: NullPointerException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Need call arguments: path")))
        } catch (e: FileNotFoundException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "File not found")))
        } catch (e: PasswordUnsupportedException) {
            callback(Result.failure(FlutterError(
                PASSWORD_UNSUPPORTED,
                "Opening a password-protected PDF needs Android 15 (API 35); this device runs API ${Build.VERSION.SDK_INT}"
            )))
        } catch (e: SecurityException) {
            callback(Result.failure(FlutterError(PASSWORD_PROTECTED, "The PDF is password-protected")))
        } catch (e: IOException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Can't open file")))
        } catch (e: CreateRendererException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Can't create PDF renderer")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Unknown error")))
        }
    }

    override fun closeDocument(message: IdMessage) {
        val id = message.id ?: throw FlutterError(RENDER_ERROR, "Need call arguments: id!")
        try {
            documents.close(id)
        } catch (e: RepositoryItemNotFoundException) {
            //Idempotent, matching iOS, which simply drops the key. Closing an already-closed document was an
            //exception here and a no-op there for the very same call.
        } catch (e: Exception) {
            throw FlutterError(RENDER_ERROR, "Unknown error")
        }
    }

    override fun getPage(
        message: GetPageMessage,
        callback: (Result<GetPageReply>) -> Unit
    ) {
        try {
            val documentId = message.documentId!!
            val pageNumber = message.pageNumber!!.toInt()

            val reply = documents.get(documentId).withPage(pageNumber) { page ->
                GetPageReply(
                    width = page.width.toDouble(),
                    height = page.height.toDouble(),
                )
            }

            callback(Result.success(reply))
        } catch (e: NullPointerException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Need call arguments: documentId & page!")))
        } catch (e: RepositoryItemNotFoundException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Document not exist in documents")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Unknown error")))
        }
    }

    override fun renderPage(
        message: RenderPageMessage,
        callback: (Result<RenderPageReply>) -> Unit
    ) {
        scope.launch {
            try {
                val documentId = message.documentId ?: run {
                    withContext(Dispatchers.Main) {
                        callback(Result.failure(FlutterError(RENDER_ERROR, "Document ID is null")))
                    }
                    return@launch
                }

                val pageNumber = message.pageNumber?.toInt() ?: run {
                    withContext(Dispatchers.Main) {
                        callback(Result.failure(FlutterError(RENDER_ERROR, "Page number is null")))
                    }
                    return@launch
                }

                val width = message.width?.toInt() ?: run {
                    withContext(Dispatchers.Main) {
                        callback(Result.failure(FlutterError(RENDER_ERROR, "Width is null")))
                    }
                    return@launch
                }

                val height = message.height?.toInt() ?: run {
                    withContext(Dispatchers.Main) {
                        callback(Result.failure(FlutterError(RENDER_ERROR, "Height is null")))
                    }
                    return@launch
                }

                val format = message.format?.toInt() ?: 1
                val backgroundColor = message.backgroundColor
                val color = backgroundColor?.let { parseColorOrTransparent(it) } ?: Color.TRANSPARENT

                val crop = message.crop ?: false
                val cropX = if (crop) message.cropX?.toInt() ?: 0 else 0
                val cropY = if (crop) message.cropY?.toInt() ?: 0 else 0
                val cropH = if (crop) message.cropHeight?.toInt() ?: 0 else 0
                val cropW = if (crop) message.cropWidth?.toInt() ?: 0 else 0

                val quality = message.quality?.toInt() ?: 100
                val forPrint = message.forPrint ?: false

                //  background thread render
                val pageImage = documents.get(documentId).withPage(pageNumber) { page ->
                    page.renderToByteArray(
                        width = width,
                        height = height,
                        background = color,
                        format = format,
                        crop = crop,
                        cropX = cropX,
                        cropY = cropY,
                        cropW = cropW,
                        cropH = cropH,
                        quality = quality,
                        forPrint = forPrint,
                    )
                }

                withContext(Dispatchers.Main) {
                    callback(Result.success(RenderPageReply(
                        width = pageImage.width.toLong(),
                        height = pageImage.height.toLong(),
                        bytes = pageImage.bytes,
                    )))
                }
            } catch (e: CancellationException) {
                //The scope was cancelled (engine detach); the channel is gone, so there is nobody to reply to.
                throw e
            } catch (e: Throwable) {
                //`Throwable`, not `Exception`: a large render fails with OutOfMemoryError, which is an Error -- and
                //letting it escape leaves the callback uninvoked and the Dart future pending forever.
                withContext(Dispatchers.Main) {
                    callback(Result.failure(FlutterError(RENDER_ERROR, "Unexpected error", e.toString())))
                }
            }
        }
    }

    override fun registerTexture(): RegisterTextureReply {
        val surfaceProducer = binding.textureRegistry.createSurfaceProducer()
        val id = surfaceProducer.id().toInt()
        surfaceProducers.put(id, surfaceProducer)

        surfaceProducer.setCallback(object : Callback {
            override fun onSurfaceAvailable() {
                documentStatesPerSurface[id]?.let { documentUpdate ->
                    onDocumentOrSurfaceChanged(
                        surfaceProducer.surface,
                        documentUpdate,
                        callback = null,
                    )
                }
            }

            override fun onSurfaceCleanup() {
                // ignore - Surface is used once to draw bitmap
            }
        })

        return RegisterTextureReply(id = id.toLong())
    }

    override fun updateTexture(
        message: UpdateTextureMessage,
        callback: (Result<Unit>) -> Unit
    ) {
        //Everything is inside the try: pigeon generates no error handling around an @async host method, so an
        //exception escaping here means the reply is never sent and the Dart future hangs forever.
        try {
            val texId = message.textureId?.toInt()
                ?: return callback(Result.failure(FlutterError(RENDER_ERROR, "Need call arguments: textureId")))
            val surfaceProducer = surfaceProducers[texId]
                ?: return callback(Result.failure(FlutterError(RENDER_ERROR, "No texture of texId=$texId")))

            //Optional on the wire, and iOS simply skips the resize when they are absent -- so must we, rather than
            //throwing on a call the schema permits.
            val texWidth = message.textureWidth?.toInt() ?: 0
            val texHeight = message.textureHeight?.toInt() ?: 0
            if (texWidth != 0 && texHeight != 0) {
                surfaceProducer.setSize(texWidth, texHeight)
            }
            documentStatesPerSurface.put(texId, message)
            onDocumentOrSurfaceChanged(surfaceProducer.surface, message, callback)
        } catch (e: RepositoryItemNotFoundException) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "Document not exist in documents repository")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "updateTexture failed", e.toString())))
        }
    }

    private fun onDocumentOrSurfaceChanged(
        surface: Surface,
        message: UpdateTextureMessage,
        callback: ((Result<Unit>) -> Unit)?,
    ) {
        val pageNumber = message.pageNumber!!.toInt()
        val document = documents.get(message.documentId!!)
        document.withPage(pageNumber) { page ->
            val fullWidth = message.fullWidth ?: page.width.toDouble()
            val fullHeight = message.fullHeight ?: page.height.toDouble()
            //Defaulted, not force-unwrapped: the schema declares all of these optional and iOS defaults them, so a
            //call that succeeds there must not throw here.
            val destX = message.destinationX?.toInt() ?: 0
            val destY = message.destinationY?.toInt() ?: 0
            val width = message.width?.toInt() ?: 0
            val height = message.height?.toInt() ?: 0
            val srcX = message.sourceX?.toInt() ?: 0
            val srcY = message.sourceY?.toInt() ?: 0
            val backgroundColor = message.backgroundColor
            val allowAntiAliasing = message.allowAntiAliasing ?: true

            if (width <= 0 || height <= 0) {
                //`return@withPage`, not a bare call: without it execution fell through into `createBitmap(0, 0)`,
                //which throws, and the catch below invoked the callback a *second* time -- which the engine rejects.
                callback?.invoke(Result.failure(FlutterError(RENDER_ERROR, "updateTexture width/height == 0")))
                return@withPage
            }

            val mat = Matrix()
            mat.setValues(floatArrayOf((fullWidth / page.width).toFloat(), 0f, -srcX.toFloat(), 0f, (fullHeight / page.height).toFloat(), -srcY.toFloat(), 0f, 0f, 1f))

            var bmp: Bitmap? = null
            try {
                bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                if (backgroundColor != null) {
                    bmp.eraseColor(parseColorOrTransparent(backgroundColor))
                }
                page.render(bmp, null, mat, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                //The surface belongs to the SurfaceProducer, which reuses it for the texture's whole lifetime -- so
                //it must NOT be released here. Doing so forced the engine to reallocate an ImageReader and its
                //buffers on every single update, i.e. on every frame of a scroll or pinch.
                val canvas = surface.lockCanvas(Rect(destX, destY, destX + width, destY + height))
                try {
                    //`Rect` is (left, top, right, bottom): passing (destX, destY, width, height) clipped the region
                    //for any non-zero destination.
                    val paint = if (allowAntiAliasing) antiAliasPaint else null
                    canvas.drawBitmap(bmp, destX.toFloat(), destY.toFloat(), paint)
                } finally {
                    surface.unlockCanvasAndPost(canvas)
                }
                callback?.invoke(Result.success(Unit))
            } catch (e: Exception) {
                callback?.invoke(Result.failure(FlutterError(RENDER_ERROR, "updateTexture failed", e.toString())))
            } finally {
                bmp?.recycle()
            }
        }
    }

    override fun resizeTexture(
        message: ResizeTextureMessage,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val texId = message.textureId?.toInt()
                ?: return callback(Result.failure(FlutterError(RENDER_ERROR, "Need call arguments: textureId")))
            val width = message.width?.toInt()
                ?: return callback(Result.failure(FlutterError(RENDER_ERROR, "Need call arguments: width")))
            val height = message.height?.toInt()
                ?: return callback(Result.failure(FlutterError(RENDER_ERROR, "Need call arguments: height")))
            //An unknown id used to report success here while iOS reported failure for the same call.
            val tex = surfaceProducers[texId]
                ?: return callback(Result.failure(FlutterError(RENDER_ERROR, "No texture of texId=$texId")))
            tex.setSize(width, height)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(RENDER_ERROR, "resizeTexture failed", e.toString())))
        }
    }

    override fun unregisterTexture(message: UnregisterTextureMessage) {
        val id = message.id!!.toInt()
        val surfaceProducer = surfaceProducers[id]
        surfaceProducer?.setCallback(null)
        surfaceProducer?.release()
        surfaceProducers.remove(id)
        //Also drop the retained UpdateTextureMessage: the registry reuses texture ids, so a later texture with the
        //same id would have had `onSurfaceAvailable` redraw the *previous* texture's page.
        documentStatesPerSurface.remove(id)
    }

    private fun openDataDocument(data: ByteArray, password: String?): Pair<ParcelFileDescriptor, PdfRenderer> {
        val tempDataFile = File(binding.applicationContext.cacheDir, "$randomFilename.pdf")
        tempDataFile.writeBytes(data)
        Log.d(CHANNEL, "OpenDataDocument. Created file: " + tempDataFile.path)
        return openTempFileDocument(tempDataFile, password)
    }

    private fun openAssetDocument(assetPath: String, password: String?): Pair<ParcelFileDescriptor, PdfRenderer> {
        val fullAssetPath = binding.flutterAssets.getAssetFilePathByName(assetPath)
        val tempAssetFile = File(binding.applicationContext.cacheDir, "$randomFilename.pdf")
        binding.applicationContext.assets.open(fullAssetPath).use { it.toFile(tempAssetFile) }
        Log.d(CHANNEL, "OpenAssetDocument. Created file: " + tempAssetFile.path)
        return openTempFileDocument(tempAssetFile, password)
    }

    /**
     * Open a document from a file this plugin just wrote to `cacheDir`, and unlink the file straight away.
     *
     * The descriptor keeps the inode alive for as long as the renderer needs it, so deleting the name now is safe --
     * and it is the only thing that stops `cacheDir` growing by the full size of every document ever opened from
     * data or assets. The name was a fresh UUID each time, so nothing ever reused or cleaned these up.
     */
    private fun openTempFileDocument(file: File, password: String?): Pair<ParcelFileDescriptor, PdfRenderer> {
        try {
            return openFileDocument(file, password)
        } finally {
            file.delete()
        }
    }

    /**
     * [password] is a *fallback*, used only if the document actually demands one -- so we always try the plain
     * constructor first, and reach for [LoadParams] only once that has been refused.
     *
     * Trying [LoadParams] up front instead would be wrong. It validates the password unconditionally, so a document
     * encrypted with an *empty* user password (permission restrictions only -- no printing or copying, the common
     * shape for invoices and statements) opens happily with no password yet fails with [SecurityException] when one
     * is supplied. A caller holding a remembered password would then break the very documents that needed none.
     * Verified on API 37: `perms_only.pdf` opens with no password and throws with one.
     *
     * iOS behaves this way for free -- `unlockWithPassword` is only called there when the document did not already
     * come back unlocked -- so this keeps the two platforms honest with each other.
     *
     * Throws [SecurityException] if the document is encrypted and [password] is absent or wrong,
     * [PasswordUnsupportedException] if it is encrypted and [password] was given but this device cannot use one,
     * [IOException] if the file is corrupt.
     */
    private fun openFileDocument(file: File, password: String?): Pair<ParcelFileDescriptor, PdfRenderer> {
        Log.d(CHANNEL, "OpenFileDocument. File: " + file.path) //Never log `password`.

        try {
            return newRenderer(file) { PdfRenderer(it) }
        } catch (e: SecurityException) {
            //Encrypted, and no password to try: report it as-is.
            if (password == null) throw e
        }

        if (!isPasswordSupported()) throw PasswordUnsupportedException()
        return newRenderer(file) { withPassword(it, password!!) }
    }

    /** Isolated so the API-35-only [LoadParams] is never touched by a method that runs on older devices. */
    private fun withPassword(fd: ParcelFileDescriptor, password: String): PdfRenderer =
        PdfRenderer(fd, LoadParams.Builder().setPassword(password).build())

    /**
     * [PdfRenderer] only takes ownership of the descriptor once it has been constructed; if it throws, closing it is
     * on us. That was a leak nobody ever hit, because a throw here used to mean a corrupt file. It matters now: a
     * wrong password throws [SecurityException], so a caller re-prompting the user would leak a descriptor per
     * attempt, and the retry above opens a second one by design.
     */
    private inline fun newRenderer(
        file: File,
        make: (ParcelFileDescriptor) -> PdfRenderer
    ): Pair<ParcelFileDescriptor, PdfRenderer> {
        val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            ?: throw CreateRendererException()
        try {
            return Pair(fd, make(fd))
        } catch (e: Throwable) {
            fd.close()
            throw e
        }
    }
}
