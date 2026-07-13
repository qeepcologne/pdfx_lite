package io.scer.pdfx.document

import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor

class Document (
    val id: String,
    private val documentRenderer: PdfRenderer,
    private val fileDescriptor: ParcelFileDescriptor
) {
    val pagesCount: Int get() = documentRenderer.pageCount

    fun close() {
        documentRenderer.close()
        fileDescriptor.close()
    }

    /**
     * Open page by page number (not index!)
     */
    fun openPage(pageNumber: Int): PdfRenderer.Page = documentRenderer.openPage(pageNumber - 1)
}
