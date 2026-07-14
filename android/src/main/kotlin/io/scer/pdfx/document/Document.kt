package io.scer.pdfx.document

import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor

class Document (
    val id: String,
    private val documentRenderer: PdfRenderer,
    private val fileDescriptor: ParcelFileDescriptor
) {
    /**
     * `PdfRenderer` permits only one open page per document: a second `openPage` while one is still open throws
     * `IllegalStateException("Current page not closed")`. Closing the document with a page open throws too.
     *
     * Not theoretical. `renderPage` runs on a background coroutine while `updateTexture` runs on the platform thread,
     * so they genuinely overlap: on an Android 14 device, a large render running concurrently with texture updates
     * fails *every one* of them without this lock. A newer `PdfRenderer` (seen on an API 37 emulator) tolerates two
     * open pages and shows no such failure — which is exactly why the lock must stay: the devices in the field are
     * the strict ones.
     */
    private val lock = Any()

    val pagesCount: Int get() = documentRenderer.pageCount

    fun close() = synchronized(lock) {
        documentRenderer.close()
        fileDescriptor.close()
    }

    /**
     * Open page [pageNumber] (not index!), hand it to [block], and close it again.
     *
     * A page is never held past a single call — that is what [lock] enforces. iOS carries no such restriction but
     * follows the same open-use-close shape, so that both platforms behave identically.
     */
    fun <T> withPage(pageNumber: Int, block: (PdfRenderer.Page) -> T): T = synchronized(lock) {
        documentRenderer.openPage(pageNumber - 1).use(block)
    }
}
