package com.fashionos.app.background

import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Engine orchestration against deterministic fakes (local BG §11.3).
 *
 * No device, no Google Play services, no model download, no `android.graphics`.
 * The two SDK adapters are behind interfaces precisely so the parts that decide
 * BEHAVIOUR — preparation, error typing, cancellation, cleanup, the concurrency
 * guard — can be proven here in milliseconds.
 */
class GoogleSubjectSegmenterEngineTest {

    private lateinit var tempRoot: File
    private lateinit var cache: LocalCutoutCacheStore

    private val width = 4
    private val height = 4
    private val pixelCount = width * height

    @Before
    fun setUp() {
        tempRoot = File.createTempFile("wtm-engine-test", "").let {
            it.delete(); it.mkdirs(); it
        }
        cache = LocalCutoutCacheStore(
            File(tempRoot, LocalCutoutCacheStore.ROOT_DIR_NAME).apply { mkdirs() },
        )
    }

    @After
    fun tearDown() {
        tempRoot.deleteRecursively()
    }

    // ── fakes ───────────────────────────────────────────────────────────────

    private class FakeClient(
        var availability: ModuleAvailability = ModuleAvailability.AVAILABLE,
        var installResult: ModuleAvailability = ModuleAvailability.AVAILABLE,
        var initError: LocalCutoutException? = null,
        var segmentError: LocalCutoutException? = null,
        var output: SegmentationOutput? = null,
        var availabilityThrows: Exception? = null,
        var installThrows: Exception? = null,
    ) : SubjectSegmentationClient {
        var availabilityCalls = 0
        var installCalls = 0
        var initCalls = 0
        var segmentCalls = 0
        var closeCalls = 0
        var lastUrgent: Boolean? = null
        var onSegment: (() -> Unit)? = null

        override fun moduleAvailability(timeoutMs: Long): ModuleAvailability {
            availabilityCalls++
            availabilityThrows?.let { throw it }
            return availability
        }

        override fun requestModuleInstall(timeoutMs: Long, urgent: Boolean): ModuleAvailability {
            installCalls++
            lastUrgent = urgent
            installThrows?.let { throw it }
            return installResult
        }

        override fun awaitInitialization(timeoutMs: Long) {
            initCalls++
            initError?.let { throw it }
        }

        override fun segment(image: DecodedImage, timeoutMs: Long): SegmentationOutput {
            segmentCalls++
            onSegment?.invoke()
            segmentError?.let { throw it }
            val count = image.width * image.height
            return output ?: SegmentationOutput(
                // Top half at full confidence: coverage 0.5, inside the accepted
                // band. A full-frame mask is refused outright now (§5), so the
                // default has to look like a real garment cutout.
                FloatArray(count) { if (it < count / 2) 1f else 0f },
                listOf(SubjectBounds(0, 0, image.width, image.height / 2)),
            )
        }

        override fun close() {
            closeCalls++
        }
    }

    private inner class FakeCodec(
        var decodeError: LocalCutoutException? = null,
        var emptyEncode: Boolean = false,
    ) : BitmapCodec {
        var decodeCalls = 0
        var lastDecoded: ByteArray? = null

        override fun decode(bytes: ByteArray): DecodedImage {
            decodeCalls++
            lastDecoded = bytes
            decodeError?.let { throw it }
            return DecodedImage(IntArray(pixelCount) { 0xFF804020.toInt() }, width, height)
        }

        override fun encodeMaskPng(alpha: ByteArray, width: Int, height: Int): ByteArray =
            if (emptyEncode) ByteArray(0) else ByteArray(32) { 1 }

        override fun encodeCutoutPng(argb: IntArray, width: Int, height: Int): ByteArray =
            if (emptyEncode) ByteArray(0) else ByteArray(64) { 2 }
    }

    private fun engine(
        client: FakeClient = FakeClient(),
        codec: FakeCodec = FakeCodec(),
        guard: SingleOperationGuard = SingleOperationGuard(),
        clock: () -> Long = System::currentTimeMillis,
    ) = GoogleSubjectSegmenterEngine(client, codec, cache, guard, clock)

    private fun jpeg() = ByteArray(128) { 7 }

    // ── capability + preparation ────────────────────────────────────────────

    @Test
    fun `model already available needs no install`() {
        val client = FakeClient(availability = ModuleAvailability.AVAILABLE)
        val result = engine(client).prepare(5_000, urgent = false)

        assertEquals(ModuleAvailability.AVAILABLE, result)
        assertEquals(0, client.installCalls)
        // Initialisation is warmed so the first real add is not charged for it.
        assertEquals(1, client.initCalls)
    }

