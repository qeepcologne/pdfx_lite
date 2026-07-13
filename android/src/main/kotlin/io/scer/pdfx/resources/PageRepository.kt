package io.scer.pdfx.resources

import android.graphics.pdf.PdfRenderer
import io.scer.pdfx.document.Page
import io.scer.pdfx.utils.randomID

class PageRepository : Repository<Page>() {
    /**
     * Register page in repository
     * @returns page id
     */
    fun register(pageRenderer: PdfRenderer.Page): Page {
        val id = randomID
        val page = Page(id, pageRenderer)
        set(id, page)
        return page
    }

    public override fun close(id: String) {
        get(id).close()
        super.close(id)
    }
}
