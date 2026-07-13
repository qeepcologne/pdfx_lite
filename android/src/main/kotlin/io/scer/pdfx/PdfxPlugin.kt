package io.scer.pdfx

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.scer.pdfx.resources.DocumentRepository
import io.scer.pdfx.resources.PageRepository

/**
 * PdfxPlugin
 */
class PdfxPlugin : FlutterPlugin {
    private val documents = DocumentRepository()
    private val pages = PageRepository()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        PdfxApi.setUp(
            flutterPluginBinding.binaryMessenger,
            Messages(flutterPluginBinding, documents, pages)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PdfxApi.setUp(binding.binaryMessenger, null)
        documents.clear()
        pages.clear()
    }
}