    @Test
    fun `model not installed triggers a deferred install by default`() {
        val client = FakeClient(
            availability = ModuleAvailability.NOT_INSTALLED,
            installResult = ModuleAvailability.NOT_INSTALLED,
        )
        val result = engine(client).prepare(5_000, urgent = false)

        assertEquals(1, client.installCalls)
        assertEquals(false, client.lastUrgent)
        assertEquals(ModuleAvailability.NOT_INSTALLED, result)
    }

    @Test
    fun `an urgent preparation is passed through`() {
        val client = FakeClient(availability = ModuleAvailability.NOT_INSTALLED)
        engine(client).prepare(5_000, urgent = true)
        assertEquals(true, client.lastUrgent)
    }

    @Test
    fun `missing Play Services skips the install attempt entirely`() {
        // There is nothing to install against, so asking would just burn the budget.
        val client = FakeClient(availability = ModuleAvailability.PLAY_SERVICES_UNAVAILABLE)
        val result = engine(client).prepare(5_000, urgent = true)

        assertEquals(ModuleAvailability.PLAY_SERVICES_UNAVAILABLE, result)
        assertEquals(0, client.installCalls)
    }

    @Test
    fun `a download failure is reported, never thrown`() {
        val client = FakeClient(
            availability = ModuleAvailability.NOT_INSTALLED,
            installThrows = RuntimeException("network down"),
        )
        assertEquals(ModuleAvailability.DOWNLOAD_FAILED, engine(client).prepare(5_000, true))
    }

    @Test
    fun `a throwing availability probe degrades to UNKNOWN rather than crashing`() {
        val client = FakeClient(availabilityThrows = RuntimeException("play services died"))
        assertEquals(ModuleAvailability.UNKNOWN, engine(client).capability(1_000))
    }

    @Test
    fun `a warm-up initialisation failure does not fail preparation`() {
        val client = FakeClient(
            availability = ModuleAvailability.AVAILABLE,
            initError = LocalCutoutException(LocalCutoutErrors.TIMEOUT, "slow"),
        )
        assertEquals(ModuleAvailability.AVAILABLE, engine(client).prepare(5_000, false))
    }

    @Test
    fun `availability maps to the right error code and wire name`() {
        assertEquals(
            LocalCutoutErrors.MISSING_PLAY_SERVICES,
            ModuleAvailability.PLAY_SERVICES_UNAVAILABLE.toErrorCode(),
        )
        assertEquals(
            LocalCutoutErrors.MODEL_NOT_INSTALLED,
            ModuleAvailability.NOT_INSTALLED.toErrorCode(),
        )
        assertEquals(
            LocalCutoutErrors.MODEL_DOWNLOAD_FAILED,
            ModuleAvailability.DOWNLOAD_FAILED.toErrorCode(),
        )
        assertEquals(
            "missing_google_play_services",
            ModuleAvailability.PLAY_SERVICES_UNAVAILABLE.toWireName(),
        )
        assertEquals("available", ModuleAvailability.AVAILABLE.toWireName())
        assertEquals("temporarily_unavailable", ModuleAvailability.UNKNOWN.toWireName())
    }

    // ── happy path ──────────────────────────────────────────────────────────

    @Test
    fun `a successful run writes both files and reports metrics`() {
        val client = FakeClient(
            output = SegmentationOutput(
                FloatArray(pixelCount) { if (it < pixelCount / 2) 1f else 0f },
                listOf(SubjectBounds(0, 0, 4, 2)),
            ),
        )
        val result = engine(client).removeBackground(jpeg(), 10_000)

        assertTrue(LocalCutoutCacheStore.isValidOperationId(result.operationId))
        assertTrue(File(result.maskFilePath).isFile)
        assertTrue(File(result.cutoutFilePath).isFile)
        assertTrue(File(result.maskFilePath).length() > 0)
        assertTrue(File(result.cutoutFilePath).length() > 0)
        assertEquals(width, result.metrics.width)
        assertEquals(height, result.metrics.height)
        assertEquals(1, result.metrics.subjectCount)
        assertEquals(0.5, result.metrics.foregroundAreaRatio, 1e-9)
        assertNotNull(result.metrics.bounds)
    }

