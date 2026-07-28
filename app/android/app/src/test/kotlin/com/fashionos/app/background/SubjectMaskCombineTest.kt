package com.fashionos.app.background

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Per-subject mask reconstruction (local BG §4).
 *
 * Used only when the full foreground mask is unusable. The SDK contract is that each
 * subject's mask is `bounds.width * bounds.height` floats covering exactly its
 * bounding box at (`startX`, `startY`) in the input image. Nothing here resizes or
 * reinterprets coordinates — a mask that contradicts its bounds is refused, because
 * guessing would silently misalign the mask against the photo.
 */
class SubjectMaskCombineTest {

    private fun mask(x: Int, y: Int, w: Int, h: Int, fill: Float) =
        SubjectConfidenceMask(SubjectBounds(x, y, w, h), FloatArray(w * h) { fill })

    private fun a(out: FloatArray, w: Int, x: Int, y: Int) = out[y * w + x]

    @Test
    fun `a single subject is placed at its own offset`() {
        val out = SoftMask.combineSubjectMasks(listOf(mask(2, 1, 2, 2, 0.8f)), 5, 4)
        assertEquals(20, out.size)
        assertEquals(0.8f, a(out, 5, 2, 1), 1e-6f)
        assertEquals(0.8f, a(out, 5, 3, 2), 1e-6f)
        // everything outside the box stays background
        assertEquals(0f, a(out, 5, 0, 0), 1e-6f)
        assertEquals(0f, a(out, 5, 4, 3), 1e-6f)
        assertEquals(4, out.count { it > 0f })
    }

    @Test
    fun `overlapping subjects take the maximum confidence`() {
        val out = SoftMask.combineSubjectMasks(
            listOf(mask(0, 0, 3, 3, 0.4f), mask(1, 1, 3, 3, 0.9f)),
            4, 4,
        )
        assertEquals(0.4f, a(out, 4, 0, 0), 1e-6f) // first only
        assertEquals(0.9f, a(out, 4, 2, 2), 1e-6f) // overlap -> max
        assertEquals(0.9f, a(out, 4, 3, 3), 1e-6f) // second only
    }

    @Test
    fun `the weaker subject never overwrites the stronger one regardless of order`() {
        val strongFirst = SoftMask.combineSubjectMasks(
            listOf(mask(0, 0, 2, 2, 0.9f), mask(0, 0, 2, 2, 0.2f)), 2, 2,
        )
        val weakFirst = SoftMask.combineSubjectMasks(
            listOf(mask(0, 0, 2, 2, 0.2f), mask(0, 0, 2, 2, 0.9f)), 2, 2,
        )
        assertTrue(strongFirst.contentEquals(weakFirst))
        assertEquals(0.9f, strongFirst[0], 1e-6f)
    }

    @Test
    fun `soft values survive - nothing is thresholded`() {
        val values = floatArrayOf(0.05f, 0.33f, 0.66f, 0.95f)
        val out = SoftMask.combineSubjectMasks(
            listOf(SubjectConfidenceMask(SubjectBounds(0, 0, 2, 2), values)), 2, 2,
        )
        assertTrue(out.contentEquals(values))
        assertEquals(4, out.distinct().size)
    }

    // ── bounds validation: refuse rather than stretch ─────────────────────────

    @Test
    fun `a mask whose length disagrees with its bounds is refused`() {
        val bad = SubjectConfidenceMask(SubjectBounds(0, 0, 3, 3), FloatArray(4) { 0.5f })
        val e = runCatching { SoftMask.combineSubjectMasks(listOf(bad), 4, 4) }.exceptionOrNull()
        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, (e as LocalCutoutException).code)
        assertTrue(e.message!!.contains("does not match its bounds"))
    }

    @Test
    fun `bounds extending past the source are refused`() {
        for (b in listOf(
            SubjectBounds(3, 0, 2, 2), // right edge past width
            SubjectBounds(0, 3, 2, 2), // bottom past height
            SubjectBounds(-1, 0, 2, 2), // negative origin
        )) {
            val m = SubjectConfidenceMask(b, FloatArray(b.width * b.height) { 0.5f })
            val e = runCatching { SoftMask.combineSubjectMasks(listOf(m), 4, 4) }.exceptionOrNull()
            assertTrue("expected refusal for $b", e is LocalCutoutException)
            assertTrue((e as LocalCutoutException).message!!.contains("outside"))
        }
    }

    @Test
    fun `non-positive subject bounds are refused`() {
        val m = SubjectConfidenceMask(SubjectBounds(0, 0, 0, 2), FloatArray(0))
        assertTrue(runCatching { SoftMask.combineSubjectMasks(listOf(m), 4, 4) }.isFailure)
    }

    @Test
    fun `a corrupt subject mask is refused, not blended in`() {
        val values = FloatArray(4) { Float.NaN }
        val m = SubjectConfidenceMask(SubjectBounds(0, 0, 2, 2), values)
        val e = runCatching { SoftMask.combineSubjectMasks(listOf(m), 2, 2) }.exceptionOrNull()
        assertTrue(e is LocalCutoutException)
        assertTrue((e as LocalCutoutException).message!!.contains("not usable"))
    }

    @Test
    fun `no usable subject mask at all is refused`() {
        val none = listOf(SubjectConfidenceMask(SubjectBounds(0, 0, 2, 2), null))
        val e = runCatching { SoftMask.combineSubjectMasks(none, 2, 2) }.exceptionOrNull()
        assertTrue(e is LocalCutoutException)
        assertTrue((e as LocalCutoutException).message!!.contains("No per-subject"))
        assertTrue(runCatching { SoftMask.combineSubjectMasks(emptyList(), 2, 2) }.isFailure)
    }

    @Test
    fun `a null mask alongside a good one is skipped, not fatal`() {
        val out = SoftMask.combineSubjectMasks(
            listOf(
                SubjectConfidenceMask(SubjectBounds(0, 0, 2, 2), null),
                mask(0, 0, 2, 2, 0.6f),
            ),
            2, 2,
        )
        assertTrue(out.all { it == 0.6f })
    }

    @Test
    fun `the reconstruction feeds toAlpha without further complaint`() {
        val out = SoftMask.combineSubjectMasks(listOf(mask(1, 1, 2, 2, 1f)), 4, 4)
        val alpha = SoftMask.toAlpha(out, 4, 4)
        assertEquals(16, alpha.size)
        assertEquals(4, alpha.count { (it.toInt() and 0xFF) == 255 })
    }
}
