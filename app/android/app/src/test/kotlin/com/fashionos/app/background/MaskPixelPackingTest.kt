package com.fashionos.app.background

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * The mask channel contract (local BG §6.1.5).
 *
 * These tests exist because of a real production-blocking bug, found only by device
 * diagnosis on 2026-07-29. `encodeMaskPng` wrote the confidence into R/G/B and set
 * `alpha = 0xFF`, on the assumption that the backend would take luminance. It does
 * not: `_extract_mask_channel` tests alpha-bearing modes FIRST, and
 * `compress(PNG)` on an ARGB_8888 bitmap always emits RGBA — so the server read a
 * uniformly opaque band, measured coverage 1.0, tripped `_MAX_LOCAL_ALPHA_AREA`
 * (0.998), and rejected EVERY ingest with 422 "The cutout mask does not look
 * usable."
 *
 * 83 Android unit tests were green throughout, because the only coverage of
 * `encodeMaskPng` was a fake that returned a canned byte array. So the assertion
 * that matters here is on **alpha**, not on RGB.
 */
class MaskPixelPackingTest {

    /** Alpha byte of an ARGB int. */
    private fun a(p: Int) = (p ushr 24) and 0xFF
    private fun r(p: Int) = (p ushr 16) and 0xFF
    private fun g(p: Int) = (p ushr 8) and 0xFF
    private fun b(p: Int) = p and 0xFF

    @Test
    fun `alpha carries the confidence value`() {
        val alpha = byteArrayOf(0, 64, 127, -1) // -1 == 0xFF
        val packed = packMaskPixels(alpha, 4, 1)

        assertEquals(0, a(packed[0]))
        assertEquals(64, a(packed[1]))
        assertEquals(127, a(packed[2]))
        assertEquals(255, a(packed[3]))
    }

    @Test
    fun `alpha is NOT uniformly opaque - the exact regression that shipped`() {
        // A real mask has background (0) and foreground (255). If alpha comes back
        // all-255 the server measures coverage 1.0 and rejects the ingest.
        val alpha = ByteArray(100) { if (it < 80) 0 else -1 }
        val packed = packMaskPixels(alpha, 10, 10)

        val allOpaque = packed.all { a(it) == 255 }
        assertNotEquals(
            "alpha must not be uniformly 0xFF — that is the bug that 422'd every ingest",
            true,
            allOpaque,
        )
        assertEquals(80, packed.count { a(it) == 0 })
        assertEquals(20, packed.count { a(it) == 255 })
    }

    @Test
    fun `server-side coverage computed from alpha matches the mask`() {
        // Mirrors backend `mask_alpha_area_ratio`: the MEAN of the 8-bit alpha band.
        // With the old packing this was always exactly 1.0.
        val alpha = ByteArray(1000) { if (it < 250) -1 else 0 } // 25% foreground
        val packed = packMaskPixels(alpha, 100, 10)

        val meanAlpha = packed.sumOf { a(it) }.toDouble() / (packed.size * 255.0)
        assertEquals(0.25, meanAlpha, 1e-9)
        // And it must sit inside the server's accepted band, unlike 1.0.
        assert(meanAlpha in 0.005..0.998)
    }

    @Test
    fun `rgb mirrors alpha so the luminance branch is also correct`() {
        // Belt and braces: if a future server build reduces via luminance instead of
        // the alpha band, it still reads the same confidence.
        val alpha = byteArrayOf(0, 17, -34, -1)
        val packed = packMaskPixels(alpha, 4, 1)

        for (p in packed) {
            assertEquals(a(p), r(p))
            assertEquals(a(p), g(p))
            assertEquals(a(p), b(p))
        }
    }

    @Test
    fun `soft edges survive as intermediate alpha`() {
        // A gradient must stay a gradient — no thresholding, no clamping to 0/255.
        val alpha = ByteArray(256) { it.toByte() }
        val packed = packMaskPixels(alpha, 256, 1)

        assertEquals(256, packed.map { a(it) }.distinct().size)
        assertEquals(0, a(packed[0]))
        assertEquals(128, a(packed[128]))
        assertEquals(255, a(packed[255]))
    }

    @Test
    fun `packing covers exactly width times height pixels`() {
        val packed = packMaskPixels(ByteArray(12) { -1 }, 4, 3)
        assertEquals(12, packed.size)
    }

    @Test
    fun `a short alpha array is rejected rather than read out of bounds`() {
        assertThrows(IllegalArgumentException::class.java) {
            packMaskPixels(ByteArray(5) { -1 }, 4, 3)
        }
    }

    @Test
    fun `non-positive dimensions are rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            packMaskPixels(ByteArray(4) { -1 }, 0, 4)
        }
        assertThrows(IllegalArgumentException::class.java) {
            packMaskPixels(ByteArray(4) { -1 }, 4, -1)
        }
    }
}
