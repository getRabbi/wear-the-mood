package com.fashionos.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.provider.Settings
import java.util.concurrent.atomic.AtomicBoolean
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import com.android.installreferrer.api.ReferrerDetails
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native bridges for the referral rewards program (§24), exposed to Flutter via
 * two MethodChannels:
 *
 *  - `wtm/install_referrer` — the official Google Play Install Referrer Client
 *    Library for DEFERRED install attribution (a token in the Play `referrer`).
 *    NOT the deprecated INSTALL_REFERRER broadcast. Bounded (5s timeout), always
 *    closes the service connection, never blocks startup, never logs the token.
 *
 *  - `wtm/app_links` — verified HTTPS App Links (https://wearthemood.com/r/<code>)
 *    for links opened when the app is ALREADY installed. Only our referral host +
 *    /r/ path is forwarded; everything else is ignored.
 */
class MainActivity : FlutterActivity() {
    private val installReferrerChannel = "wtm/install_referrer"
    private val appLinksChannel = "wtm/app_links"
    private val notifSettingsChannel = "com.fashionos.app/notif_settings"
    private var appLinks: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannels()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installReferrerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getReferrer" -> fetchInstallReferrer(result)
                    else -> result.notImplemented()
                }
            }

        appLinks = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appLinksChannel)
        appLinks!!.setMethodCallHandler { call, result ->
            when (call.method) {
                // The App Link (if any) the activity was launched with.
                "getInitialLink" -> result.success(referralUriFrom(intent))
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notifSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Open THIS app's OS notification settings so a user who denied
                    // permission can re-enable it (§20). Best-effort — never throws.
                    "open" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Deep-link straight to this app's notification settings, with a safe
     *  fallback to the app details page on older devices. */
    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (_: Exception) {
            // No settings activity to handle it — nothing more we can do.
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = referralUriFrom(intent) ?: return
        appLinks?.invokeMethod("onLink", link)
    }

    /**
     * Stable notification channels (§20), created once (idempotent). FCM
     * notification messages route to these by id; `wtm_updates` is the manifest
     * default. Only needed on Android 8+ (channels didn't exist before).
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        val channels = listOf(
            Triple("wtm_social", "Social activity", NotificationManager.IMPORTANCE_DEFAULT),
            Triple("wtm_account", "Account updates", NotificationManager.IMPORTANCE_HIGH),
            Triple("wtm_style", "Style reminders", NotificationManager.IMPORTANCE_DEFAULT),
            Triple("wtm_community", "Community", NotificationManager.IMPORTANCE_DEFAULT),
            Triple("wtm_updates", "Wear The Mood updates", NotificationManager.IMPORTANCE_LOW),
        )
        for ((id, name, importance) in channels) {
            mgr.createNotificationChannel(NotificationChannel(id, name, importance))
        }
    }

    /** Only our referral App Links (https + wearthemood.com host + /r/ path). */
    private fun referralUriFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data: Uri = intent.data ?: return null
        if (data.scheme != "https") return null
        if (data.host != "wearthemood.com" && data.host != "www.wearthemood.com") return null
        if (!(data.path ?: "").startsWith("/r/")) return null
        return data.toString()
    }

    private fun fetchInstallReferrer(result: MethodChannel.Result) {
        val client = InstallReferrerClient.newBuilder(this).build()
        val replied = AtomicBoolean(false)
        val timeoutHandler = Handler(mainLooper)

        fun reply(payload: Map<String, Any?>) {
            timeoutHandler.removeCallbacksAndMessages(null)
            if (replied.compareAndSet(false, true)) {
                runOnUiThread { result.success(payload) }
            }
            try {
                client.endConnection()
            } catch (_: Exception) {
                // Best-effort close — never surface a teardown error.
            }
        }

        // Never block indefinitely: bail after 5s if the service never responds.
        timeoutHandler.postDelayed({ reply(mapOf("status" to "timeout")) }, 5000)

        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    when (responseCode) {
                        InstallReferrerClient.InstallReferrerResponse.OK -> {
                            try {
                                val details: ReferrerDetails = client.installReferrer
                                val referrer = details.installReferrer
                                reply(
                                    mapOf(
                                        "status" to "ok",
                                        // Raw referrer + parsed token; never logged here.
                                        "referrer" to referrer,
                                        "referralToken" to parseToken(referrer),
                                        "referrerClickTimestampSeconds"
                                            to details.referrerClickTimestampSeconds,
                                        "installBeginTimestampSeconds"
                                            to details.installBeginTimestampSeconds,
                                    ),
                                )
                            } catch (_: Exception) {
                                reply(mapOf("status" to "error"))
                            }
                        }
                        InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED ->
                            reply(mapOf("status" to "notSupported"))
                        InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE ->
                            reply(mapOf("status" to "unavailable"))
                        else -> reply(mapOf("status" to "unavailable"))
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    // Bounded: Dart decides whether to retry; we don't auto-loop.
                }
            })
        } catch (_: Exception) {
            reply(mapOf("status" to "error"))
        }
    }

    /** Extract only `referral_token` from the (decoded) Play referrer string. */
    private fun parseToken(referrer: String?): String? {
        if (referrer.isNullOrEmpty()) return null
        return try {
            Uri.parse("https://x/?$referrer").getQueryParameter("referral_token")
        } catch (_: Exception) {
            null
        }
    }
}
