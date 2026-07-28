package com.fashionos.app.background

import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * End-to-end integrity of the local path (local BG §1, §4, §5).
 *
 * What the engine must guarantee before it reports success, proven against fakes:
 * a corrupt confidence buffer never becomes a cutout; a bad full mask falls back to
 * per-subject reconstruction rather than to the cloud; a coverage extreme is refused;
 * and no scratch file survives an invalid result.
 *
 * These are the guarantees that were missing when a 69%-NaN buffer from ML Kit
 * `16.0.0-beta1` sailed through to a saved wardrobe item on 2026-07-29.
 */
class LocalCutoutIntegrityTest {

    private lateinit var tempRoot: File
    private lateinit var cache: LocalCutoutCacheStore

    private val width = 8
    private val height = 8
    private val pixels = width * height

    @Before
    fun setUp() {
        tempRoot = File.createTempFile("wtm-integrity", "").let { it.delete(); it.mkdirs(); it }
        cache = LocalCutoutCacheStore(
            File(tempRoot, LocalCutoutCacheStore.ROOT_DIR_NAME).apply { mkdirs() },
        )
    }

    @After
    fun tearDown() {
        tempRoot.deleteRecursively()
    }

    // ── fakes ───────────────────────────────────────────────────────────────

    private inner class Client(var output: SegmentationOutput?) : SubjectSegmentationClient {
        override fun moduleAvailability(timeoutMs: Long) = ModuleAvailability.AVAILABLE
        override fun requestModuleInstall(timeoutMs: Long, urgent: Boolean) =
            ModuleAvailability.AVAILABLE

        override fun awaitInitialization(timeoutMs: Long) = Unit
        override fun segment(image: DecodedImage, timeoutMs: Long): SegmentationOutput {
            // Per-subject only — the foreground mask is not requested any more.
            val bounds = SubjectBounds(0, 0, width, height / 2)
            return output ?: SegmentationOutput(
                FloatArray(0),
                listOf(bounds),
                listOf(SubjectConfidenceMask(bounds, FloatArray(width * height / 2) { 1f })),
            )
        }

        override fun close() = Unit
    }

    private inner class Codec : BitmapCodec {
        override fun decode(bytes: ByteArray) =
            DecodedImage(IntArray(pixels) { 0xFF204060.toInt() }, width, height)

        override fun encodeMaskPng(alpha: ByteArray, width: Int, height: Int) = ByteArray(16) { 1 }
        override fun encodeCutoutPng(argb: IntArray, width: Int, height: Int) = ByteArray(32) { 2 }
    }

    private fun engine(output: SegmentationOutput?) =
        GoogleSubjectSegmenterEngine(Client(output), Codec(), cache)

    private fun jpeg() = ByteArray(64) { 3 }

    /** Files left under the cache root, whatever their depth. */
    private fun scratchFiles(): List<File> =
        File(tempRoot, LocalCutoutCacheStore.ROOT_DIR_NAME)
            .walkTopDown().filter { it.isFile }.toList()

    private fun goodSubject() = listOf(SubjectBounds(0, 0, width, height / 2))

    // ── corrupt buffer rejection ────────────────────────────────────────────

