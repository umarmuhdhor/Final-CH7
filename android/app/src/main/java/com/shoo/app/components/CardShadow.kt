package com.shoo.app.components

import android.os.Build
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** `Capsule()`: fully rounded ends. */
val CapsuleShape = RoundedCornerShape(50)

/**
 * SwiftUI `.shadow(color:radius:x:y:)` on a view of `shape`: a real blurred shadow drawn behind it.
 *
 * `radius` is SwiftUI's (half the Figma blur; Gaussian sigma ≈ radius). `spread` is Figma's (SwiftUI has none).
 * Put it before the background: `Modifier.shooShadow(…, shape = s).background(Color.White, s)`.
 * The shadow is cast by the shape's outline, not by the view's pixels (SwiftUI casts it from the content), so pass
 * the shape the view is drawn in. Android 8.x (API 26–27) can't blur a shape in hardware: no shadow there.
 */
fun Modifier.shooShadow(
    color: Color,
    radius: Dp,
    x: Dp = 0.dp,
    y: Dp = 0.dp,
    shape: Shape = RectangleShape,
    spread: Dp = 0.dp,
): Modifier = drawBehind {
    drawShadow(Offset.Zero, size, shape, color, radius.toPx(), x.toPx(), y.toPx(), spread.toPx())
}

/**
 * Figma's shared card shadow ("Update card", "Card Akun", "Evidence Card", "Verified Note"…):
 * #F6FCFE 5% y 1 blur 2, then #E7F2F6 6% y 6 blur 16.
 */
fun Modifier.figmaCardShadow(shape: Shape = RectangleShape): Modifier = this
    .shooShadow(hex(0xF6FCFE, 0.05f), radius = 1.dp, y = 1.dp, shape = shape)
    .shooShadow(hex(0xE7F2F6, 0.06f), radius = 8.dp, y = 6.dp, shape = shape)

/**
 * Figma's white capsule button shadow ("Aman", "Bahaya" secondary): black 20%, y 3, blur 5, spread -3.
 * Like iOS, a white capsule inset by 3 casts it behind the button.
 */
fun Modifier.figmaButtonShadow(): Modifier = drawBehind {
    drawShadow(
        Offset.Zero, size, CapsuleShape, Color.Black.copy(alpha = 0.2f),
        radiusPx = 2.5.dp.toPx(), xPx = 0f, yPx = 3.dp.toPx(), spreadPx = -3.dp.toPx(), fill = Color.White,
    )
}

/**
 * Draws `shape` of `size` at `topLeft` (grown by `spreadPx` on every side) filled with `fill`, casting a Gaussian
 * shadow of sigma `radiusPx` (SwiftUI radius) offset by (x, y). Uses the paint's shadow layer, which hardware
 * rendering supports for shapes from API 28.
 */
fun DrawScope.drawShadow(
    topLeft: Offset,
    size: Size,
    shape: Shape,
    color: Color,
    radiusPx: Float,
    xPx: Float = 0f,
    yPx: Float = 0f,
    spreadPx: Float = 0f,
    fill: Color = Color.Transparent,
) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
        if (fill.alpha > 0f) {
            val grown = Size(size.width + spreadPx * 2, size.height + spreadPx * 2)
            if (grown.width > 0f && grown.height > 0f) {
                val outline = shape.createOutline(grown, layoutDirection, this)
                drawIntoCanvas { canvas ->
                    canvas.save()
                    canvas.translate(topLeft.x - spreadPx, topLeft.y - spreadPx)
                    canvas.drawOutline(outline, Paint().apply { this.color = fill; isAntiAlias = true })
                    canvas.restore()
                }
            }
        }
        return
    }
    if (color.alpha <= 0f) return
    val grown = Size(size.width + spreadPx * 2, size.height + spreadPx * 2)
    if (grown.width <= 0f || grown.height <= 0f) return
    val outline = shape.createOutline(grown, layoutDirection, this)
    // Skia turns a shadow-layer radius into sigma = 0.57735 × radius + 0.5.
    val blur = ((radiusPx - 0.5f) / 0.57735f).coerceAtLeast(0.01f)
    // An opaque shadow colour takes the paint's alpha (Paint.setShadowLayer): keep it just below opaque so a
    // transparent fill still casts it.
    val shadowColor = color.copy(alpha = color.alpha.coerceAtMost(0.996f))
    drawIntoCanvas { canvas ->
        val paint = Paint()
        val frameworkPaint = paint.asFrameworkPaint()
        frameworkPaint.isAntiAlias = true
        frameworkPaint.color = fill.toArgb()
        frameworkPaint.setShadowLayer(blur, xPx, yPx, shadowColor.toArgb())
        canvas.save()
        canvas.translate(topLeft.x - spreadPx, topLeft.y - spreadPx)
        canvas.drawOutline(outline, paint)
        canvas.restore()
    }
}