    @Test
    fun `the engine segments the EXACT bytes it was given`() {
        // Same bytes to the engine and to the upload — the only way local mask
        // dimensions and the stored original can be guaranteed to agree (§8.1).
        val codec = FakeCodec()
        val bytes = jpeg()
        engine(codec = codec).removeBackground(bytes, 10_000)
        assertTrue(bytes === codec.lastDecoded)
    }

    @Test
    fun `output files live inside the cache root`() {
        val result = engine().removeBackground(jpeg(), 10_000)
        assertTrue(cache.isContained(File(result.maskFilePath)))
        assertTrue(cache.isContained(File(result.cutoutFilePath)))
    }

    @Test
    fun `the serialised map matches the Dart contract`() {
        val map = engine().removeBackground(jpeg(), 10_000).toMap()

        assertEquals("google_mlkit", map["engine"])
        assertTrue((map["engineVersion"] as String).isNotEmpty())
        assertTrue((map["operationId"] as String).isNotEmpty())
        assertTrue((map["maskFilePath"] as String).isNotEmpty())
        assertTrue((map["cutoutFilePath"] as String).isNotEmpty())
        assertTrue(map["latencyMs"] is Int)

        @Suppress("UNCHECKED_CAST")
        val metrics = map["metrics"] as Map<String, Any?>
        for (key in listOf(
            "width", "height", "subjectCount", "foregroundAreaRatio",
            "borderForegroundRatio", "uncertainPixelRatio", "meanForegroundConfidence",
        )) {
            assertNotNull("missing $key", metrics[key])
        }
    }

    @Test
    fun `no reported subject is a typed NO_SUBJECT failure`() {
        // Changed 2026-07-29: this used to succeed with null bounds. Requiring at
        // least one subject is what makes per-subject reconstruction possible when
        // the full mask is corrupt, and "a mask with no subject" is the engine
        // saying it found nothing (§5).
        val client = FakeClient(
            output = SegmentationOutput(
                FloatArray(pixelCount) { if (it < pixelCount / 2) 1f else 0f },
                emptyList(),
            ),
        )
        assertEquals(
            LocalCutoutErrors.NO_SUBJECT,
            codeOf { engine(client).removeBackground(jpeg(), 10_000) },
        )
    }

    @Test
    fun `bounds are omitted when a subject reports a degenerate box`() {
        // unionBounds still has to cope with a zero-area subject without inventing a
        // box, which is what the old test was really protecting.
        val client = FakeClient(
            output = SegmentationOutput(
                FloatArray(pixelCount) { if (it < pixelCount / 2) 1f else 0f },
                listOf(SubjectBounds(0, 0, 0, 0)),
            ),
        )

        @Suppress("UNCHECKED_CAST")
        val metrics = engine(client).removeBackground(jpeg(), 10_000)
            .toMap()["metrics"] as Map<String, Any?>
        assertNull(metrics["foregroundBounds"])
    }

    // ── typed failures ──────────────────────────────────────────────────────

    private fun codeOf(block: () -> Unit): String? =
        (runCatching(block).exceptionOrNull() as? LocalCutoutException)?.code

    @Test
    fun `an unavailable model fails with its typed code and writes nothing`() {
        val client = FakeClient(availability = ModuleAvailability.NOT_INSTALLED)
        val code = codeOf { engine(client).removeBackground(jpeg(), 10_000) }

        assertEquals(LocalCutoutErrors.MODEL_NOT_INSTALLED, code)
        assertEquals(0, cache.rootFileCount())
    }

    @Test
    fun `missing Play Services fails with its typed code`() {
        val client = FakeClient(availability = ModuleAvailability.PLAY_SERVICES_UNAVAILABLE)
        assertEquals(
            LocalCutoutErrors.MISSING_PLAY_SERVICES,
            codeOf { engine(client).removeBackground(jpeg(), 10_000) },
        )
    }

    @Test
    fun `empty source bytes are rejected`() {
        assertEquals(
            LocalCutoutErrors.INVALID_OUTPUT,
            codeOf { engine().removeBackground(ByteArray(0), 10_000) },
        )
    }

    @Test
    fun `a decode failure is typed and leaves no directory`() {
        val codec = FakeCodec(
            decodeError = LocalCutoutException(LocalCutoutErrors.INVALID_OUTPUT, "bad jpeg"),
        )
        assertEquals(
            LocalCutoutErrors.INVALID_OUTPUT,
            codeOf { engine(codec = codec).removeBackground(jpeg(), 10_000) },
        )
        assertEquals(0, cache.rootFileCount())
    }

