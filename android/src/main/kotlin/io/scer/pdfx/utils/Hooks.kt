package io.scer.pdfx.utils

import android.graphics.Bitmap
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

fun InputStream.toFile(file: File) {
    file.outputStream().use { this.copyTo(it) }
}

/**
 * Save bitmap to file
 */
fun Bitmap.toFile(file: File, format: Int, quality: Int = 100): File {
    FileOutputStream(file, false).use { stream ->
        this.compress(parseCompressFormat(format, quality), quality, stream)
        stream.flush()
    }
    return file
}
