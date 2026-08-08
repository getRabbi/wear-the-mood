package com.fashionos.app.background

/**
 * The native contract self-test (local BG §4).
 *
 * A Dart unit test can prove the orchestrator's decisions but not one thing that
 * actually matters on a device: that the NATIVE half works. `encodeCutoutPNG` on
 * iOS had never once produced a cutout — it composed through a bitmap context in a
 * pixel format CoreGraphics cannot represent and always returned nil — and that
 * survived a green compile check, a green Flutter suite and a typed cloud fallback
 * that made the result look normal. Android's mask encoder shipped writing the
 * confidence into R/G/B with opaque alpha, so every single ingest came back 422,
 * past 83 green Kotlin tests whose fake codec packed nothing.
 *
 * Both defects are the same shape: the encoder is the one component whose output no
 * test looked at. So this exercises the real codec end to end — encode, decode back,
 * inspect the pixels — plus the cache, the id discipline and the provider.
 *
 * Rules it lives by:
 *  * it returns only bounded, non-identifying fields — never a path, never bytes;
 *  * it never throws: a failure is a typed `failureCode`, because a self-test that
 *    can crash the app is worse than no self-test;
 *  * it is cheap enough to run on demand, and Dart runs it at most once per app
 *    version (§4) — never on every launch.
 */
object LocalCutoutSelfTest {

    /** Bumped when the shape of the reply changes, so Dart can reason about age. */
    const val CHANNEL_VERSION = 1

    /** A tiny synthetic image: big enough to have a border and an interior. */
    private const val PROBE_WIDTH = 8
    private const val PROBE_HEIGHT = 8

    /** Typed reasons, mirrored by Dart's `LocalCutoutSelfTestFailure`. */
    object Failure {
        const val NONE = "none"
        const val CACHE = "cache_unavailable"
        const val OPERATION_ID = "operation_id_invalid"
        const val MASK_ENCODER = "mask_encoder_lost_alpha"
        const val CUTOUT_ENCODER = "cutout_encoder_lost_transparency"
        const val DECODE = "output_not_decodable"
        const val DIMENSIONS = "dimensions_not_preserved"
        const val CLEANUP = "cleanup_failed"
        const val ENGINE_VERSION = "engine_version_missing"
        const val PROVIDER = "provider_unavailable"
        const val INTERNAL = "internal"
    }

