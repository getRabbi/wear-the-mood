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
     * How far outside `0.0..1.0` a confidence may drift and still be treated as a
     * legitimate value to clamp rather than corruption.
     *
     * Deliberately tiny. Genuine float arithmetic lands a hair outside the interval;
     * a corrupt read does not land at 1.0001, it lands at 3.4e38 or NaN.
     */
    const val CONFIDENCE_DRIFT_TOLERANCE = 1e-3f

    /**
     * Share of a confidence buffer that may be non-finite or wildly out of range
     * before the whole buffer is rejected.
     *
     * A healthy ML Kit buffer has ZERO such values, so this is a hair above nothing
     * rather than a real allowance. The device diagnostic that motivated this check
     * measured 69% invalid — three orders of magnitude past this bound.
     */
    const val MAX_INVALID_CONFIDENCE_RATIO = 0.001

    /** What an inspection found. Counts only; never any pixel value. */
    data class ConfidenceReport(
        val total: Int,
        val nonFinite: Int,
        val outOfRange: Int,
    ) {
        val invalid: Int get() = nonFinite + outOfRange
        val invalidRatio: Double
            get() = if (total <= 0) 1.0 else invalid.toDouble() / total
        val isUsable: Boolean
            get() = total > 0 && invalidRatio <= MAX_INVALID_CONFIDENCE_RATIO

        /** Bounded, non-identifying — safe to log. */
        fun summary(): String =
            "total=$total non_finite=$nonFinite out_of_range=$outOfRange " +
                "invalid_ratio=${"%.4f".format(invalidRatio)}"
    }

    /**
     * Count how much of [confidence] is unusable. Never throws, never mutates.
     *
     * `outOfRange` counts only values beyond [CONFIDENCE_DRIFT_TOLERANCE] — a value
     * of `1.0002` is a clampable drift, not corruption.
     */
    fun inspectConfidence(confidence: FloatArray): ConfidenceReport {
        var nonFinite = 0
        var outOfRange = 0
        for (c in confidence) {
            if (c.isNaN() || c.isInfinite()) {
                nonFinite++
            } else if (c < -CONFIDENCE_DRIFT_TOLERANCE || c > 1f + CONFIDENCE_DRIFT_TOLERANCE) {
                outOfRange++
            }
        }
        return ConfidenceReport(confidence.size, nonFinite, outOfRange)
    }

    /**
     * Inspect [confidence] and reject it if it cannot be trusted (§1).
     *
     * This is the guard that turns a corrupt SDK buffer into a typed local failure
     * instead of a plausible-looking cutout. Before it existed, [toAlpha] coerced
     * NaN to 0 and clamped 3.4e38 to 1, which is exactly how a 69%-invalid buffer
     * became a saved wardrobe item.
     *
     * @throws LocalCutoutException [LocalCutoutErrors.INVALID_OUTPUT] on a length
     *   mismatch or on too much invalid data.
     */
    fun requireUsableConfidence(
        confidence: FloatArray,
        width: Int,
        height: Int,
    ): ConfidenceReport {
        requirePositiveDimensions(width, height)
        val expected = width * height
        if (confidence.size != expected) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Confidence buffer length ${confidence.size} does not match ${width}x$height.",
            )
        }
        val report = inspectConfidence(confidence)
        if (!report.isUsable) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Confidence buffer is not usable: ${report.summary()}.",
            )
        }
        return report
    }

    /**
     * Rebuild a full-frame soft mask from per-subject masks (§4).
     *
     * Only used when the full foreground mask is unusable. Each subject mask is
     * placed at its own documented offset and overlaps take the MAXIMUM confidence,
     * so two subjects sharing a pixel keep the stronger claim. Nothing is resized,
     * nothing is thresholded, and pixels no subject covers stay 0.
     *
     * @throws LocalCutoutException when no subject supplies a mask, or when a mask's
     *   length or bounds contradict the SDK contract — a mismatch is refused rather
     *   than stretched, because a wrong coordinate assumption silently misaligns the
     *   mask against the photo.
     */
    fun combineSubjectMasks(
        masks: List<SubjectConfidenceMask>,
        width: Int,
        height: Int,
    ): FloatArray {
        requirePositiveDimensions(width, height)
        val usable = masks.filter { it.confidence != null && it.confidence.isNotEmpty() }
        if (usable.isEmpty()) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "No per-subject confidence mask was supplied.",
            )
        }
        val out = FloatArray(width * height)
        for (mask in usable) {
            val b = mask.bounds
            val values = mask.confidence!!
            if (b.width <= 0 || b.height <= 0) {
                throw LocalCutoutException(
                    LocalCutoutErrors.INVALID_OUTPUT,
                    "Subject bounds ${b.width}x${b.height} are not positive.",
                )
            }
            if (values.size != b.width * b.height) {
                throw LocalCutoutException(
                    LocalCutoutErrors.INVALID_OUTPUT,
                    "Subject mask length ${values.size} does not match its bounds " +
                        "${b.width}x${b.height}.",
                )
            }
            if (b.startX < 0 || b.startY < 0 ||
                b.startX + b.width > width || b.startY + b.height > height
            ) {
                throw LocalCutoutException(
                    LocalCutoutErrors.INVALID_OUTPUT,
                    "Subject bounds fall outside the ${width}x$height source.",
                )
            }
            val report = inspectConfidence(values)
            if (!report.isUsable) {
                throw LocalCutoutException(
                    LocalCutoutErrors.INVALID_OUTPUT,
                    "Subject mask is not usable: ${report.summary()}.",
                )
            }
            for (y in 0 until b.height) {
                val srcRow = y * b.width
                val dstRow = (b.startY + y) * width + b.startX
                for (x in 0 until b.width) {
                    val v = values[srcRow + x].coerceIn(0f, 1f)
                    val i = dstRow + x
                    if (v > out[i]) out[i] = v
                }
            }
        }
        return out
    }

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
        // Validate FIRST. This used to coerce NaN to 0 and clamp anything huge to 1,
        // which turned a corrupt SDK buffer into a plausible mask instead of a typed
        // failure (§1). Legitimate drift is still clamped below.
        requireUsableConfidence(confidence, width, height)
        val expected = width * height
        val alpha = ByteArray(expected)
        for (i in 0 until expected) {
            val c = confidence[i]
            // Only survivors of validation reach here: finite, and within drift of
            // 0..1. NaN is still handled defensively so this can never produce a
            // garbage byte even if the tolerance is ever loosened.
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
