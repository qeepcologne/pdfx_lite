package io.scer.pdfx.resources

import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.scer.pdfx.document.Document
import io.scer.pdfx.utils.randomID

class DocumentRepository : Repository<Document>() {
    /**
     * Register document in repository
     * @returns document id
     */
    fun register(getPair: Pair<ParcelFileDescriptor, PdfRenderer>?): Document {
        val id = randomID
        val (fileDescriptor, renderer) = getPair!!
        val document = Document(id, renderer, fileDescriptor)
        set(id, document)
        return document
    }

    public override fun close(id: String) {
        get(id).close()
        super.close(id)
    }

    /**
     * Close every open document, then empty the map.
     *
     * The inherited `clear()` only dropped the references, leaking each document's `PdfRenderer` and its file
     * descriptor on every engine detach.
     */
    override fun clear() {
        for (document in drain()) {
            try {
                document.close()
            } catch (e: Exception) {
                //Best effort: one document failing to close must not strand the rest.
            }
        }
    }
}
