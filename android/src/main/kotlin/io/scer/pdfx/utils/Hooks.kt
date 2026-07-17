package io.scer.pdfx.utils

import android.graphics.Bitmap
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream

fun InputStream.toFile(file: File) {
    file.outputStream().use { this.copyTo(it) }
}

/**
 * Encode bitmap to a byte array in the requested format. Returned straight over the pigeon bridge, no temp file.
 */
fun Bitmap.toByteArray(format: Int, quality: Int = 100): ByteArray =
    ByteArrayOutputStream().use { stream ->
        this.compress(parseCompressFormat(format, quality), quality, stream)
        stream.toByteArray()
    }
