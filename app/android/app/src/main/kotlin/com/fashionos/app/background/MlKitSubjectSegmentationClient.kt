package com.fashionos.app.background

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentationResult
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import java.util.concurrent.CancellationException
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * The real Google ML Kit Subject Segmentation adapter (local BG §2.1, §8.2).
 *
 * The ONLY class that imports ML Kit. Everything above it programs against
 * [SubjectSegmentationClient], so the engine's behaviour is unit-tested with
 * fakes and this adapter is covered by the compile check plus device QA.
 *
 * ⚠ `play-services-mlkit-subject-segmentation` is still **16.0.0-beta1**, and on this
 * device its full foreground buffer is unusable — see [options]. A typed failure
 * degrades to the existing Azure BiRefNet flow; a native crash inside the SDK does
 * NOT, which is the standing risk with this dependency.
 *
 * Enabled outputs: multiple subjects WITH per-subject confidence masks, and nothing
 * else. The per-subject masks are the authoritative soft alpha (reconstructed by
 * `SoftMask.combineSubjectMasks`); the full foreground mask is not requested.
 * Foreground/per-subject BITMAPS are deliberately NOT enabled: each is another
 * full-resolution ARGB_8888 allocation, and we composite from the source bitmap
 * we already hold.
 *
 * Every call blocks with a bound — callers are already on a background executor.
 */
