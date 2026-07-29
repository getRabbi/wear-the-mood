import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Local-first background removal (local BG §8.4). Registration only — the
  /// engine, Vision contact and cache all live in `Runner/BackgroundRemoval/`.
  /// Nil if the cache root cannot be created; either way the app launches
  /// normally and Dart falls back to the cloud cutout path.
  private var backgroundRemoval: WTMBackgroundRemovalPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The messenger comes from a registrar rather than the bridge directly: the
    // `registrar(forPlugin:)` -> `messenger()` pair is the long-stable API, and
    // the plugin name is namespaced so it cannot collide with a pub plugin.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "com.wearthemood.WTMBackgroundRemovalPlugin")
    {
      backgroundRemoval = WTMBackgroundRemovalPlugin.register(
        with: registrar.messenger()
      )
    }
  }

  /// Release the Vision engine and scratch files (§8.4).
  ///
  /// iOS can terminate without calling this, which is why the engine also sweeps
  /// stale operation directories on the next launch — teardown is a courtesy, not
  /// the only cleanup path.
  override func applicationWillTerminate(_ application: UIApplication) {
    backgroundRemoval?.detach()
    backgroundRemoval = nil
    super.applicationWillTerminate(application)
  }
}
