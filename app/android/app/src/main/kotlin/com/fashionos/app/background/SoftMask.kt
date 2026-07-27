package com.fashionos.app.background

import kotlin.math.roundToInt

/**
 * The mask maths for local background removal (local BG §5, §8.2).
 *
 * Deliberately free of every Android framework type: ML Kit hands us a
 * `FloatBuffer` of confidences, and everything from there to "alpha bytes +
 * metrics + composited pixels" is arithmetic. Keeping it that way means the part
 * most likely to be subtly wrong is covered by fast, deterministic JVM tests
 * instead of a device.
 *
 * THE RULE THAT MATTERS: the confidence mask is soft and stays soft. Nothing here
 * thresholds the output to 0/255. A hard stencil is what makes lace, chiffon,
 * hair and thin straps look cut out with scissors, and it is exactly what the
 * BiRefNet pipeline went to some trouble to avoid on the server side.
 */
object SoftMask {

    /**
     * Alpha values strictly between these bounds count as "uncertain" — a genuinely
     * soft edge. Expected to be non-trivial for lace and hair, which is why a high
     * ratio is a soft warning in the Dart policy and never a rejection.
     */
    const val UNCERTAIN_LOW = 16
    const val UNCERTAIN_HIGH = 239

    /** At or above this, a pixel is treated as foreground for confidence averaging. */
    const val FOREGROUND_THRESHOLD = 128

    /**
     * Convert ML Kit confidences (`0.0..1.0`, row-major) to 8-bit alpha.
     *
     * Values are clamped and rounded, never thresholded. The returned array is
     * `width * height` bytes, unsigned in spirit — read with `toInt() and 0xFF`.
     *
     * @throws LocalCutoutException [LocalCutoutErrors.INVALID_OUTPUT] when the buffer
     *   length does not match the source dimensions, which would silently misalign
     *   the mask against the photo.
     */
    fun toAlpha(confidence: FloatArray, width: Int, height: Int): ByteArray {
        requirePositiveDimensions(width, height)
        val expected = width * height
        if (confidence.size != expected) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Confidence buffer length ${confidence.size} does not match ${width}x$height.",
            )
        }
        val alpha = ByteArray(expected)
        for (i in 0 until expected) {
            val c = confidence[i]
            // NaN fails both comparisons and lands on 0 — an unusable value must not
            // become an arbitrary alpha.
            val clamped = when {
                c.isNaN() -> 0f
                c <= 0f -> 0f
                c >= 1f -> 1f
                else -> c
            }
            alpha[i] = (clamped * 255f).roundToInt().toByte()
        }
        return alpha
    }

    /**
     * Apply [alpha] to [argb] in place-safe fashion, returning a new pixel array
     * with the original colour and the mask's alpha.
     *
     * Straight alpha, not premultiplied: the PNG encoder expects unpremultiplied
     * ARGB_8888, and premultiplying here would darken every soft edge.
     */
    fun composite(argb: IntArray, alpha: ByteArray): IntArray {
        if (argb.size != alpha.size) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Pixel count ${argb.size} does not match mask ${alpha.size}.",
            )
        }
        val out = IntArray(argb.size)
        for (i in argb.indices) {
            val a = alpha[i].toInt() and 0xFF
            out[i] = (a shl 24) or (argb[i] and 0x00FFFFFF)
        }
        return out
    }

    /**
     * Measure a finished mask. The definitions here are the CONTRACT that the iOS
     * engine must match in Phase 4 — the Dart quality policy applies one set of
     * thresholds to both platforms, so a divergent definition would silently mean
     * different rejection behaviour per platform.
     */
    fun measure(
        alpha: ByteArray,
        width: Int,
        height: Int,
        subjects: List<SubjectBounds>,
    ): MaskMetrics {
        requirePositiveDimensions(width, height)
        if (alpha.size != width * height) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Mask length ${alpha.size} does not match ${width}x$height.",
            )
        }

        var alphaSum = 0L
        var uncertain = 0L
        var foregroundCount = 0L
        var foregroundSum = 0L
        for (b in alpha) {
            val a = b.toInt() and 0xFF
            alphaSum += a
            if (a in (UNCERTAIN_LOW + 1)..<UNCERTAIN_HIGH) uncertain++
            if (a >= FOREGROUND_THRESHOLD) {
                foregroundCount++
                foregroundSum += a
            }
        }

        val total = width.toLong() * height.toLong()
        val borderSum = borderAlphaSum(alpha, width, height)

        return MaskMetrics(
            width = width,
            height = height,
            subjectCount = subjects.size,
            // Mean alpha: a soft edge contributes proportionally rather than being
            // counted as fully present or fully absent. Matches the server's own
            // `mask_alpha_area_ratio`, so client and server agree on "coverage".
            foregroundAreaRatio = alphaSum.toDouble() / (total * 255.0),
            borderForegroundRatio = if (borderSum.pixels == 0L) {
                0.0
            } else {
                borderSum.sum.toDouble() / (borderSum.pixels * 255.0)
            },
            uncertainPixelRatio = uncertain.toDouble() / total,
            meanForegroundConfidence = if (foregroundCount == 0L) {
                0.0
            } else {
                foregroundSum.toDouble() / (foregroundCount * 255.0)
            },
            bounds = unionBounds(subjects),
        )
    }

    private data class BorderSum(val sum: Long, val pixels: Long)

    /** Mean alpha over the one-pixel frame border, counting each pixel exactly once. */
    private fun borderAlphaSum(alpha: ByteArray, width: Int, height: Int): BorderSum {
        var sum = 0L
        var pixels = 0L
        fun add(x: Int, y: Int) {
            sum += alpha[y * width + x].toInt() and 0xFF
            pixels++
        }
        for (x in 0 until width) {
            add(x, 0)
            if (height > 1) add(x, height - 1)
        }
        // Skip the corners already counted by the top/bottom rows.
        for (y in 1 until (height - 1).coerceAtLeast(1)) {
            add(0, y)
            if (width > 1) add(width - 1, y)
        }
        return BorderSum(sum, pixels)
    }

    /** Smallest box containing every subject, or null when none were reported. */
    fun unionBounds(subjects: List<SubjectBounds>): SubjectBounds? {
        if (subjects.isEmpty()) return null
        var left = Int.MAX_VALUE
        var top = Int.MAX_VALUE
        var right = Int.MIN_VALUE
        var bottom = Int.MIN_VALUE
        for (s in subjects) {
            if (s.width <= 0 || s.height <= 0) continue
            left = minOf(left, s.startX)
            top = minOf(top, s.startY)
            right = maxOf(right, s.startX + s.width)
            bottom = maxOf(bottom, s.startY + s.height)
        }
        if (left == Int.MAX_VALUE) return null
        return SubjectBounds(left, top, right - left, bottom - top)
    }

    private fun requirePositiveDimensions(width: Int, height: Int) {
        if (width <= 0 || height <= 0) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Image has non-positive dimensions.",
            )
        }
    }
}

/** One subject's pixel bounds, as ML Kit reports them. */
data class SubjectBounds(
    val startX: Int,
    val startY: Int,
    val width: Int,
    val height: Int,
)

/** Safe, non-identifying measurements of one mask. Mirrors `LocalCutoutMetrics` in Dart. */
data class MaskMetrics(
    val width: Int,
    val height: Int,
    val subjectCount: Int,
    val foregroundAreaRatio: Double,
    val borderForegroundRatio: Double,
    val uncertainPixelRatio: Double,
    val meanForegroundConfidence: Double,
    val bounds: SubjectBounds?,
)
