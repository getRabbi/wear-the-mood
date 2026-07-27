package com.fashionos.app.background

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The mask maths (local BG §11.3).
 *
 * The single most important property here is that soft alpha stays soft. If any
 * of this thresholds to 0/255, lace, chiffon, hair and thin straps come out
 * looking cut with scissors — and it would be invisible in a compile check.
 */
class SoftMaskTest {

    private fun alphaAt(alpha: ByteArray, index: Int): Int = alpha[index].toInt() and 0xFF

    // ── FloatBuffer -> soft alpha ────────────────────────────────────────────

    @Test
    fun `converts confidences to 8-bit alpha`() {
        val alpha = SoftMask.toAlpha(floatArrayOf(0f, 0.5f, 1f, 0.25f), 2, 2)
        assertEquals(4, alpha.size)
        assertEquals(0, alphaAt(alpha, 0))
        assertEquals(128, alphaAt(alpha, 1)) // 0.5 * 255 = 127.5, rounds to 128
        assertEquals(255, alphaAt(alpha, 2))
        assertEquals(64, alphaAt(alpha, 3))
    }

    @Test
    fun `preserves intermediate values instead of thresholding`() {
        val confidences = floatArrayOf(0.05f, 0.2f, 0.45f, 0.62f, 0.8f, 0.95f)
        val alpha = SoftMask.toAlpha(confidences, 6, 1)
        val distinct = (0 until 6).map { alphaAt(alpha, it) }.toSet()
        // Six distinct inputs must yield six distinct outputs — no binarisation.
        assertEquals(6, distinct.size)
        assertTrue(distinct.none { it == 0 || it == 255 })
    }

    @Test
    fun `clamps out-of-range confidences`() {
        val alpha = SoftMask.toAlpha(floatArrayOf(-0.5f, 1.7f), 2, 1)
        assertEquals(0, alphaAt(alpha, 0))
        assertEquals(255, alphaAt(alpha, 1))
    }

    @Test
    fun `maps NaN to fully transparent rather than an arbitrary value`() {
        val alpha = SoftMask.toAlpha(floatArrayOf(Float.NaN, 0.5f), 2, 1)
        assertEquals(0, alphaAt(alpha, 0))
    }

