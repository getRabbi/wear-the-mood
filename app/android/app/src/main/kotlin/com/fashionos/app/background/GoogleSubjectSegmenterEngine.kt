package com.fashionos.app.background

/**
 * The Android local-cutout engine (local BG §8.2).
 *
 * Orchestration only — every SDK touch goes through [SubjectSegmentationClient] or
 * [BitmapCodec], so this whole class is exercised by JVM tests with fakes.
 *
 * Order of work, and why:
 *   1. availability, so an AOSP device or a missing model costs nothing;
 *   2. decode the EXACT bytes Dart will upload as the original — never a re-read
 *      of a file, which is how mask/original dimension drift happens (§8.1);
 *   3. await initialisation, so inference is not charged for model load;
 *   4. segment;
 *   5. convert to soft alpha, measure, composite;
 *   6. write both PNGs into the operation directory and hand back paths.
 *
 * A cancellation checkpoint sits between each expensive stage: teardown flips a
 * flag rather than interrupting a thread mid-inference.
 */
class GoogleSubjectSegmenterEngine(
    private val client: SubjectSegmentationClient,
    private val codec: BitmapCodec,
    private val cache: LocalCutoutCacheStore,
    private val guard: SingleOperationGuard = SingleOperationGuard(),
    private val clock: () -> Long = System::currentTimeMillis,
    private val engineVersion: String = DEFAULT_ENGINE_VERSION,
    // Injected rather than `android.util.Log`: the android.jar stub throws in JVM
    // unit tests, which would make every diagnostic error path untestable.
    private val logger: LocalCutoutLogger = LocalCutoutLogger.NONE,
) {
    companion object {
        /** Bounded, non-identifying. Reported for observability only. */
        const val DEFAULT_ENGINE_VERSION = "mlkit-subject-segmentation-16.0.0-beta1"

        const val ENGINE_NAME = "google_mlkit"

        /** Share of the budget spent waiting for initialisation before inference. */
        private const val INIT_BUDGET_FRACTION = 0.4

        /**
         * Coverage band a local mask must land inside to be accepted (§5).
         *
         * Matches the server's own `_MIN/_MAX_LOCAL_ALPHA_AREA`, so the client never
         * uploads a mask the endpoint would refuse.
         */
        const val MIN_COVERAGE = 0.005
        const val MAX_COVERAGE = 0.995
    }

    /** The reconstructed mask plus the report that justified accepting it. */
    class ResolvedConfidence(
        val values: FloatArray,
        val fromFullMask: Boolean,
        val report: SoftMask.ConfidenceReport,
        val subjectCount: Int,
    ) {
        fun describe(): String =
            (if (fromFullMask) "full_mask" else "per_subject_x$subjectCount") +
                " ${report.summary()}"
    }

    /**
     * Build the authoritative mask from per-subject masks (§1-§4).
     *
     * There is no full-foreground path any more: `enableForegroundConfidenceMask()`
     * is off because that buffer is corrupt at the source on ML Kit
     * `16.0.0-beta1`, and reading it — even copied inside the success callback —
     * produced 15%-96% NaN/out-of-range values. The per-subject masks carried zero
     * NaN and a deterministic bounded overshoot, so they are the only source we
     * trust. Any problem is typed and surfaces as a local failure.
     */
    private fun resolveConfidence(
        output: SegmentationOutput,
        width: Int,
        height: Int,
    ): ResolvedConfidence {
        val combined = SoftMask.combineSubjectMasks(output.subjectMasks, width, height)
        // Clamped by construction, so this only re-checks length; kept so the mask
        // handed to toAlpha is provably in range whatever the source.
        val report = SoftMask.requireUsableConfidence(combined, width, height)
        return ResolvedConfidence(combined, false, report, output.subjectMasks.size)
    }

    /** What this device can do right now. Never throws. */
    fun capability(timeoutMs: Long): ModuleAvailability =
        try {
            client.moduleAvailability(timeoutMs)
        } catch (e: Exception) {
            logger.warn("availability probe failed: ${e.javaClass.simpleName}")
            ModuleAvailability.UNKNOWN
        }

    /**
     * Native contract self-test (§4). Never throws.
     *
     * Runs the REAL codec and the REAL cache — the two components no other test
     * looks at, and the two that have each shipped broken. The provider smoke is
     * folded in but reported separately: a device with no Play services should
     * report an unavailable MODEL, not a failed encoder.
     */
    fun selfTest(timeoutMs: Long): Map<String, Any?> {
        var availability = capability(timeoutMs)
        if (availability == ModuleAvailability.AVAILABLE) {
            // Initialisation is part of the provider contract: a segmenter that
            // cannot init is not "available" however the module reports itself.
            val initialised = runCatching { client.awaitInitialization(timeoutMs) }.isSuccess
            if (!initialised) {
                logger.warn("self test: segmenter initialisation failed")
                availability = ModuleAvailability.UNKNOWN
            }
        }
        return LocalCutoutSelfTest.run(codec, cache, engineVersion, availability)
    }

    /**
     * Best-effort model preparation. Never throws: an unprepared model is a normal
     * outcome that routes the add to the cloud, not an error the user should see.
     */
    fun prepare(timeoutMs: Long, urgent: Boolean): ModuleAvailability {
        val current = capability(timeoutMs)
        if (current == ModuleAvailability.AVAILABLE) {
            // Warm the segmenter so the first real add is not charged for it.
            runCatching { client.awaitInitialization(timeoutMs) }
                .onFailure { logger.warn("init warm-up failed: ${it.javaClass.simpleName}") }
            return ModuleAvailability.AVAILABLE
        }
        if (current == ModuleAvailability.PLAY_SERVICES_UNAVAILABLE) {
            return current // nothing to install against
        }
        return try {
            client.requestModuleInstall(timeoutMs, urgent)
        } catch (e: Exception) {
            logger.warn("module install failed: ${e.javaClass.simpleName}")
            ModuleAvailability.DOWNLOAD_FAILED
        }
    }

    /**
     * Segment [jpegBytes] and write the results into a fresh operation directory.
     *
     * @throws LocalCutoutException always typed; the caller maps `code` straight to
     *   `PlatformException.code`.
     */
    fun removeBackground(jpegBytes: ByteArray, timeoutMs: Long): LocalCutoutResult {
        val operationId = LocalCutoutCacheStore.newOperationId()
        if (!guard.begin(operationId)) {
            throw LocalCutoutException(
                LocalCutoutErrors.BUSY,
                "Another background removal is already running.",
            )
        }
        val startedAt = clock()
        try {
            return runOperation(operationId, jpegBytes, timeoutMs, startedAt)
        } catch (e: LocalCutoutException) {
            cache.delete(operationId) // never leave a half-written directory behind
            throw e
        } catch (e: Exception) {
            cache.delete(operationId)
            throw LocalCutoutException(
                LocalCutoutErrors.INTERNAL,
                "Local background removal failed: ${e.javaClass.simpleName}",
                e,
            )
        } finally {
            guard.end(operationId)
        }
    }

    private fun runOperation(
        operationId: String,
        jpegBytes: ByteArray,
        timeoutMs: Long,
        startedAt: Long,
    ): LocalCutoutResult {
        if (jpegBytes.isEmpty()) {
            throw LocalCutoutException(LocalCutoutErrors.INVALID_OUTPUT, "Empty source image.")
        }

        val availability = capability(timeoutMs)
        if (availability != ModuleAvailability.AVAILABLE) {
            throw LocalCutoutException(
                availability.toErrorCode(),
                "Segmentation model unavailable: ${availability.name}",
            )
        }
        guard.throwIfCancelled(operationId)

        val decodeStart = clock()
        val image = codec.decode(jpegBytes)
        val decodeMs = clock() - decodeStart
        if (image.width <= 0 || image.height <= 0 ||
            image.pixels.size != image.width * image.height
        ) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Decoded image is inconsistent.",
            )
        }
        guard.throwIfCancelled(operationId)

        val initStart = clock()
        val initBudget = (timeoutMs * INIT_BUDGET_FRACTION).toLong().coerceAtLeast(1L)
        client.awaitInitialization(initBudget)
        val initMs = clock() - initStart
        guard.throwIfCancelled(operationId)

        val inferenceStart = clock()
        val remaining = (timeoutMs - (clock() - startedAt)).coerceAtLeast(1L)
        val output = client.segment(image, remaining)
        val inferenceMs = clock() - inferenceStart
        guard.throwIfCancelled(operationId)

        val maskStart = clock()
        // ML Kit must report at least one subject. Without one there is nothing to
        // reconstruct from if the full mask is bad, and a "mask with no subject" is
        // the engine saying it found nothing (§5).
        if (output.subjects.isEmpty()) {
            throw LocalCutoutException(
                LocalCutoutErrors.NO_SUBJECT,
                "No foreground subject was found.",
            )
        }
        val resolved = resolveConfidence(output, image.width, image.height)
        val confidence = resolved.values
        val alpha = SoftMask.toAlpha(confidence, image.width, image.height)
        val metrics = SoftMask.measure(alpha, image.width, image.height, output.subjects)
        val maskMs = clock() - maskStart
        // Near-empty or near-full is not a cutout. Refuse locally rather than upload
        // something the server's own coverage band would reject anyway (§5).
        if (metrics.foregroundAreaRatio < MIN_COVERAGE || metrics.foregroundAreaRatio > MAX_COVERAGE) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Mask coverage ${"%.4f".format(metrics.foregroundAreaRatio)} is outside " +
                    "$MIN_COVERAGE..$MAX_COVERAGE.",
            )
        }
        guard.throwIfCancelled(operationId)

        val compositeStart = clock()
        val maskPng = codec.encodeMaskPng(alpha, image.width, image.height)
        val cutoutPng = codec.encodeCutoutPng(
            SoftMask.composite(image.pixels, alpha),
            image.width,
            image.height,
        )
        if (maskPng.isEmpty() || cutoutPng.isEmpty()) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Encoder produced an empty image.",
            )
        }
        val compositeMs = clock() - compositeStart
        guard.throwIfCancelled(operationId)

        val writeStart = clock()
        cache.createOperationDir(operationId)
        val maskFile = cache.maskFile(operationId)
        val cutoutFile = cache.cutoutFile(operationId)
        maskFile.writeBytes(maskPng)
        cutoutFile.writeBytes(cutoutPng)
        // A result must never point at a missing or empty file (§4).
        if (!maskFile.isFile || maskFile.length() == 0L ||
            !cutoutFile.isFile || cutoutFile.length() == 0L
        ) {
            throw LocalCutoutException(
                LocalCutoutErrors.CACHE_UNAVAILABLE,
                "Could not persist the operation output.",
            )
        }

        // Structured stage timings (§10): durations and bucketed counts only — no
        // paths, no filenames, no operation id, no bytes.
        logger.warn(
            "local cutout stages decode_ms=$decodeMs init_ms=$initMs " +
                "inference_ms=$inferenceMs mask_ms=$maskMs composite_ms=$compositeMs " +
                "write_ms=${clock() - writeStart} total_ms=${clock() - startedAt} " +
                "subjects=${metrics.subjectCount} " +
                "coverage=${"%.2f".format(metrics.foregroundAreaRatio)}",
        )
        return LocalCutoutResult(
            operationId = operationId,
            engineVersion = engineVersion,
            maskFilePath = maskFile.path,
            cutoutFilePath = cutoutFile.path,
            metrics = metrics,
            latencyMs = (clock() - startedAt).coerceAtLeast(0L),
        )
    }

    /** Cancel the in-flight run, if any. */
    fun cancel(operationId: String?) = guard.cancel(operationId)

    /** Delete one operation's files. Idempotent; id-based, never path-based. */
    fun cleanup(operationId: String): Boolean = cache.delete(operationId)

    fun sweepCache(maxAgeMs: Long): Int = cache.sweepStale(maxAgeMs, clock())

    /** Release the segmenter and drop scratch files. Safe to call twice. */
    fun close() {
        guard.cancel()
        runCatching { client.close() }
            .onFailure { logger.warn("segmenter close failed: ${it.javaClass.simpleName}") }
        runCatching { cache.clear() }
    }
}