    @Test
    fun `a corrupt full mask with no usable subject masks is refused`() {
        val corrupt = FloatArray(pixels) { Float.NaN }
        val e = runCatching {
            engine(SegmentationOutput(corrupt, goodSubject())).removeBackground(jpeg(), 5_000)
        }.exceptionOrNull()

        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, (e as LocalCutoutException).code)
    }

    @Test
    fun `no scratch file survives a refused result`() {
        val corrupt = FloatArray(pixels) { 9e37f }
        runCatching {
            engine(SegmentationOutput(corrupt, goodSubject())).removeBackground(jpeg(), 5_000)
        }
        assertTrue("cache must be clean after an invalid result", scratchFiles().isEmpty())
    }

    @Test
    fun `a mask of the wrong length is refused and leaves nothing behind`() {
        val short = FloatArray(pixels / 2) { 0.9f }
        val e = runCatching {
            engine(SegmentationOutput(short, goodSubject())).removeBackground(jpeg(), 5_000)
        }.exceptionOrNull()
        assertTrue(e is LocalCutoutException)
        assertTrue(scratchFiles().isEmpty())
    }

    // ── per-subject reconstruction (§4) ──────────────────────────────────────

    @Test
    fun `a corrupt full mask is rebuilt from per-subject masks instead of failing`() {
        val corrupt = FloatArray(pixels) { Float.NaN }
        val bounds = SubjectBounds(0, 0, width, height / 2)
        val subjectMask = SubjectConfidenceMask(bounds, FloatArray(width * height / 2) { 1f })

        val result = engine(
            SegmentationOutput(corrupt, listOf(bounds), listOf(subjectMask)),
        ).removeBackground(jpeg(), 5_000)

        // Half the frame at full confidence -> coverage 0.5, inside the band.
        assertEquals(0.5, result.metrics.foregroundAreaRatio, 1e-9)
        assertEquals(1, result.metrics.subjectCount)
        assertTrue(File(result.maskFilePath).isFile)
        assertTrue(File(result.cutoutFilePath).isFile)
    }

    @Test
    fun `reconstruction from a subject mask that also fails is refused`() {
        val corrupt = FloatArray(pixels) { Float.NaN }
        val bounds = SubjectBounds(0, 0, width, height / 2)
        val badSubject = SubjectConfidenceMask(bounds, FloatArray(width * height / 2) { Float.NaN })

        val e = runCatching {
            engine(SegmentationOutput(corrupt, listOf(bounds), listOf(badSubject)))
                .removeBackground(jpeg(), 5_000)
        }.exceptionOrNull()

        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, (e as LocalCutoutException).code)
        assertTrue(scratchFiles().isEmpty())
    }

    // ── completion criteria (§5) ─────────────────────────────────────────────

    @Test
    fun `no reported subject is a typed no-subject failure`() {
        val fine = FloatArray(pixels) { 1f }
        val e = runCatching {
            engine(SegmentationOutput(fine, emptyList())).removeBackground(jpeg(), 5_000)
        }.exceptionOrNull()

        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.NO_SUBJECT, (e as LocalCutoutException).code)
        assertTrue(scratchFiles().isEmpty())
    }

    @Test
    fun `a near-empty mask is refused rather than uploaded`() {
        // A faint single pixel: 0.2/64 = 0.003 mean alpha, under the 0.005 floor.
        val bounds = SubjectBounds(0, 0, width, height / 2)
        val faint = FloatArray(width * height / 2).also { it[0] = 0.2f }
        val e = runCatching {
            engine(
                SegmentationOutput(
                    FloatArray(0),
                    listOf(bounds),
                    listOf(SubjectConfidenceMask(bounds, faint)),
                ),
            ).removeBackground(jpeg(), 5_000)
        }.exceptionOrNull()

        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, (e as LocalCutoutException).code)
        assertTrue((e as LocalCutoutException).message!!.contains("coverage"))
    }

    @Test
    fun `a near-full mask is refused - that is not a cutout`() {
        // A subject covering the WHOLE frame at full confidence -> coverage 1.0.
        val bounds = SubjectBounds(0, 0, width, height)
        val e = runCatching {
            engine(
                SegmentationOutput(
                    FloatArray(0),
                    listOf(bounds),
                    listOf(SubjectConfidenceMask(bounds, FloatArray(pixels) { 1f })),
                ),
            ).removeBackground(jpeg(), 5_000)
        }.exceptionOrNull()

        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.INVALID_OUTPUT, (e as LocalCutoutException).code)
        assertTrue(scratchFiles().isEmpty())
    }

    @Test
    fun `a healthy mask succeeds and reports matching dimensions`() {
        val result = engine(null).removeBackground(jpeg(), 5_000)

        assertEquals(width, result.metrics.width)
        assertEquals(height, result.metrics.height)
        assertEquals(0.5, result.metrics.foregroundAreaRatio, 1e-9)
        assertTrue(File(result.maskFilePath).isFile)
        assertTrue(File(result.cutoutFilePath).isFile)
        assertFalse(scratchFiles().isEmpty())
    }

    // ── cancellation cleanup ─────────────────────────────────────────────────

    @Test
    fun `a cancelled operation leaves no scratch file`() {
        val guard = SingleOperationGuard()
        val client = object : SubjectSegmentationClient {
            override fun moduleAvailability(timeoutMs: Long) = ModuleAvailability.AVAILABLE
            override fun requestModuleInstall(timeoutMs: Long, urgent: Boolean) =
                ModuleAvailability.AVAILABLE

            override fun awaitInitialization(timeoutMs: Long) = Unit
            override fun segment(image: DecodedImage, timeoutMs: Long): SegmentationOutput {
                // Cancel mid-flight, exactly as teardown does.
                guard.cancel()
                return SegmentationOutput(
                    FloatArray(pixels) { if (it < pixels / 2) 1f else 0f },
                    listOf(SubjectBounds(0, 0, width, height / 2)),
                )
            }

            override fun close() = Unit
        }
        val e = runCatching {
            GoogleSubjectSegmenterEngine(client, Codec(), cache, guard)
                .removeBackground(jpeg(), 5_000)
        }.exceptionOrNull()

        assertTrue(e is LocalCutoutException)
        assertEquals(LocalCutoutErrors.CANCELLED, (e as LocalCutoutException).code)
        assertTrue(scratchFiles().isEmpty())
    }

    @Test
    fun `a timeout from the client is typed and leaves nothing behind`() {
        val client = object : SubjectSegmentationClient {
            override fun moduleAvailability(timeoutMs: Long) = ModuleAvailability.AVAILABLE
            override fun requestModuleInstall(timeoutMs: Long, urgent: Boolean) =
                ModuleAvailability.AVAILABLE

            override fun awaitInitialization(timeoutMs: Long) = Unit
            override fun segment(image: DecodedImage, timeoutMs: Long): SegmentationOutput =
                throw LocalCutoutException(LocalCutoutErrors.TIMEOUT, "ML Kit timed out.")

            override fun close() = Unit
        }
        val e = runCatching {
            GoogleSubjectSegmenterEngine(client, Codec(), cache).removeBackground(jpeg(), 5_000)
        }.exceptionOrNull()

        assertEquals(LocalCutoutErrors.TIMEOUT, (e as LocalCutoutException).code)
        assertTrue(scratchFiles().isEmpty())
    }
}