class MlKitSubjectSegmentationClient(
    context: Context,
) : SubjectSegmentationClient {

    private val appContext = context.applicationContext
    private val lock = Any()
    private var segmenter: SubjectSegmenter? = null
    private var closed = false

    /**
     * Per-subject confidence masks ONLY.
     *
     * `enableForegroundConfidenceMask()` is deliberately absent. On this SDK version
     * that buffer came back 15%–96% NaN/out-of-range, varying run to run, and copying
     * it inside the success callback on a direct executor did not help — so it is
     * corrupt at the source and must not be read at all. The per-subject masks from
     * the same result measured zero NaN with a deterministic, bounded overshoot, so
     * the authoritative mask is reconstructed from those instead (§1, §2).
     */
    private fun options(): SubjectSegmenterOptions =
        SubjectSegmenterOptions.Builder()
            .enableMultipleSubjects(
                SubjectSegmenterOptions.SubjectResultOptions.Builder()
                    .enableConfidenceMask()
                    .build(),
            )
            .build()

    /** One reusable segmenter for the plugin's lifetime (§8.2). */
    private fun requireSegmenter(): SubjectSegmenter = synchronized(lock) {
        if (closed) {
            throw LocalCutoutException(LocalCutoutErrors.CANCELLED, "Engine is closed.")
        }
        segmenter ?: SubjectSegmentation.getClient(options()).also { segmenter = it }
    }

    override fun moduleAvailability(timeoutMs: Long): ModuleAvailability {
        return try {
            val client = ModuleInstall.getClient(appContext)
            val response = await(client.areModulesAvailable(requireSegmenter()), timeoutMs)
            if (response.areModulesAvailable()) {
                ModuleAvailability.AVAILABLE
            } else {
                ModuleAvailability.NOT_INSTALLED
            }
        } catch (e: LocalCutoutException) {
            if (e.code == LocalCutoutErrors.TIMEOUT) ModuleAvailability.UNKNOWN else throw e
        } catch (e: Exception) {
            // Play services absent/disabled/too old — a normal outcome on AOSP and
            // de-Googled devices, never a crash (§2.1).
            Log.w(TAG, "module availability unavailable: ${e.javaClass.simpleName}")
            ModuleAvailability.PLAY_SERVICES_UNAVAILABLE
        }
    }

    override fun requestModuleInstall(timeoutMs: Long, urgent: Boolean): ModuleAvailability {
        return try {
            val client = ModuleInstall.getClient(appContext)
            val api = requireSegmenter()
            if (!urgent) {
                // Deferred: Play services fetches it in the background at its own
                // pace. Nothing blocks, and the NEXT add finds it ready.
                client.deferredInstall(api)
                return ModuleAvailability.NOT_INSTALLED
            }
            val request = ModuleInstallRequest.newBuilder().addApi(api).build()
            await(client.installModules(request), timeoutMs)
            val response = await(client.areModulesAvailable(api), timeoutMs)
            if (response.areModulesAvailable()) {
                ModuleAvailability.AVAILABLE
            } else {
                ModuleAvailability.DOWNLOAD_FAILED
            }
        } catch (e: Exception) {
            Log.w(TAG, "module install failed: ${e.javaClass.simpleName}")
            ModuleAvailability.DOWNLOAD_FAILED
        }
    }

    override fun awaitInitialization(timeoutMs: Long) {
        // getInitTask() lets us pay model initialisation BEFORE the user's first
        // add, instead of on top of that add's inference.
        await(requireSegmenter().initTask, timeoutMs)
    }

    /**
     * Run segmentation, copying every buffer **inside** ML Kit's success callback.
     *
     * This is not stylistic. Reading `foregroundConfidenceMask` after
     * `Tasks.await()` returned produced ~69% NaN/out-of-range floats in row-shaped
     * blocks on a POCO X3 (2026-07-29 diagnostic) — the SDK had already reused the
     * native memory. Copying on the completing thread, before the callback returns
     * and while `result` is still strongly referenced by the listener frame, is the
     * earliest point at which the data is guaranteed to be ours.
     *
     * A direct executor is used deliberately: the default posts listeners to the main
     * looper, which both widens the window and would deadlock a main-thread caller.
     * Everything crossing back out is an app-owned array.
     */
    override fun segment(image: DecodedImage, timeoutMs: Long): SegmentationOutput {
        var bitmap: Bitmap? = null
        try {
            bitmap = Bitmap.createBitmap(
                image.pixels,
                image.width,
                image.height,
                Bitmap.Config.ARGB_8888,
            )
            // Rotation 0: the bytes are already EXIF-stripped and upright (§8.1).
            val input = InputImage.fromBitmap(bitmap, 0)

            // Exactly-once completion: whichever listener fires first wins, the rest
            // are no-ops. Holds either a SegmentationOutput or a Throwable.
            val outcome = OneShotOutcome()
            val direct = Executor { it.run() }

            requireSegmenter().process(input)
                .addOnSuccessListener(direct) { result ->
                    // COPY EVERYTHING NOW. `result` is alive for this whole block.
                    outcome.settle(runCatching { copyOut(result) }.fold({ it }, { it }))
                }
                .addOnFailureListener(direct) { e -> outcome.settle(e) }
                .addOnCanceledListener(direct) {
                    outcome.settle(CancellationException("ML Kit cancelled the request."))
                }

            if (!outcome.await(timeoutMs)) {
                throw LocalCutoutException(LocalCutoutErrors.TIMEOUT, "ML Kit timed out.")
            }
            return when (val value = outcome.get()) {
                is SegmentationOutput -> value
                is LocalCutoutException -> throw value
                is CancellationException ->
                    throw LocalCutoutException(LocalCutoutErrors.CANCELLED, "ML Kit cancelled.", value)
                is Throwable -> throw LocalCutoutException(
                    LocalCutoutErrors.INTERNAL,
                    "ML Kit failed: ${value.javaClass.simpleName}",
                    value,
                )
                else -> throw LocalCutoutException(
                    LocalCutoutErrors.INTERNAL,
                    "ML Kit produced no result.",
                )
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            throw LocalCutoutException(LocalCutoutErrors.CANCELLED, "Interrupted.", e)
        } finally {
            // The InputImage no longer needs it, and this is the largest allocation
            // in the operation.
            bitmap?.recycle()
        }
    }

    /**
     * Deep-copy an ML Kit result into app-owned memory. Runs inside the callback.
     *
     * Every buffer is duplicated and rewound rather than read at its current
     * position: the old code used `remaining()`, which silently depends on a position
     * the SDK controls.
     */
    private fun copyOut(result: SubjectSegmentationResult): SegmentationOutput {
        // The foreground mask is NOT requested and NOT read — see options().
        val foreground = FloatArray(0)
        val subjects = ArrayList<SubjectBounds>()
        val masks = ArrayList<SubjectConfidenceMask>()
        for (subject in result.subjects) {
            val bounds = SubjectBounds(
                startX = subject.startX,
                startY = subject.startY,
                width = subject.width,
                height = subject.height,
            )
            subjects.add(bounds)
            masks.add(SubjectConfidenceMask(bounds, subject.confidenceMask?.let { copyFloatBuffer(it) }))
        }
        return SegmentationOutput(foreground, subjects, masks)
    }


    override fun close() {
        synchronized(lock) {
            closed = true
            runCatching { segmenter?.close() }
                .onFailure { Log.w(TAG, "segmenter close failed: ${it.javaClass.simpleName}") }
            segmenter = null
        }
    }

    /** Bounded blocking await that maps Play-services failures to typed errors. */
    private fun <T> await(task: Task<T>, timeoutMs: Long): T =
        try {
            Tasks.await(task, timeoutMs.coerceAtLeast(1L), TimeUnit.MILLISECONDS)
        } catch (e: TimeoutException) {
            throw LocalCutoutException(LocalCutoutErrors.TIMEOUT, "ML Kit timed out.", e)
        } catch (e: CancellationException) {
            throw LocalCutoutException(LocalCutoutErrors.CANCELLED, "ML Kit cancelled.", e)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            throw LocalCutoutException(LocalCutoutErrors.CANCELLED, "Interrupted.", e)
        } catch (e: ExecutionException) {
            throw LocalCutoutException(
                LocalCutoutErrors.INTERNAL,
                "ML Kit failed: ${e.cause?.javaClass?.simpleName ?: "unknown"}",
                e,
            )
        }

    private companion object {
        const val TAG = "WtmLocalCutout"
    }
}
