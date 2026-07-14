package io.scer.pdfx

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.scer.pdfx.resources.DocumentRepository

/**
 * PdfxPlugin
 */
class PdfxPlugin : FlutterPlugin {
    private val documents = DocumentRepository()
    private var messages: Messages? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val messages = Messages(flutterPluginBinding, documents)
        this.messages = messages
        PdfxApi.setUp(flutterPluginBinding.binaryMessenger, messages)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PdfxApi.setUp(binding.binaryMessenger, null)
        messages?.dispose()
        messages = null
        documents.clear()
    }
}
