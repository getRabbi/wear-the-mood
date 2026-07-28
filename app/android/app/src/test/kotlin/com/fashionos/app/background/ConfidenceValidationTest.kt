package com.fashionos.app.background

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Confidence-buffer validation (local BG §1).
 *
 * Motivated by a real device finding on 2026-07-29: ML Kit `16.0.0-beta1` returned a
 * `foregroundConfidenceMask` that was ~69% NaN/out-of-range when copied after
 * `Tasks.await()`. [SoftMask.toAlpha] silently coerced NaN to 0 and clamped huge
 * values to 1, so that buffer became a saved wardrobe item with a scrambled mask.
 *
 * The rule these tests pin: legitimate float drift near 0 and 1 is clamped, and
 * anything else is refused outright.
 */
class ConfidenceValidationTest {

    private fun clean(n: Int, value: Float = 0.5f) = FloatArray(n) { value }

    // ── drift is tolerated ───────────────────────────────────────────────────

    @Test
    fun `tiny drift below zero and above one is accepted and clamped`() {
        val c = floatArrayOf(-0.0005f, 0f, 0.5f, 1f, 1.0005f)
        val report = SoftMask.inspectConfidence(c)
        assertEquals(0, report.invalid)
        assertTrue(report.isUsable)

        val alpha = SoftMask.toAlpha(c, 5, 1)
        assertEquals(0, alpha[0].toInt() and 0xFF)   // -0.0005 clamps to 0
        assertEquals(0, alpha[1].toInt() and 0xFF)
        assertEquals(128, alpha[2].toInt() and 0xFF)
        assertEquals(255, alpha[3].toInt() and 0xFF)
        assertEquals(255, alpha[4].toInt() and 0xFF) // 1.0005 clamps to 255
    }

    @Test
    fun `drift exactly at the tolerance is still accepted`() {
        val t = SoftMask.CONFIDENCE_DRIFT_TOLERANCE
        val report = SoftMask.inspectConfidence(floatArrayOf(-t, 1f + t))
        assertEquals(0, report.invalid)
        assertTrue(report.isUsable)
    }

    // ── corruption is refused ────────────────────────────────────────────────

    @Test
    fun `a heavily corrupt buffer is rejected, never converted`() {
        // The shape actually observed on device: ~69% invalid.
        val c = FloatArray(1000) { i ->
            when {
                i % 100 < 20 -> Float.NaN
                i % 100 < 69 -> 3.4e38f
                else -> 0.7f
            }
        }
        val report = SoftMask.inspectConfidence(c)
        assertFalse(report.isUsable)
        assertEquals(200, report.nonFinite)
        assertEquals(490, report.outOfRange)

        val e = runCatching { SoftMask.toAlpha(c, 1000, 1) }.exceptionOrNull()
        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, (e as LocalCutoutException).code)
    }

    @Test
    fun `NaN beyond the allowance is rejected`() {
        val n = 10_000
        val c = FloatArray(n) { if (it < 50) Float.NaN else 0.5f } // 0.5% > 0.1% bound
        assertFalse(SoftMask.inspectConfidence(c).isUsable)
        assertTrue(runCatching { SoftMask.toAlpha(c, n, 1) }.isFailure)
    }

    @Test
    fun `positive and negative infinity both count as non-finite`() {
        val c = floatArrayOf(Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, 0.5f)
        val report = SoftMask.inspectConfidence(c)
        assertEquals(2, report.nonFinite)
        assertEquals(0, report.outOfRange)
    }

    @Test
    fun `a value far outside the range is out-of-range, not merely clamped`() {
        val report = SoftMask.inspectConfidence(floatArrayOf(-5f, 42f, 0.5f))
        assertEquals(2, report.outOfRange)
        assertFalse(report.isUsable)
    }

    @Test
    fun `a single stray value in a large clean buffer is tolerated`() {
        // 1 in 10000 = 0.0001, inside the 0.001 bound: one bad float should not cost
        // the user their fast path.
        val c = clean(10_000).also { it[7] = Float.NaN }
        assertTrue(SoftMask.inspectConfidence(c).isUsable)
        assertEquals(0, SoftMask.toAlpha(c, 10_000, 1)[7].toInt() and 0xFF)
    }

    @Test
    fun `an empty buffer is never usable`() {
        assertFalse(SoftMask.inspectConfidence(FloatArray(0)).isUsable)
    }

    @Test
    fun `a length mismatch is rejected before validity is considered`() {
        val e = runCatching { SoftMask.requireUsableConfidence(clean(10), 4, 4) }.exceptionOrNull()
        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, (e as LocalCutoutException).code)
        assertTrue(e.message!!.contains("does not match"))
    }

    @Test
    fun `a clean buffer passes and reports zero invalid`() {
        val report = SoftMask.requireUsableConfidence(clean(64), 8, 8)
        assertEquals(64, report.total)
        assertEquals(0, report.invalid)
        assertEquals(0.0, report.invalidRatio, 1e-12)
    }

    @Test
    fun `the report summary carries counts only, never pixel values`() {
        val summary = SoftMask.inspectConfidence(floatArrayOf(0.123456f, Float.NaN)).summary()
        assertTrue(summary.contains("non_finite=1"))
        assertFalse("must not leak a pixel value", summary.contains("0.123"))
    }
}
