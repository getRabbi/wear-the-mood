package com.fashionos.app.background

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * `wtm/background_removal` — the Flutter bridge for local cutouts (local BG §4, §8.4).
 *
 * Thin by design: it validates arguments, moves work onto a single background
 * thread, and marshals typed errors back. All decisions live in
 * [GoogleSubjectSegmenterEngine]; all SDK contact lives in the adapters.
 *
 * Two lifecycle rules that prevent the classic Flutter plugin crashes:
 *   * every `result.*` call is posted to the main thread;
 *   * after [detach], nothing calls back into Flutter — the engine may already be
 *     gone, and replying to a dead channel throws.
 *
 * The channel is registered unconditionally; the FEATURE is gated in Dart. A build
 * with the gates off simply never calls these methods, and a build on an
 * unsupported OS gets a typed `unsupported` capability instead of an exception.
 */
class WtmBackgroundRemovalPlugin private constructor(
    private val channel: MethodChannel,
    private val engine: GoogleSubjectSegmenterEngine,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    // One worker: segmentation is memory-heavy and the engine admits one operation
    // at a time anyway, so a pool would only add threads that immediately block.
    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "wtm-local-cutout").apply { isDaemon = true }
    }
    private val detached = AtomicBoolean(false)

    companion object {
        const val CHANNEL = "wtm/background_removal"
        private const val TAG = "WtmLocalCutout"

        /** ML Kit Subject Segmentation requires API 24 (local BG §2.1). */
        const val MIN_SDK = Build.VERSION_CODES.N

        private const val DEFAULT_TIMEOUT_MS = 20_000L
        private const val MAX_TIMEOUT_MS = 120_000L
        private const val DEFAULT_SWEEP_MAX_AGE_MS = 6L * 60 * 60 * 1000

        /**
         * Wire the channel. Returns null below API 24, where ML Kit Subject
         * Segmentation cannot run at all — Dart then sees a missing channel and
         * maps it to `unsupported`, which is the correct fallback.
         */
        // Lint correctly notes SDK_INT can never be < 24 while minSdk is 24. The
        // check is kept deliberately: it is the one line that still refuses to
        // register if the floor is ever lowered again, and ML Kit Subject
        // Segmentation genuinely cannot run below 24.
        @Suppress("ObsoleteSdkInt")
        fun register(context: Context, messenger: BinaryMessenger): WtmBackgroundRemovalPlugin? {
            if (Build.VERSION.SDK_INT < MIN_SDK) return null
            return try {
                val cacheRoot = File(context.cacheDir, LocalCutoutCacheStore.ROOT_DIR_NAME)
                    .apply { mkdirs() }
                val engine = GoogleSubjectSegmenterEngine(
                    client = MlKitSubjectSegmentationClient(context),
                    codec = AndroidBitmapCodec(),
                    cache = LocalCutoutCacheStore(cacheRoot),
                    // Messages are exception class names only — never bytes, paths
                    // or user data (§10).
                    logger = LocalCutoutLogger { Log.w(TAG, it) },
                )
                val channel = MethodChannel(messenger, CHANNEL)
                WtmBackgroundRemovalPlugin(channel, engine).also {
                    channel.setMethodCallHandler(it)
                }
            } catch (e: Exception) {
                // A failure here must never stop the app from launching.
                Log.w(TAG, "could not register: ${e.javaClass.simpleName}")
                null
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capability" -> onWorker(result) {
                capabilityMap(engine.capability(timeoutOf(call, 4_000L)))
            }

            "prepare" -> onWorker(result) {
                // `urgent` blocks on a download; the default deferred install lets
                // Play services fetch the model without holding up the caller.
                val urgent = call.argument<Boolean>("urgent") ?: false
                capabilityMap(engine.prepare(timeoutOf(call, 15_000L), urgent))
            }

            "removeBackground" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                if (bytes == null || bytes.isEmpty()) {
                    reply(result) {
                        result.error(
                            LocalCutoutErrors.INVALID_OUTPUT,
                            "No image bytes supplied.",
                            null,
                        )
                    }
                    return
                }
                onWorker(result) {
                    engine.removeBackground(bytes, timeoutOf(call, DEFAULT_TIMEOUT_MS)).toMap()
                }
            }

            "cancel" -> {
                engine.cancel(call.argument<String>("operationId"))
                reply(result) { result.success(null) }
            }

            "cleanup" -> {
                // Operation ID, never a path — see LocalCutoutCacheStore (R10b).
                val id = call.argument<String>("operationId")
                onWorker(result) { engine.cleanup(id ?: "") }
            }

            "sweepCache" -> onWorker(result) {
                val maxAge = (call.argument<Number>("maxAgeMs")?.toLong() ?: DEFAULT_SWEEP_MAX_AGE_MS)
                    .coerceAtLeast(0L)
                engine.sweepCache(maxAge)
            }

            else -> reply(result) { result.notImplemented() }
        }
    }

    /** Run [block] off the main thread and marshal its outcome back typed. */
    private fun onWorker(result: MethodChannel.Result, block: () -> Any?) {
        if (detached.get()) return
        worker.execute {
            val outcome = try {
                Result.success(block())
            } catch (e: LocalCutoutException) {
                Result.failure(e)
            } catch (e: Exception) {
                // Nothing escapes untyped: an uncaught exception here would surface
                // to the user as a broken Add Garment instead of a cloud fallback.
                Log.w(TAG, "operation failed: ${e.javaClass.simpleName}")
                Result.failure(
                    LocalCutoutException(
                        LocalCutoutErrors.INTERNAL,
                        e.javaClass.simpleName,
                        e,
                    ),
                )
            }
            reply(result) {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { error ->
                        val typed = error as? LocalCutoutException
                        result.error(
                            typed?.code ?: LocalCutoutErrors.INTERNAL,
                            typed?.message ?: "Local background removal failed.",
                            null,
                        )
                    },
                )
            }
        }
    }

    /** Reply on the main thread, and never after detach. */
    private fun reply(@Suppress("UNUSED_PARAMETER") result: MethodChannel.Result, block: () -> Unit) {
        if (detached.get()) return
        mainHandler.post {
            if (detached.get()) return@post
            runCatching(block).onFailure {
                Log.w(TAG, "reply failed: ${it.javaClass.simpleName}")
            }
        }
    }

    private fun capabilityMap(availability: ModuleAvailability): Map<String, Any?> = mapOf(
        "availability" to availability.toWireName(),
        "engine" to GoogleSubjectSegmenterEngine.ENGINE_NAME,
        "engineVersion" to GoogleSubjectSegmenterEngine.DEFAULT_ENGINE_VERSION,
    )

    private fun timeoutOf(call: MethodCall, fallback: Long): Long =
        (call.argument<Number>("timeoutMs")?.toLong() ?: fallback)
            .coerceIn(1L, MAX_TIMEOUT_MS)

    /**
     * Release everything on activity/engine teardown (§8.4). After this the plugin
     * never touches Flutter again, so a late worker callback cannot crash on a
     * disposed engine.
     */
    fun detach() {
        if (!detached.compareAndSet(false, true)) return
        mainHandler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
        worker.execute { runCatching { engine.close() } }
        worker.shutdown()
    }
}
