package io.scer.pdfx.utils

import android.graphics.Bitmap
import android.os.Build

/**
 * `Bitmap.CompressFormat.WEBP` is deprecated since API 30 in favour of the explicit `WEBP_LOSSLESS` / `WEBP_LOSSY`.
 * minSdk is 24, where those do not exist, so the deprecated constant stays as the pre-30 fallback.
 *
 * The split mirrors what the platform does for the deprecated constant: quality 100 means lossless.
 */
fun parseCompressFormat(format: Int, quality: Int): Bitmap.CompressFormat = when (format) {
    0 -> Bitmap.CompressFormat.JPEG
    1 -> Bitmap.CompressFormat.PNG
    2 -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        if (quality == 100) Bitmap.CompressFormat.WEBP_LOSSLESS else Bitmap.CompressFormat.WEBP_LOSSY
    } else {
        @Suppress("DEPRECATION")
        Bitmap.CompressFormat.WEBP
    }
    else -> Bitmap.CompressFormat.JPEG
}