    /**
     * Run the contract checks against the REAL codec and cache.
     *
     * [providerAvailability] is passed in rather than probed here so the pure
     * contract half stays runnable without Google Play services — the provider smoke
     * is reported separately and never fails the encoder verdict.
     */
    fun run(
        codec: BitmapCodec,
        cache: LocalCutoutCacheStore,
        engineVersion: String,
        providerAvailability: ModuleAvailability,
    ): Map<String, Any?> {
        var encoderOk = false
        var cacheOk = false
        var failure = Failure.NONE
        var operationId: String? = null

        try {
            operationId = LocalCutoutCacheStore.newOperationId()
            if (!LocalCutoutCacheStore.isValidOperationId(operationId)) {
                return reply(engineVersion, providerAvailability, false, false, Failure.OPERATION_ID)
            }

            // 1. The cache root is writable and containment-checked.
            val dir = cache.createOperationDir(operationId)
            val probe = java.io.File(dir, "selftest.bin")
            probe.writeBytes(byteArrayOf(1, 2, 3, 4))
            cacheOk = probe.exists() && probe.readBytes().size == 4 && cache.isContained(probe)
            if (!cacheOk) {
                return reply(engineVersion, providerAvailability, false, false, Failure.CACHE)
            }

            // 2. The MASK encoder must carry the confidence in the alpha channel.
            //    A mask that reaches the server uniformly opaque is exactly the
            //    422-every-ingest defect, and it is invisible to the eye.
            val alpha = ByteArray(PROBE_WIDTH * PROBE_HEIGHT) { index ->
                // 0, a soft mid value, and full — so a thresholding encoder is caught
                // as surely as one that drops the channel.
                when (index % 3) {
                    0 -> 0
                    1 -> 0x80.toByte()
                    else -> 0xFF.toByte()
                }
            }
            val maskPng = codec.encodeMaskPng(alpha, PROBE_WIDTH, PROBE_HEIGHT)
            if (maskPng.isEmpty()) {
                return reply(engineVersion, providerAvailability, false, cacheOk, Failure.MASK_ENCODER)
            }
            val decodedMask = codec.decode(maskPng)
            if (decodedMask.width != PROBE_WIDTH || decodedMask.height != PROBE_HEIGHT) {
                return reply(engineVersion, providerAvailability, false, cacheOk, Failure.DIMENSIONS)
            }
            if (!maskAlphaSurvived(decodedMask.pixels, alpha)) {
                return reply(engineVersion, providerAvailability, false, cacheOk, Failure.MASK_ENCODER)
            }

            // 3. The CUTOUT encoder must keep fully transparent pixels transparent
            //    AND keep an intermediate alpha intermediate. Losing the first gives
            //    an opaque rectangle; losing the second hardens every soft edge.
            val argb = IntArray(PROBE_WIDTH * PROBE_HEIGHT) { index ->
                when (index % 3) {
                    0 -> 0x00000000                     // fully transparent
                    1 -> 0x80FF0000.toInt()             // half-transparent red
                    else -> 0xFF00FF00.toInt()          // opaque green
                }
            }
            val cutoutPng = codec.encodeCutoutPng(argb, PROBE_WIDTH, PROBE_HEIGHT)
            if (cutoutPng.isEmpty()) {
                return reply(engineVersion, providerAvailability, false, cacheOk, Failure.CUTOUT_ENCODER)
            }
            val decodedCutout = try {
                codec.decode(cutoutPng)
            } catch (_: Exception) {
                return reply(engineVersion, providerAvailability, false, cacheOk, Failure.DECODE)
            }
            if (decodedCutout.width != PROBE_WIDTH || decodedCutout.height != PROBE_HEIGHT) {
                return reply(engineVersion, providerAvailability, false, cacheOk, Failure.DIMENSIONS)
            }
            if (!cutoutAlphaSurvived(decodedCutout.pixels)) {
                return reply(engineVersion, providerAvailability, false, cacheOk, Failure.CUTOUT_ENCODER)
            }
            encoderOk = true

            // 4. Cleanup really removes the directory (a leak here fills the cache).
            cache.delete(operationId)
            operationId = null
            if (dir.exists()) {
                return reply(engineVersion, providerAvailability, encoderOk, cacheOk, Failure.CLEANUP)
            }

            if (engineVersion.isBlank()) {
                return reply(engineVersion, providerAvailability, encoderOk, cacheOk, Failure.ENGINE_VERSION)
            }
        } catch (e: Exception) {
            failure = if (e is LocalCutoutException && e.code == LocalCutoutErrors.CACHE_UNAVAILABLE) {
                Failure.CACHE
            } else {
                Failure.INTERNAL
            }
            return reply(engineVersion, providerAvailability, encoderOk, cacheOk, failure)
        } finally {
            // Never leave scratch behind, whichever branch returned.
            operationId?.let { runCatching { cache.delete(it) } }
        }
        return reply(engineVersion, providerAvailability, encoderOk, cacheOk, failure)
    }

    /**
     * Every probe value must survive into alpha, within one step of quantisation.
     *
     * The historic defect wrote the value into R/G/B and left alpha at 0xFF, so
     * checking alpha alone is what discriminates. Colour is deliberately not
     * asserted: this encoder mirrors the value into RGB, but a future one that keeps
     * only alpha would still be correct for the server, which reads alpha first.
     */
    private fun maskAlphaSurvived(pixels: IntArray, expected: ByteArray): Boolean {
        if (pixels.size != expected.size) return false
        var sawTransparent = false
        var sawSoft = false
        for (i in pixels.indices) {
            val actual = (pixels[i] ushr 24) and 0xFF
            val want = expected[i].toInt() and 0xFF
            if (kotlin.math.abs(actual - want) > 1) return false
            if (want == 0) sawTransparent = true
            if (want in 1..254) sawSoft = true
        }
        // A uniformly opaque result would pass a naive comparison if the probe had no
        // transparency in it, so prove the probe itself discriminated.
        return sawTransparent && sawSoft
    }

    private fun cutoutAlphaSurvived(pixels: IntArray): Boolean {
        var transparent = 0
        var soft = 0
        var opaque = 0
        for (pixel in pixels) {
            when (val a = (pixel ushr 24) and 0xFF) {
                0 -> transparent++
                255 -> opaque++
                else -> if (a in 100..160) soft++
            }
        }
        return transparent > 0 && soft > 0 && opaque > 0
    }

    private fun reply(
        engineVersion: String,
        availability: ModuleAvailability,
        encoderOk: Boolean,
        cacheOk: Boolean,
        failureCode: String,
    ): Map<String, Any?> = mapOf(
        "status" to if (failureCode == Failure.NONE && encoderOk && cacheOk) "pass" else "fail",
        "engine" to GoogleSubjectSegmenterEngine.ENGINE_NAME,
        "engineVersion" to engineVersion,
        "channelVersion" to CHANNEL_VERSION,
        "encoderOk" to encoderOk,
        "cacheOk" to cacheOk,
        "platformAvailable" to (availability != ModuleAvailability.PLAY_SERVICES_UNAVAILABLE),
        "modelAvailable" to (availability == ModuleAvailability.AVAILABLE),
        "failureCode" to failureCode,
    )
}
