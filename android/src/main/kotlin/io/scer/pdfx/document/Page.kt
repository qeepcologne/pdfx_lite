package io.scer.pdfx.document

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import io.scer.pdfx.utils.toByteArray

/**
 * Render this page and return the encoded image bytes.
 *
 * An extension on the renderer's own page type rather than a class wrapping it: a page lives only for the duration of
 * one [Document.withPage] call, so there is nothing for a wrapper to own.
 */
fun PdfRenderer.Page.renderToByteArray(
    width: Int,
    height: Int,
    background: Int,
    format: Int,
    crop: Boolean,
    cropX: Int,
    cropY: Int,
    cropW: Int,
    cropH: Int,
    quality: Int,
    forPrint: Boolean
): PageImage {
    val bitmap = Bitmap.createBitmap(
        width,
        height,
        Bitmap.Config.ARGB_8888)
    bitmap.eraseColor(background)
    val mode = if (forPrint) PdfRenderer.Page.RENDER_MODE_FOR_PRINT else PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY
    render(bitmap, null, null, mode)

    if (crop && (cropW != width || cropH != height)) {
        val cropped = Bitmap.createBitmap(bitmap, cropX, cropY, cropW, cropH)
        return PageImage(
            cropW,
            cropH,
            cropped.toByteArray(format, quality)
        )
    } else {
        return PageImage(
            width,
            height,
            bitmap.toByteArray(format, quality)
        )
    }
}

data class PageImage(
    val width: Int,
    val height: Int,
    val bytes: ByteArray
)