    @Test
    fun `an initialisation failure surfaces its own code`() {
        val client = FakeClient(
            initError = LocalCutoutException(LocalCutoutErrors.TIMEOUT, "init timed out"),
        )
        assertEquals(
            LocalCutoutErrors.TIMEOUT,
            codeOf { engine(client).removeBackground(jpeg(), 10_000) },
        )
    }

    @Test
    fun `a segmentation timeout surfaces as TIMEOUT`() {
        val client = FakeClient(
            segmentError = LocalCutoutException(LocalCutoutErrors.TIMEOUT, "inference timed out"),
        )
        assertEquals(
            LocalCutoutErrors.TIMEOUT,
            codeOf { engine(client).removeBackground(jpeg(), 10_000) },
        )
    }

    @Test
    fun `a confidence buffer of the wrong length is INVALID_OUTPUT`() {
        // A subject IS reported, so the failure under test is the buffer length and
        // not the no-subject guard. With no per-subject mask to rebuild from, the
        // length mismatch is terminal.
        val client = FakeClient(
            output = SegmentationOutput(
                FloatArray(pixelCount - 1) { 1f },
                listOf(SubjectBounds(0, 0, width, height / 2)),
            ),
        )
        assertEquals(
            LocalCutoutErrors.INVALID_OUTPUT,
            codeOf { engine(client).removeBackground(jpeg(), 10_000) },
        )
    }

    @Test
    fun `an entirely empty mask with no subjects is NO_SUBJECT`() {
        val client = FakeClient(
            output = SegmentationOutput(FloatArray(pixelCount) { 0f }, emptyList()),
        )
        assertEquals(
            LocalCutoutErrors.NO_SUBJECT,
            codeOf { engine(client).removeBackground(jpeg(), 10_000) },
        )
        assertEquals(0, cache.rootFileCount())
    }

    @Test
    fun `an empty encoder result never becomes a successful response`() {
        assertEquals(
            LocalCutoutErrors.INVALID_OUTPUT,
            codeOf {
                engine(codec = FakeCodec(emptyEncode = true)).removeBackground(jpeg(), 10_000)
            },
        )
        assertEquals(0, cache.rootFileCount())
    }

    @Test
    fun `an unexpected exception is wrapped as INTERNAL, never leaked raw`() {
        val client = FakeClient()
        client.onSegment = { throw IllegalStateException("boom") }
        assertEquals(
            LocalCutoutErrors.INTERNAL,
            codeOf { engine(client).removeBackground(jpeg(), 10_000) },
        )
    }

    // ── cancellation, concurrency, lifecycle ────────────────────────────────

    @Test
    fun `a cancelled operation aborts and cleans up`() {
        val guard = SingleOperationGuard()
        val client = FakeClient()
        // Cancel mid-flight, at the moment inference is running.
        client.onSegment = { guard.cancel() }

        assertEquals(
            LocalCutoutErrors.CANCELLED,
            codeOf { engine(client, guard = guard).removeBackground(jpeg(), 10_000) },
        )
        assertEquals(0, cache.rootFileCount())
    }

    @Test
    fun `a second concurrent operation is rejected as BUSY`() {
        // Two memory-heavy segmentations at once is the shape of an OOM on a
        // mid-range device, so the second caller is turned away rather than queued.
        val guard = SingleOperationGuard()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val slowClient = FakeClient()
        slowClient.onSegment = {
            started.countDown()
            release.await(5, TimeUnit.SECONDS)
        }
        val slowEngine = engine(slowClient, guard = guard)
        val secondEngine = engine(FakeClient(), guard = guard)

        val thread = Thread { runCatching { slowEngine.removeBackground(jpeg(), 10_000) } }
        thread.start()
        assertTrue(started.await(5, TimeUnit.SECONDS))

        val code = codeOf { secondEngine.removeBackground(jpeg(), 10_000) }
        release.countDown()
        thread.join(5_000)

        assertEquals(LocalCutoutErrors.BUSY, code)
    }

    @Test
    fun `the guard is released so a later operation succeeds`() {
        val guard = SingleOperationGuard()
        val e = engine(guard = guard)
        e.removeBackground(jpeg(), 10_000)
        assertFalse(guard.isBusy)
        assertNull(guard.activeOperationId)
        // A second, sequential run is fine.
        assertNotNull(e.removeBackground(jpeg(), 10_000))
    }

    @Test
    fun `the guard is released even when the operation fails`() {
        val guard = SingleOperationGuard()
        val client = FakeClient(availability = ModuleAvailability.NOT_INSTALLED)
        runCatching { engine(client, guard = guard).removeBackground(jpeg(), 10_000) }
        assertFalse(guard.isBusy)
    }

