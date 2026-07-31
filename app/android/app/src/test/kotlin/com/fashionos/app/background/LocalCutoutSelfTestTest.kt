package com.fashionos.app.background

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The native contract self-test (local BG §4).
 *
 * The reason this exists at all: `encodeMaskPng` shipped writing the confidence
 * into R/G/B with opaque alpha, so the server measured coverage 1.0 and rejected
 * EVERY ingest with 422 — while 83 Android unit tests stayed green, because the
 * only coverage of the encoder was a fake that returned a canned byte array. iOS
 * had the mirror defect: `encodeCutoutPNG` could not represent its own pixel format
 * and returned nil on every device, for months, behind a green compile check.
 *
 * A self-test only helps if it DISCRIMINATES. So these assertions prove it passes on
 * a healthy codec and fails, with the right typed reason, on each specific way a
 * codec can be broken — a self-test that always passes is worse than none, because
 * it turns an unknown into a false assurance.
 *
 * The mirror of `LocalCutoutSelfTestTests.swift`, so the two platforms cannot drift.
 */
class LocalCutoutSelfTestTest {

    @get:Rule
    val temp = TemporaryFolder()

    private fun cache(): LocalCutoutCacheStore =
        LocalCutoutCacheStore(temp.newFolder(LocalCutoutCacheStore.ROOT_DIR_NAME))

    /**
     * A codec that behaves like the real one: PNG-free, but faithful about the two
     * properties the self test asserts — the mask value lands in alpha, and cutout
     * alpha survives untouched. Encodes by simply carrying the pixels through a
     * trivial container, so the round trip is exact.
     */
    private open class FaithfulCodec : BitmapCodec {
        var lastEncoded: IntArray = IntArray(0)
        var lastWidth = 0
        var lastHeight = 0

        override fun decode(bytes: ByteArray): DecodedImage =
            DecodedImage(lastEncoded.copyOf(), lastWidth, lastHeight)

        override fun encodeMaskPng(alpha: ByteArray, width: Int, height: Int): ByteArray {
            // Exactly what AndroidBitmapCodec does, minus android.graphics.
            lastEncoded = packMaskPixels(alpha, width, height)
            lastWidth = width
            lastHeight = height
            return ByteArray(width * height) { 1 }
        }

        override fun encodeCutoutPng(argb: IntArray, width: Int, height: Int): ByteArray {
            lastEncoded = argb.copyOf()
            lastWidth = width
            lastHeight = height
            return ByteArray(width * height) { 2 }
        }
    }

    private fun run(
        codec: BitmapCodec,
        store: LocalCutoutCacheStore = cache(),
        engineVersion: String = GoogleSubjectSegmenterEngine.DEFAULT_ENGINE_VERSION,
        availability: ModuleAvailability = ModuleAvailability.AVAILABLE,
    ): Map<String, Any?> = LocalCutoutSelfTest.run(codec, store, engineVersion, availability)

    @Test
    fun `passes with a faithful codec`() {
        val reply = run(FaithfulCodec())
        assertEquals("pass", reply["status"])
        assertEquals(LocalCutoutSelfTest.Failure.NONE, reply["failureCode"])
        assertEquals(true, reply["encoderOk"])
        assertEquals(true, reply["cacheOk"])
        assertEquals(GoogleSubjectSegmenterEngine.ENGINE_NAME, reply["engine"])
        assertEquals(true, reply["modelAvailable"])
    }

    /**
     * THE regression. An encoder that mirrors the value into RGB but leaves alpha
     * opaque looks identical to the eye and is what shipped.
     */
    @Test
    fun `fails when the mask encoder drops the value out of alpha`() {
        val codec = object : FaithfulCodec() {
            override fun encodeMaskPng(alpha: ByteArray, width: Int, height: Int): ByteArray {
                lastEncoded = IntArray(width * height) { index ->
                    val v = alpha[index].toInt() and 0xFF
                    // value in RGB, alpha forced opaque -- the 422-every-ingest bug
                    (0xFF shl 24) or (v shl 16) or (v shl 8) or v
                }
                lastWidth = width
                lastHeight = height
                return ByteArray(4) { 1 }
            }
        }
        val reply = run(codec)
        assertEquals("fail", reply["status"])
        assertEquals(LocalCutoutSelfTest.Failure.MASK_ENCODER, reply["failureCode"])
        assertEquals(false, reply["encoderOk"])
    }

