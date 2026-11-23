package com.shoo.app.features.pairing

import android.graphics.Bitmap
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/**
 * GD-04: the invite link as a QR code, drawn on device (zxing core, iOS CoreImage), never fetched. Black modules on
 * white, `scale` pixels per module; draw it with `FilterQuality.None` (iOS `.interpolation(.none)`).
 * iOS `CIQRCodeGenerator` adds a one-module quiet zone; so does this.
 */
object QRCode {
    fun image(text: String, scale: Float = 12f): ImageBitmap? {
        return try {
            val hints = mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
                EncodeHintType.MARGIN to 1,
                EncodeHintType.CHARACTER_SET to "UTF-8",
            )
            val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, hints)
            val step = scale.toInt().coerceAtLeast(1)
            val side = matrix.width * step
            val pixels = IntArray(side * side)
            for (y in 0 until side) {
                val row = y / step
                for (x in 0 until side) {
                    pixels[y * side + x] = if (matrix.get(x / step, row)) BLACK else WHITE
                }
            }
            Bitmap.createBitmap(pixels, side, side, Bitmap.Config.ARGB_8888).asImageBitmap()
        } catch (_: Exception) {
            null
        }
    }

    private const val BLACK = 0xFF000000.toInt()
    private const val WHITE = 0xFFFFFFFF.toInt()
}