    @Test
    fun `cleanup by operation id is idempotent`() {
        val e = engine()
        val result = e.removeBackground(jpeg(), 10_000)

        assertTrue(e.cleanup(result.operationId))
        assertFalse(File(result.maskFilePath).exists())
        assertTrue(e.cleanup(result.operationId))
    }

    @Test
    fun `cleanup refuses anything that is not a valid operation id`() {
        val e = engine()
        assertFalse(e.cleanup(""))
        assertFalse(e.cleanup("../.."))
        assertFalse(e.cleanup(tempRoot.absolutePath))
        assertTrue(tempRoot.exists())
    }

    @Test
    fun `the stale sweep uses the engine clock`() {
        var now = 1_000_000L
        val e = engine(clock = { now })
        val result = e.removeBackground(jpeg(), 10_000)
        cache.operationDir(result.operationId).setLastModified(now)

        assertEquals(0, e.sweepCache(60_000))
        now += 120_000
        assertEquals(1, e.sweepCache(60_000))
    }

    @Test
    fun `close releases the segmenter and clears scratch files`() {
        val client = FakeClient()
        val e = engine(client)
        e.removeBackground(jpeg(), 10_000)
        assertTrue(cache.rootFileCount() > 0)

        e.close()

        assertEquals(1, client.closeCalls)
        assertEquals(0, cache.rootFileCount())
    }

    @Test
    fun `close is safe to call twice - detach then activity destroy`() {
        val client = FakeClient()
        val e = engine(client)
        e.close()
        e.close()
        assertEquals(2, client.closeCalls) // idempotent at the client level
    }

    @Test
    fun `close survives a throwing client`() {
        val throwing = object : SubjectSegmentationClient {
            override fun moduleAvailability(timeoutMs: Long) = ModuleAvailability.AVAILABLE
            override fun requestModuleInstall(timeoutMs: Long, urgent: Boolean) =
                ModuleAvailability.AVAILABLE

            override fun awaitInitialization(timeoutMs: Long) = Unit
            override fun segment(image: DecodedImage, timeoutMs: Long) =
                SegmentationOutput(FloatArray(0), emptyList())

            override fun close() = throw RuntimeException("close blew up")
        }
        // Teardown must never propagate — it runs from activity destroy.
        GoogleSubjectSegmenterEngine(throwing, FakeCodec(), cache).close()
    }

    // ── structured stage logging (§10) ──────────────────────────────────

    private fun loggingEngine(
        client: FakeClient,
        messages: MutableList<String>,
    ) = GoogleSubjectSegmenterEngine(
        client,
        FakeCodec(),
        cache,
        SingleOperationGuard(),
        System::currentTimeMillis,
        GoogleSubjectSegmenterEngine.DEFAULT_ENGINE_VERSION,
        LocalCutoutLogger { messages.add(it) },
    )

    @Test
    fun `stage timings are logged without any identifying data`() {
        val messages = mutableListOf<String>()
        val engine = loggingEngine(FakeClient(), messages)

        val result = engine.removeBackground(jpeg(), 10_000)

        val stages = messages.single { it.startsWith("local cutout stages") }
        // Durations and counts are present...
        for (key in listOf(
            "decode_ms=", "init_ms=", "inference_ms=", "mask_ms=",
            "composite_ms=", "write_ms=", "total_ms=", "subjects=", "coverage=",
        )) {
            assertTrue("missing $key in: $stages", stages.contains(key))
        }
        // ...and nothing that could identify the user or the photo (§10).
        assertFalse(stages.contains(result.operationId))
        assertFalse(stages.contains(result.maskFilePath))
        assertFalse(stages.contains(result.cutoutFilePath))
        assertFalse(stages.contains(cache.rootPath))
        assertFalse(stages.contains(".png"))
        assertFalse(stages.contains("/"))
    }

    @Test
    fun `a failure logs only safe categories, never a path or a filename`() {
        val messages = mutableListOf<String>()
        val engine = loggingEngine(
            FakeClient(availability = ModuleAvailability.NOT_INSTALLED),
            messages,
        )

        runCatching { engine.removeBackground(jpeg(), 10_000) }

        for (message in messages) {
            assertFalse(message.contains("/"))
            assertFalse(message.contains(".png"))
        }
    }

    private fun LocalCutoutCacheStore.rootFileCount(): Int =
        File(rootPath).listFiles()?.size ?: 0
}