    /** An encoder that thresholds soft alpha hardens every lace and chiffon edge. */
    @Test
    fun `fails when the mask encoder thresholds soft values`() {
        val codec = object : FaithfulCodec() {
            override fun encodeMaskPng(alpha: ByteArray, width: Int, height: Int): ByteArray {
                lastEncoded = IntArray(width * height) { index ->
                    val v = if ((alpha[index].toInt() and 0xFF) >= 128) 0xFF else 0x00
                    (v shl 24) or (v shl 16) or (v shl 8) or v
                }
                lastWidth = width
                lastHeight = height
                return ByteArray(4) { 1 }
            }
        }
        val reply = run(codec)
        assertEquals("fail", reply["status"])
        assertEquals(LocalCutoutSelfTest.Failure.MASK_ENCODER, reply["failureCode"])
    }

    /** The iOS defect's shape: transparency lost, so the closet shows a rectangle. */
    @Test
    fun `fails when the cutout encoder flattens transparency`() {
        val codec = object : FaithfulCodec() {
            override fun encodeCutoutPng(argb: IntArray, width: Int, height: Int): ByteArray {
                lastEncoded = IntArray(argb.size) { argb[it] or (0xFF shl 24) }
                lastWidth = width
                lastHeight = height
                return ByteArray(4) { 2 }
            }
        }
        val reply = run(codec)
        assertEquals("fail", reply["status"])
        assertEquals(LocalCutoutSelfTest.Failure.CUTOUT_ENCODER, reply["failureCode"])
    }

    @Test
    fun `fails when an encoder returns nothing`() {
        val codec = object : FaithfulCodec() {
            override fun encodeCutoutPng(argb: IntArray, width: Int, height: Int) = ByteArray(0)
        }
        val reply = run(codec)
        assertEquals("fail", reply["status"])
        assertEquals(LocalCutoutSelfTest.Failure.CUTOUT_ENCODER, reply["failureCode"])
    }

    @Test
    fun `fails when the output cannot be decoded back`() {
        val codec = object : FaithfulCodec() {
            override fun decode(bytes: ByteArray): DecodedImage =
                throw LocalCutoutException(LocalCutoutErrors.INVALID_OUTPUT, "nope")
        }
        val reply = run(codec)
        assertEquals("fail", reply["status"])
        assertEquals(LocalCutoutSelfTest.Failure.INTERNAL, reply["failureCode"])
    }

    @Test
    fun `fails when dimensions do not round trip`() {
        val codec = object : FaithfulCodec() {
            override fun decode(bytes: ByteArray): DecodedImage =
                DecodedImage(IntArray(lastWidth * lastHeight), lastWidth + 1, lastHeight)
        }
        val reply = run(codec)
        assertEquals("fail", reply["status"])
        assertEquals(LocalCutoutSelfTest.Failure.DIMENSIONS, reply["failureCode"])
    }

    @Test
    fun `fails typed when the cache root is unusable`() {
        val unusable = LocalCutoutCacheStore(File(temp.newFile("not-a-directory"), "nested"))
        val reply = run(FaithfulCodec(), store = unusable)
        assertEquals("fail", reply["status"])
        assertEquals(false, reply["cacheOk"])
    }

    @Test
    fun `fails when the engine version is blank`() {
        val reply = run(FaithfulCodec(), engineVersion = "  ")
        assertEquals("fail", reply["status"])
        assertEquals(LocalCutoutSelfTest.Failure.ENGINE_VERSION, reply["failureCode"])
    }

    /** A missing model is a provider condition, not a broken encoder. */
    @Test
    fun `reports a missing model without failing the encoder verdict`() {
        val reply = run(FaithfulCodec(), availability = ModuleAvailability.NOT_INSTALLED)
        assertEquals("pass", reply["status"])
        assertEquals(true, reply["platformAvailable"])
        assertEquals(false, reply["modelAvailable"])
    }

    @Test
    fun `reports missing play services distinctly`() {
        val reply = run(FaithfulCodec(), availability = ModuleAvailability.PLAY_SERVICES_UNAVAILABLE)
        assertEquals(false, reply["platformAvailable"])
        assertEquals(false, reply["modelAvailable"])
    }

    @Test
    fun `leaves no scratch behind`() {
        val root = temp.newFolder("sweep-root")
        val store = LocalCutoutCacheStore(root)
        run(FaithfulCodec(), store = store)
        assertEquals(0, root.listFiles()?.size ?: 0)
    }

    /** The reply is telemetry: bounded, non-identifying fields only (§10). */
    @Test
    fun `reply carries only bounded safe fields`() {
        val reply = run(FaithfulCodec())
        assertEquals(
            setOf(
                "status", "engine", "engineVersion", "channelVersion", "encoderOk",
                "cacheOk", "platformAvailable", "modelAvailable", "failureCode",
            ),
            reply.keys,
        )
        for ((key, value) in reply) {
            if (value is String) {
                assertFalse("$key looks like a path", value.contains(File.separator))
                assertFalse("$key looks like a path", value.contains("/"))
            }
        }
        assertTrue(reply["channelVersion"] is Int)
    }
}