    @Test
    fun `rejects a buffer whose length does not match the source`() {
        // A short buffer silently misaligns the mask against the photo, so this
        // must be a hard typed error rather than a best-effort crop.
        val e = runCatching { SoftMask.toAlpha(floatArrayOf(0f, 1f, 0f), 2, 2) }
            .exceptionOrNull() as? LocalCutoutException
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, e?.code)
    }

    @Test
    fun `rejects non-positive dimensions`() {
        val e = runCatching { SoftMask.toAlpha(FloatArray(0), 0, 5) }
            .exceptionOrNull() as? LocalCutoutException
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, e?.code)
    }

    @Test
    fun `maps a full-resolution buffer onto the same dimensions`() {
        val alpha = SoftMask.toAlpha(FloatArray(1600 * 1200) { 0.5f }, 1600, 1200)
        assertEquals(1600 * 1200, alpha.size)
    }

    // ── compositing ─────────────────────────────────────────────────────────

    @Test
    fun `composites straight alpha over the source colour`() {
        val argb = intArrayOf(0xFF112233.toInt(), 0xFF445566.toInt())
        val out = SoftMask.composite(argb, byteArrayOf(0, 140.toByte()))

        assertEquals(0x00, out[0] ushr 24)
        assertEquals(0x112233, out[0] and 0x00FFFFFF) // colour preserved under alpha 0
        assertEquals(140, out[1] ushr 24)
        assertEquals(0x445566, out[1] and 0x00FFFFFF) // NOT premultiplied/darkened
    }

    @Test
    fun `compositing rejects a size mismatch`() {
        val e = runCatching { SoftMask.composite(IntArray(4), ByteArray(3)) }
            .exceptionOrNull() as? LocalCutoutException
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, e?.code)
    }

    // ── metrics ─────────────────────────────────────────────────────────────

    @Test
    fun `measures a half-covered frame`() {
        // Left half opaque, right half transparent, on a 4x2 image.
        val alpha = ByteArray(8)
        for (y in 0 until 2) {
            for (x in 0 until 2) alpha[y * 4 + x] = 255.toByte()
        }
        val m = SoftMask.measure(alpha, 4, 2, emptyList())

        assertEquals(0.5, m.foregroundAreaRatio, 1e-9)
        assertEquals(1.0, m.meanForegroundConfidence, 1e-9)
        assertEquals(0.0, m.uncertainPixelRatio, 1e-9)
    }

    @Test
    fun `counts soft alpha proportionally in the area ratio`() {
        val m = SoftMask.measure(ByteArray(16) { 128.toByte() }, 4, 4, emptyList())
        assertEquals(128.0 / 255.0, m.foregroundAreaRatio, 1e-9)
    }

    @Test
    fun `an empty mask reports zero coverage and zero confidence`() {
        val m = SoftMask.measure(ByteArray(16), 4, 4, emptyList())
        assertEquals(0.0, m.foregroundAreaRatio, 1e-9)
        assertEquals(0.0, m.meanForegroundConfidence, 1e-9)
        assertEquals(0.0, m.borderForegroundRatio, 1e-9)
        assertEquals(0, m.subjectCount)
    }

    @Test
    fun `a near-full mask reports near-total coverage and border contact`() {
        val m = SoftMask.measure(ByteArray(16) { 255.toByte() }, 4, 4, emptyList())
        assertEquals(1.0, m.foregroundAreaRatio, 1e-9)
        assertEquals(1.0, m.borderForegroundRatio, 1e-9)
    }

    @Test
    fun `border ratio ignores the interior`() {
        // 4x4 with ONLY the 2x2 centre filled: the border must read as empty.
        val alpha = ByteArray(16)
        for (y in 1..2) for (x in 1..2) alpha[y * 4 + x] = 255.toByte()
        val m = SoftMask.measure(alpha, 4, 4, emptyList())

        assertEquals(0.0, m.borderForegroundRatio, 1e-9)
        assertEquals(4.0 / 16.0, m.foregroundAreaRatio, 1e-9)
    }

    @Test
    fun `border ratio counts every border pixel exactly once`() {
        // A full 3x3 border is 8 pixels; double-counting the corners would make
        // the ratio wrong in a way no other assertion here would notice.
        val alpha = ByteArray(9) { 255.toByte() }
        alpha[4] = 0 // hollow centre
        val m = SoftMask.measure(alpha, 3, 3, emptyList())
        assertEquals(1.0, m.borderForegroundRatio, 1e-9)
    }

    @Test
    fun `uncertain ratio counts only genuinely intermediate alpha`() {
        val alpha = byteArrayOf(
            0, // certain background
            255.toByte(), // certain foreground
            128.toByte(), // uncertain
            200.toByte(), // uncertain
        )
        val m = SoftMask.measure(alpha, 4, 1, emptyList())
        assertEquals(0.5, m.uncertainPixelRatio, 1e-9)
    }

    @Test
    fun `mean foreground confidence averages only foreground pixels`() {
        // One background pixel must not drag the foreground average down.
        val alpha = byteArrayOf(0, 200.toByte(), 200.toByte(), 200.toByte())
        val m = SoftMask.measure(alpha, 4, 1, emptyList())
        assertEquals(200.0 / 255.0, m.meanForegroundConfidence, 1e-9)
    }

    @Test
    fun `rejects a mask whose length does not match the dimensions`() {
        val e = runCatching { SoftMask.measure(ByteArray(5), 4, 4, emptyList()) }
            .exceptionOrNull() as? LocalCutoutException
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, e?.code)
    }

    // ── multiple-subject metadata ───────────────────────────────────────────

    @Test
    fun `subject count comes from the reported subjects`() {
        val subjects = listOf(
            SubjectBounds(0, 0, 10, 10),
            SubjectBounds(50, 50, 10, 10),
            SubjectBounds(20, 5, 4, 4),
        )
        val m = SoftMask.measure(ByteArray(16) { 128.toByte() }, 4, 4, subjects)
        assertEquals(3, m.subjectCount)
    }

    @Test
    fun `union bounds span every subject`() {
        val union = SoftMask.unionBounds(
            listOf(SubjectBounds(10, 20, 30, 40), SubjectBounds(5, 50, 10, 10)),
        )!!
        assertEquals(5, union.startX)
        assertEquals(20, union.startY)
        assertEquals(35, union.width) // 40 - 5
        assertEquals(40, union.height) // 60 - 20
    }

    @Test
    fun `union bounds ignore degenerate subjects`() {
        val union = SoftMask.unionBounds(
            listOf(SubjectBounds(10, 10, 0, 0), SubjectBounds(20, 20, 5, 5)),
        )!!
        assertEquals(20, union.startX)
        assertEquals(5, union.width)
    }

    @Test
    fun `no subjects means no bounds`() {
        assertNull(SoftMask.unionBounds(emptyList()))
        assertNull(SoftMask.measure(ByteArray(4), 2, 2, emptyList()).bounds)
    }
}