/** A successful local removal, ready to serialise onto the method channel. */
class LocalCutoutResult(
    val operationId: String,
    val engineVersion: String,
    val maskFilePath: String,
    val cutoutFilePath: String,
    val metrics: MaskMetrics,
    val latencyMs: Long,
) {
    /**
     * The exact shape `LocalCutoutResult.fromMap` decodes in Dart (§4).
     *
     * Note what is NOT here: the operation DIRECTORY. Dart reads the two files (to
     * show the preview and to upload the mask) but never receives a path it is
     * expected to delete — cleanup goes back over the channel as an operation id,
     * which native re-validates and resolves inside its own root (blocker R10b).
     */
    fun toMap(): Map<String, Any?> = mapOf(
        "engine" to GoogleSubjectSegmenterEngine.ENGINE_NAME,
        "engineVersion" to engineVersion,
        "operationId" to operationId,
        "maskFilePath" to maskFilePath,
        "cutoutFilePath" to cutoutFilePath,
        "latencyMs" to latencyMs.toInt(),
        "metrics" to mapOf(
            "width" to metrics.width,
            "height" to metrics.height,
            "subjectCount" to metrics.subjectCount,
            "foregroundAreaRatio" to metrics.foregroundAreaRatio,
            "borderForegroundRatio" to metrics.borderForegroundRatio,
            "uncertainPixelRatio" to metrics.uncertainPixelRatio,
            "meanForegroundConfidence" to metrics.meanForegroundConfidence,
            "foregroundBounds" to metrics.bounds?.let {
                mapOf(
                    "left" to it.startX.toDouble(),
                    "top" to it.startY.toDouble(),
                    "right" to (it.startX + it.width).toDouble(),
                    "bottom" to (it.startY + it.height).toDouble(),
                )
            },
        ),
    )
}
