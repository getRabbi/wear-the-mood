package com.fashionos.app.background

/**
 * Stable error codes for local-first background removal (local BG §4, §8.2).
 *
 * These travel to Dart as `PlatformException.code` and are mirrored exactly by
 * `LocalCutoutErrorCode` in `local_cutout_platform.dart`. They are a SHIPPED
 * CONTRACT: add values, never rename or repurpose one. Dart maps an unrecognised
 * code to a generic native error, so a newer native layer can never break an
 * older Dart layer.
 *
 * Every failure path must produce one of these. An uncaught native exception in
 * the segmentation path would surface to the user as a broken Add Garment, when
 * the correct behaviour is always a quiet fall back to the Azure BiRefNet worker.
 */
object LocalCutoutErrors {
    /** The OS cannot do this at all — Android below API 24. */
    const val UNSUPPORTED = "unsupported"

    /** Google Play services missing or unusable (AOSP / de-Googled device). */
    const val MISSING_PLAY_SERVICES = "missing_play_services"

    /** The `subject_segment` module has not been installed yet. */
    const val MODEL_NOT_INSTALLED = "model_not_installed"

    /** An install was requested and did not complete. */
    const val MODEL_DOWNLOAD_FAILED = "model_download_failed"

    /** The engine ran and found no foreground instance. */
    const val NO_SUBJECT = "no_subject"

    /**
     * Structurally unusable output — an undecodable source, zero dimensions, or a
     * confidence buffer whose length does not match the source.
     */
    const val INVALID_OUTPUT = "invalid_output"

    /** The operation exceeded its bound. */
    const val TIMEOUT = "timeout"

    /** Cancelled explicitly, or by activity/engine teardown. */
    const val CANCELLED = "cancelled"

    /** Another removal is already running — only one at a time is permitted. */
    const val BUSY = "busy"

    /** The operation cache directory could not be created or is not containable. */
    const val CACHE_UNAVAILABLE = "cache_unavailable"

    /** Anything else. */
    const val INTERNAL = "internal"
}

/**
 * A typed failure carrying one of [LocalCutoutErrors].
 *
 * [message] is developer-facing only and must never contain image bytes, file
 * paths, object keys or anything user-identifying (§10) — it is logged and
 * returned to Dart.
 */
class LocalCutoutException(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)
