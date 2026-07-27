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
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import java.util.concurrent.CancellationException
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * The real Google ML Kit Subject Segmentation adapter (local BG §2.1, §8.2).
 *
 * The ONLY class that imports ML Kit. Everything above it programs against
 * [SubjectSegmentationClient], so the engine's behaviour is unit-tested with
 * fakes and this adapter is covered by the compile check plus device QA.
 *
 * ⚠ `play-services-mlkit-subject-segmentation` is still **16.0.0-beta1**. The whole
 * path is gated OFF by default and every failure here is typed, so a beta
 * regression degrades to the existing Azure BiRefNet flow rather than breaking
 * Add Garment.
 *
 * Enabled outputs are exactly what the product needs (founder decision):
 *   * the full foreground confidence mask — the authoritative soft alpha;
 *   * multiple subjects WITH per-subject confidence masks, for bounds + counts.
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

    private fun options(): SubjectSegmenterOptions =
        SubjectSegmenterOptions.Builder()
            .enableForegroundConfidenceMask()
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
            val result = await(requireSegmenter().process(input), timeoutMs)

            val buffer = result.foregroundConfidenceMask
                ?: throw LocalCutoutException(
                    LocalCutoutErrors.INVALID_OUTPUT,
                    "ML Kit returned no foreground confidence mask.",
                )
            val confidence = FloatArray(buffer.remaining())
            buffer.get(confidence)

            val subjects = result.subjects.map {
                SubjectBounds(
                    startX = it.startX,
                    startY = it.startY,
                    width = it.width,
                    height = it.height,
                )
            }
            return SegmentationOutput(confidence, subjects)
        } finally {
            // The InputImage no longer needs it, and this is the largest allocation
            // in the operation.
            bitmap?.recycle()
        }
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
