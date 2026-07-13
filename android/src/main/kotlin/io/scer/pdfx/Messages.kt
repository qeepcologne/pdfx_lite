package io.scer.pdfx

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.Log
import android.util.SparseArray
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.view.TextureRegistry
import io.flutter.view.TextureRegistry.SurfaceProducer.Callback
import io.scer.pdfx.resources.DocumentRepository
import io.scer.pdfx.resources.PageRepository
import io.scer.pdfx.resources.RepositoryItemNotFoundException
import io.scer.pdfx.utils.CreateRendererException
import io.scer.pdfx.utils.randomFilename
import io.scer.pdfx.utils.toFile
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val CHANNEL = "pdf_renderer"

class Messages(private val binding : FlutterPlugin.FlutterPluginBinding,
               private val documents: DocumentRepository,
               private val pages: PageRepository) : PdfxApi {

    private val surfaceProducers: SparseArray<TextureRegistry.SurfaceProducer> = SparseArray()
    private val documentStatesPerSurface: SparseArray<UpdateTextureMessage> = SparseArray()

    //One scope for the plugin's lifetime, cancelled on detach. Launching from a fresh CoroutineScope per call leaves
    //a render running after the engine goes away, which then replies on a dead channel.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Called from [PdfxPlugin.onDetachedFromEngine]. Abandons any in-flight render. */
    fun dispose() {
        scope.cancel()
    }

    override fun openDocumentData(
        message: OpenDataMessage,
        callback: (Result<OpenReply>) -> Unit
    ) {
        try {
            val documentRenderer = openDataDocument(message.data!!)
            val document = documents.register(documentRenderer)
            callback(Result.success(OpenReply(
                id = document.id,
                pagesCount = document.pagesCount.toLong(),
            )))
        } catch (e: IOException) {
            callback(Result.failure(FlutterError(CHANNEL, "Can't open file")))
        } catch (e: CreateRendererException) {
            callback(Result.failure(FlutterError(CHANNEL, "Can't create PDF renderer")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(CHANNEL, "Unknown error")))
        }
    }

    override fun openDocumentFile(
        message: OpenPathMessage,
        callback: (Result<OpenReply>) -> Unit
    ) {
        try {
            val documentRenderer = openFileDocument(File(message.path!!))
            val document = documents.register(documentRenderer)
            callback(Result.success(OpenReply(
                id = document.id,
                pagesCount = document.pagesCount.toLong(),
            )))
        } catch (e: NullPointerException) {
            callback(Result.failure(FlutterError(CHANNEL, "Need call arguments: path")))
        } catch (e: FileNotFoundException) {
            callback(Result.failure(FlutterError(CHANNEL, "File not found")))
        } catch (e: IOException) {
            callback(Result.failure(FlutterError(CHANNEL, "Can't open file")))
        } catch (e: CreateRendererException) {
            callback(Result.failure(FlutterError(CHANNEL, "Can't create PDF renderer")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(CHANNEL, "Unknown error")))
        }
    }

    override fun openDocumentAsset(
        message: OpenPathMessage,
        callback: (Result<OpenReply>) -> Unit
    ) {
        try {
            val documentRenderer = openAssetDocument(message.path!!)
            val document = documents.register(documentRenderer)
            callback(Result.success(OpenReply(
                id = document.id,
                pagesCount = document.pagesCount.toLong(),
            )))
        } catch (e: NullPointerException) {
            callback(Result.failure(FlutterError(CHANNEL, "Need call arguments: path")))
        } catch (e: FileNotFoundException) {
            callback(Result.failure(FlutterError(CHANNEL, "File not found")))
        } catch (e: IOException) {
            callback(Result.failure(FlutterError(CHANNEL, "Can't open file")))
        } catch (e: CreateRendererException) {
            callback(Result.failure(FlutterError(CHANNEL, "Can't create PDF renderer")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(CHANNEL, "Unknown error")))
        }
    }

    override fun closeDocument(message: IdMessage) {
        try {
            documents.close(message.id!!)
        } catch (e: NullPointerException) {
            throw FlutterError(CHANNEL, "Need call arguments: id!")
        } catch (e: RepositoryItemNotFoundException) {
            throw FlutterError(CHANNEL, "Document not exist in documents repository")
        } catch (e: Exception) {
            throw FlutterError(CHANNEL, "Unknown error")
        }
    }

    override fun getPage(
        message: GetPageMessage,
        callback: (Result<GetPageReply>) -> Unit
    ) {
        try {
            val documentId = message.documentId!!
            val pageNumber = message.pageNumber!!.toInt()

            val reply = if (message.autoCloseAndroid!!) {
                documents.get(documentId).openPage(pageNumber).use { page ->
                    GetPageReply(
                        width = page.width.toDouble(),
                        height = page.height.toDouble(),
                    )
                }
            } else {
                val pageRenderer = documents.get(documentId).openPage(pageNumber)
                val page = pages.register(pageRenderer)
                GetPageReply(
                    id = page.id,
                    width = page.width.toDouble(),
                    height = page.height.toDouble(),
                )
            }

            callback(Result.success(reply))
        } catch (e: NullPointerException) {
            callback(Result.failure(FlutterError(CHANNEL, "Need call arguments: documentId & page!")))
        } catch (e: RepositoryItemNotFoundException) {
            callback(Result.failure(FlutterError(CHANNEL, "Document not exist in documents")))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError(CHANNEL, "Unknown error")))
        }
    }

    override fun renderPage(
        message: RenderPageMessage,
        callback: (Result<RenderPageReply>) -> Unit
    ) {
        scope.launch {
            try {
                val pageId = message.pageId ?: run {
                    callback(Result.failure(FlutterError(CHANNEL, "Page ID is null")))
                    return@launch
                }

                val width = message.width?.toInt() ?: run {
                    callback(Result.failure(FlutterError(CHANNEL, "Width is null")))
                    return@launch
                }

                val height = message.height?.toInt() ?: run {
                    callback(Result.failure(FlutterError(CHANNEL, "Height is null")))
                    return@launch
                }

                val format = message.format?.toInt() ?: 1
                val backgroundColor = message.backgroundColor
                val color = backgroundColor?.let { Color.parseColor(it) } ?: Color.TRANSPARENT

                val crop = message.crop ?: false
                val cropX = if (crop) message.cropX?.toInt() ?: 0 else 0
                val cropY = if (crop) message.cropY?.toInt() ?: 0 else 0
                val cropH = if (crop) message.cropHeight?.toInt() ?: 0 else 0
                val cropW = if (crop) message.cropWidth?.toInt() ?: 0 else 0

                val quality = message.quality?.toInt() ?: 100
                val forPrint = message.forPrint ?: false

                val page = pages.get(pageId)

                val tempOutFileExtension = when (format) {
                    0 -> "jpg"
                    1 -> "png"
                    2 -> "webp"
                    else -> "jpg"
                }

                val tempOutFolder = File(binding.applicationContext.cacheDir, "pdf_renderer_cache").apply {
                    mkdirs()
                }

                val tempOutFile = File(tempOutFolder, "$randomFilename.$tempOutFileExtension")

                //  background thread render
                val pageImage = page.render(
                    file = tempOutFile,
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

                withContext(Dispatchers.Main) {
                    callback(Result.success(RenderPageReply(
                        width = pageImage.width.toLong(),
                        height = pageImage.height.toLong(),
                        path = pageImage.path,
                    )))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.failure(FlutterError(CHANNEL, "Unexpected error", e.toString())))
                }
            }
        }
    }

    override fun closePage(message: IdMessage) {
        try {
            pages.close(message.id!!)
        } catch (e: NullPointerException) {
            throw FlutterError(CHANNEL, "Need call arguments: id!")
        } catch (e: RepositoryItemNotFoundException) {
            throw FlutterError(CHANNEL, "Page not exist in pages repository")
        } catch (e: Exception) {
            throw FlutterError(CHANNEL, "Unknown error")
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
        val texId = message.textureId!!.toInt()
        val surfaceProducer = surfaceProducers[texId]
        val texWidth = message.textureWidth!!.toInt()
        val texHeight = message.textureHeight!!.toInt()
        if (texWidth != 0 && texHeight != 0) {
            surfaceProducer.setSize(texWidth, texHeight)
        }
        documentStatesPerSurface.put(texId, message)
        onDocumentOrSurfaceChanged(surfaceProducer.surface, message, callback)
    }

    private fun onDocumentOrSurfaceChanged(
        surface: Surface,
        message: UpdateTextureMessage,
        callback: ((Result<Unit>) -> Unit)?,
    ) {
        val pageNumber = message.pageNumber!!.toInt()
        val document = documents.get(message.documentId!!)
        document.openPage(pageNumber).use { page ->
            val fullWidth = message.fullWidth ?: page.width.toDouble()
            val fullHeight = message.fullHeight ?: page.height.toDouble()
            val destX = message.destinationX!!.toInt()
            val destY = message.destinationY!!.toInt()
            val width = message.width!!.toInt()
            val height = message.height!!.toInt()
            val srcX = message.sourceX!!.toInt()
            val srcY = message.sourceY!!.toInt()
            val backgroundColor = message.backgroundColor

            if (width <= 0 || height <= 0) {
                callback?.invoke(Result.failure(FlutterError(CHANNEL, "updateTexture width/height == 0")))
            }

            val mat = Matrix()
            mat.setValues(floatArrayOf((fullWidth / page.width).toFloat(), 0f, -srcX.toFloat(), 0f, (fullHeight / page.height).toFloat(), -srcY.toFloat(), 0f, 0f, 1f))

            try {
                val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                if (backgroundColor != null) {
                    bmp.eraseColor(Color.parseColor(backgroundColor))
                }
                page.render(bmp, null, mat, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                surface.use {
                    val canvas = it.lockCanvas(Rect(destX, destY, width, height))

                    canvas.drawBitmap(bmp, destX.toFloat(), destY.toFloat(), null)
                    bmp.recycle()

                    it.unlockCanvasAndPost(canvas)
                }
                callback?.invoke(Result.success(Unit))
            } catch (e: Exception) {
                callback?.invoke(Result.failure(FlutterError(CHANNEL, "updateTexture Unknown error")))
            }
        }
    }

    override fun resizeTexture(
        message: ResizeTextureMessage,
        callback: (Result<Unit>) -> Unit
    ) {
        val texId = message.textureId!!.toInt()
        val width = message.width!!.toInt()
        val height = message.height!!.toInt()
        val tex = surfaceProducers[texId]
        tex?.setSize(width, height)
        callback(Result.success(Unit))
    }

    override fun unregisterTexture(message: UnregisterTextureMessage) {
        val id = message.id!!.toInt()
        val surfaceProducer = surfaceProducers[id]
        surfaceProducer?.setCallback(null)
        surfaceProducer?.release()
        surfaceProducers.remove(id)
    }

    private fun openDataDocument(data: ByteArray): Pair<ParcelFileDescriptor, PdfRenderer> {
        val tempDataFile = File(binding.applicationContext.cacheDir, "$randomFilename.pdf")
        if (!tempDataFile.exists()) {
            tempDataFile.writeBytes(data)
        }
        Log.d(CHANNEL, "OpenDataDocument. Created file: " + tempDataFile.path)
        return openFileDocument(tempDataFile)
    }

    private fun openAssetDocument(assetPath: String): Pair<ParcelFileDescriptor, PdfRenderer> {
        val fullAssetPath = binding.flutterAssets.getAssetFilePathByName(assetPath)
        val tempAssetFile = File(binding.applicationContext.cacheDir, "$randomFilename.pdf")
        if (!tempAssetFile.exists()) {
            val inputStream = binding.applicationContext.assets.open(fullAssetPath)
            inputStream.toFile(tempAssetFile)
            inputStream.close()
        }
        Log.d(CHANNEL, "OpenAssetDocument. Created file: " + tempAssetFile.path)
        return openFileDocument(tempAssetFile)
    }

    private fun openFileDocument(file: File): Pair<ParcelFileDescriptor, PdfRenderer> {
        Log.d(CHANNEL, "OpenFileDocument. File: " + file.path)
        val fileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        return if (fileDescriptor != null) {
            val pdfRenderer = PdfRenderer(fileDescriptor)
            Pair(fileDescriptor, pdfRenderer)
        } else throw CreateRendererException()
    }
}

fun <R> Surface.use(block: (Surface) -> R): R {
    try {
        return block(this)
    }
    finally {
        this.release()
    }
}
