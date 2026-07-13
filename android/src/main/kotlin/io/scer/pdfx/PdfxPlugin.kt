package io.scer.pdfx

import androidx.annotation.NonNull
import dev.flutter.pigeon.Pigeon
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.scer.pdfx.resources.DocumentRepository
import io.scer.pdfx.resources.PageRepository

/**
 * PdfxPlugin
 */
class PdfxPlugin : FlutterPlugin {
    private val documents = DocumentRepository()
    private val pages = PageRepository()

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Pigeon.PdfxApi.setup(
            flutterPluginBinding.binaryMessenger,
            Messages(flutterPluginBinding, documents, pages)
        )
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Pigeon.PdfxApi.setup(binding.binaryMessenger, null)
        documents.clear()
        pages.clear()
    }
}

