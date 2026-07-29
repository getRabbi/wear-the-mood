package com.fashionos.app.background

import java.util.concurrent.atomic.AtomicReference

/**
 * The seams that make the engine testable (local BG §11.3).
 *
 * ML Kit needs Google Play services and a downloaded model; `android.graphics`
 * needs a device or Robolectric. Both are hidden behind small interfaces so the
 * engine's ORCHESTRATION — preparation, ordering, cancellation, cleanup, error
 * mapping — runs against deterministic fakes in plain JUnit. Only the two thin
 * adapters that call the real SDKs are left to the compile check and device QA.
 *
 * No DI framework: the repository does not use one, and adding Hilt to inject two
 * interfaces would be a much larger change than the thing it enables.
 */

/** Whether the on-device segmentation model can run right now. */
enum class ModuleAvailability {
    AVAILABLE,
    PLAY_SERVICES_UNAVAILABLE,
    NOT_INSTALLED,
    DOWNLOAD_FAILED,

    /** Play services answered, but not in a way we can interpret. Retryable. */
    UNKNOWN,
    ;

    /** The typed error code this availability produces when work is attempted. */
    fun toErrorCode(): String = when (this) {
        AVAILABLE -> LocalCutoutErrors.INTERNAL
        PLAY_SERVICES_UNAVAILABLE -> LocalCutoutErrors.MISSING_PLAY_SERVICES
        NOT_INSTALLED -> LocalCutoutErrors.MODEL_NOT_INSTALLED
        DOWNLOAD_FAILED -> LocalCutoutErrors.MODEL_DOWNLOAD_FAILED
        UNKNOWN -> LocalCutoutErrors.INTERNAL
    }

    /** The wire value Dart's `LocalCutoutAvailability` decodes. */
    fun toWireName(): String = when (this) {
        AVAILABLE -> "available"
        PLAY_SERVICES_UNAVAILABLE -> "missing_google_play_services"
        NOT_INSTALLED -> "model_not_installed"
        DOWNLOAD_FAILED -> "model_download_failed"
        // Dart maps anything unrecognised to `temporarilyUnavailable`, which is
        // exactly right for UNKNOWN, but be explicit rather than rely on that.
        UNKNOWN -> "temporarily_unavailable"
    }
}

/** A decoded source image: straight ARGB_8888 pixels plus its dimensions. */
class DecodedImage(
    val pixels: IntArray,
    val width: Int,
    val height: Int,
)

/**
 * ML Kit's answer for one image, **fully copied into app-owned memory**.
 *
 * Nothing here may reference an ML Kit buffer. The 2026-07-29 device diagnostic
 * showed `foregroundConfidenceMask` read after `Tasks.await()` returning ~69%
 * NaN/out-of-range values in large row-shaped blocks — the signature of memory the
 * SDK had already reused. Every field is therefore a defensive copy made inside the
 * success callback, before it returns.
 */
class SegmentationOutput(
    /** Row-major foreground confidences in `0.0..1.0`, `width * height` long. */
    val foregroundConfidence: FloatArray,
    val subjects: List<SubjectBounds>,
    /**
     * Per-subject confidence masks, when the SDK supplied them. Used only as a
     * reconstruction source when [foregroundConfidence] is unusable (§4).
     */
    val subjectMasks: List<SubjectConfidenceMask> = emptyList(),
)

/**
 * One subject's confidence mask, copied out of ML Kit.
 *
 * Per the SDK contract the mask is `bounds.width * bounds.height` floats, row-major,
 * covering exactly the subject's bounding box at offset (`bounds.startX`,
 * `bounds.startY`) in the INPUT image. No resizing or coordinate reinterpretation is
 * applied anywhere — a mask whose length disagrees with its bounds is rejected
 * rather than stretched to fit.
 */
class SubjectConfidenceMask(
    val bounds: SubjectBounds,
    val confidence: FloatArray?,
)

/**
 * The ML Kit surface the engine uses. Every method is BLOCKING and bounded — the
 * engine already runs on a background executor, and a bounded blocking call is far
 * easier to reason about (and to fake) than nested Task listeners.
 */
interface SubjectSegmentationClient {
    /** Cheap availability probe. Must not download and must not throw. */
    fun moduleAvailability(timeoutMs: Long): ModuleAvailability

    /**
     * Ask Play services for the model. Implementations should prefer a deferred
     * install and only fall back to an urgent one when [urgent] is set, so a normal
     * app start never blocks on a download.
     */
    fun requestModuleInstall(timeoutMs: Long, urgent: Boolean): ModuleAvailability

    /**
     * Await `SubjectSegmenter.getInitTask()`, so the first real segmentation does
     * not pay initialisation on top of inference.
     */
    fun awaitInitialization(timeoutMs: Long)

    /** Run segmentation. Throws [LocalCutoutException] on timeout/failure. */
    fun segment(image: DecodedImage, timeoutMs: Long): SegmentationOutput

    /** Release the segmenter. Idempotent. */
    fun close()
}

/**
 * Logging seam.
 *
 * The engine must not import `android.util.Log`: in a plain JVM unit test the
 * android.jar stub throws `RuntimeException("Stub!")`, so a diagnostic log on an
 * error path would make that path untestable — which is exactly the path most
 * worth testing. The plugin supplies a real logger; tests get the no-op.
 */
fun interface LocalCutoutLogger {
    fun warn(message: String)

    companion object {
        val NONE = LocalCutoutLogger { }
    }
}

/** Bitmap decode/encode, isolated so the engine needs no Android framework. */
interface BitmapCodec {
    /** Decode the exact compressed JPEG Dart supplied. */
    fun decode(bytes: ByteArray): DecodedImage

    /** Lossless 8-bit grayscale/alpha PNG at full source dimensions. */
    fun encodeMaskPng(alpha: ByteArray, width: Int, height: Int): ByteArray

    /** Lossless transparent PNG at full source dimensions. */
    fun encodeCutoutPng(argb: IntArray, width: Int, height: Int): ByteArray
}

/**
 * Admits one removal at a time.
 *
 * Segmentation holds a decoded bitmap, a float buffer and two pixel arrays at
 * once — several tens of MB for a 1600px photo. Two concurrent runs on a
 * mid-range device is the shape of an OOM, so a second request is REJECTED with
 * [LocalCutoutErrors.BUSY] (Dart treats that as "temporarily unavailable" and
 * uses the cloud path) rather than queued or run in parallel.
 */
class SingleOperationGuard {
    private val current = AtomicReference<String?>(null)
    @Volatile
    private var cancelledId: String? = null

    val activeOperationId: String? get() = current.get()

    val isBusy: Boolean get() = current.get() != null

    /** Claim the slot for [operationId]; false when another run holds it. */
    fun begin(operationId: String): Boolean {
        if (!current.compareAndSet(null, operationId)) return false
        cancelledId = null
        return true
    }

    /** Release the slot if [operationId] still holds it. */
    fun end(operationId: String) {
        current.compareAndSet(operationId, null)
    }

    /** Flag the in-flight run so it aborts at its next checkpoint. */
    fun cancel(operationId: String? = null) {
        val active = current.get() ?: return
        if (operationId == null || operationId == active) cancelledId = active
    }

    fun isCancelled(operationId: String): Boolean = cancelledId == operationId

    /**
     * Abort at a checkpoint. Called between the expensive stages so teardown does
     * not have to interrupt a thread mid-inference.
     */
    fun throwIfCancelled(operationId: String) {
        if (isCancelled(operationId)) {
            throw LocalCutoutException(LocalCutoutErrors.CANCELLED, "Operation cancelled.")
        }
    }
}
