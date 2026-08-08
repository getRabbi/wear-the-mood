import CoreGraphics
import Flutter
import Foundation
import UIKit
import os

/// `wtm/background_removal` — the Flutter bridge for local cutouts (local BG §4, §8.4).
///
/// Thin by design, and identical in contract to Android's
/// `WtmBackgroundRemovalPlugin`: validate arguments, move work onto a serial
/// background queue, marshal typed errors back.
///
/// Three lifecycle rules that prevent the classic Flutter plugin crashes:
///   * every `FlutterResult` is invoked EXACTLY once, guaranteed by `ResultOnce`;
///   * every reply is delivered on the main thread;
///   * after `detach()`, nothing calls back into Flutter — the engine may already
///     be gone, and replying to a dead channel is undefined.
///
/// The channel is registered unconditionally; the FEATURE is gated in Dart. A build
/// with the gates off simply never calls these methods, and an iOS 16 device gets a
/// typed `unsupported_os` capability rather than an error.
final class WTMBackgroundRemovalPlugin: NSObject {

  static let channelName = "wtm/background_removal"

  private static let defaultRemoveTimeoutMs = 20_000
  private static let maxTimeoutMs = 120_000
  /// The self-test performs one real Vision inference on a small fixture. Generous
  /// enough for a cold first run on an older device, bounded so it can never hang.
  private static let selfTestTimeout: TimeInterval = 25
  private static let defaultSweepMaxAgeMs = Int(
    LocalCutoutOperationCache.defaultMaxAge * 1000)

  private let channel: FlutterMethodChannel
  private let engine: AppleVisionCutoutEngine
  /// Held so `exportDiagnostics` can build an exporter over the SAME root the engine
  /// wrote into. Dart never supplies a directory.
  private let cache: LocalCutoutOperationCache
  /// Serial: Vision is memory-heavy and the engine admits one operation at a time,
  /// so a concurrent queue would only create threads that immediately get refused.
  private let queue = DispatchQueue(
    label: "com.wearthemood.local-cutout", qos: .userInitiated)
  private let detached = LocalCutoutAtomicFlag()

  private init(
    channel: FlutterMethodChannel,
    engine: AppleVisionCutoutEngine,
    cache: LocalCutoutOperationCache
  ) {
    self.channel = channel
    self.engine = engine
    self.cache = cache
    super.init()
  }

  /// Wire the channel. Returns nil only if the cache root cannot be created, in
  /// which case Dart sees a missing channel and falls back to the cloud path — the
  /// app must still launch normally.
  static func register(with messenger: FlutterBinaryMessenger) -> WTMBackgroundRemovalPlugin? {
    let logger = OSLocalCutoutLogger()
    guard let cache = try? LocalCutoutOperationCache.inCachesDirectory() else {
      logger.warn("local cutout unavailable: cache root could not be created")
      return nil
    }
    // The Vision producer only exists on iOS 17+. Below that the engine's
    // availability probe short-circuits before the producer is ever called, so an
    // unavailable producer is a safe placeholder rather than a crash.
    let producer: ForegroundMaskProducing
    if #available(iOS 17.0, *) {
      producer = VisionForegroundMaskProducer()
    } else {
      producer = UnavailableForegroundMaskProducer()
    }
    let engine = AppleVisionCutoutEngine(
      maskProducer: producer, cache: cache, logger: logger)
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: messenger)
    let plugin = WTMBackgroundRemovalPlugin(
      channel: channel, engine: engine, cache: cache)
    channel.setMethodCallHandler { [weak plugin] call, result in
      plugin?.handle(call, result: result)
    }
    return plugin
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Wrapped immediately: from here on it is impossible to reply twice or zero
    // times, whichever path the code takes.
    let once = ResultOnce(result)
    if detached.value {
      once.fail(LocalCutoutError.disposed)
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "capability":
      onQueue(once) { [engine] in engine.capability().channelMap }

    case "prepare":
      onQueue(once) { [engine] in engine.prepare().channelMap }

    // The native half of the contract, proven against the real encoders and cache
    // rather than a fake (§4). Dart runs it at most once per app version — never on
    // launch — so the one Vision inference it performs costs nothing in practice.
    case "selfTest":
      onQueue(once, timeout: Self.selfTestTimeout) { [engine] in engine.selfTest() }

    case "removeBackground":
      guard let data = (arguments["imageBytes"] as? FlutterStandardTypedData)?.data,
        !data.isEmpty
      else {
        once.fail(LocalCutoutError.sourceMissing)
        return
      }
      let timeout = timeoutSeconds(arguments, fallback: Self.defaultRemoveTimeoutMs)
      // Dart decides per call, and only an internal build ever asks. Native still
      // refuses to EXPORT unless compiled with diagnostics, so a rogue `true` here
      // buys nothing but a slightly larger cache directory.
      let capture = (arguments["captureDiagnostics"] as? Bool) ?? false
      // Captured so the deadline below cancels THIS operation and no other.
      let inFlight = LocalCutoutInFlightId()
      onQueue(
        once, timeout: timeout, cancelling: inFlight,
        reportingOperationId: capture
      ) { [engine] in
        try engine
          .removeBackground(
            jpegData: data,
            captureDiagnostics: capture,
            onOperationStarted: inFlight.set
          )
          .channelMap
      }

    case "exportDiagnostics":
      // INTERNAL BUILDS ONLY. Compiled out entirely unless the
      // ios-internal-diagnostic workflow defines WTM_LOCAL_BG_DIAGNOSTICS, so an
      // App Store binary cannot be talked into exporting anything.
      #if WTM_LOCAL_BG_DIAGNOSTICS
        let operationId = arguments["operationId"] as? String ?? ""
        guard LocalCutoutOperationCache.isValidOperationId(operationId) else {
          once.fail(LocalCutoutError.malformedOperationId)
          return
        }
        exportDiagnostics(operationId: operationId, once: once)
      #else
        once.fail(LocalCutoutError.diagnosticsDisabled)
      #endif

    case "cancel":
      engine.cancel(arguments["operationId"] as? String)
      once.succeed(nil)

    case "cleanup":
      // Operation ID, never a path — see LocalCutoutOperationCache (R10b).
      let operationId = arguments["operationId"] as? String ?? ""
      onQueue(once) { [engine] in engine.cleanup(operationId) }

    case "sweepCache":
      let maxAgeMs = (arguments["maxAgeMs"] as? NSNumber)?.intValue
        ?? Self.defaultSweepMaxAgeMs
      onQueue(once) { [engine] in
        engine.sweepCache(maxAge: TimeInterval(max(0, maxAgeMs)) / 1000)
      }

    default:
      once.notImplemented()
    }
  }

  /// Run `work` off the main thread and marshal its outcome back, typed.
  ///
  /// `timeout` bounds the WAIT, not the work. That distinction matters on iOS:
  /// `VNImageRequestHandler.perform` is synchronous and cannot be interrupted, so a
  /// pathologically slow inference keeps running — and keeps the single-operation
  /// slot — until it returns. The deadline's job is therefore to (a) reply so Dart
  /// is never left hanging, and (b) flag THIS operation cancelled so it aborts at
  /// its next checkpoint. A subsequent add during that window is refused with
  /// `busy`, which Dart treats as temporarily unavailable and routes to the cloud.
  /// Android differs: `Tasks.await(task, timeout, unit)` genuinely bounds inference.
  private func onQueue(
    _ once: ResultOnce,
    timeout: TimeInterval? = nil,
    cancelling inFlight: LocalCutoutInFlightId? = nil,
    reportingOperationId reportId: Bool = false,
    _ work: @escaping () throws -> Any?
  ) {
    if let timeout {
      let deadline = DispatchWorkItem { [weak self] in
        guard let self, !self.detached.value else { return }
        // Cancel ONLY the operation this deadline belongs to. Passing nil would
        // cancel whatever happens to be active, which after a late-firing deadline
        // can be an unrelated newer run.
        if let operationId = inFlight?.value {
          self.engine.cancel(operationId)
        }
        once.fail(
          LocalCutoutError.timedOut,
          details: reportId ? inFlight?.value : nil)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: deadline)
      queue.async { [weak self] in
        let outcome = Self.evaluate(work)
        deadline.cancel()
        self?.reply(once, outcome, details: reportId ? inFlight?.value : nil)
      }
      return
    }
    queue.async { [weak self] in
      let outcome = Self.evaluate(work)
      self?.reply(once, outcome)
    }
  }

  private static func evaluate(_ work: () throws -> Any?) -> Result<Any?, LocalCutoutError> {
    do {
      return .success(try work())
    } catch let error as LocalCutoutError {
      return .failure(error)
    } catch {
      // Nothing escapes untyped: an uncaught error here would surface to the user
      // as a broken Add Garment instead of a quiet cloud fallback.
      return .failure(LocalCutoutError.unexpected(error))
    }
  }

  private func reply(
    _ once: ResultOnce,
    _ outcome: Result<Any?, LocalCutoutError>,
    details: String? = nil
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.detached.value else { return }
      switch outcome {
      case .success(let value): once.succeed(value)
      case .failure(let error): once.fail(error, details: details)
      }
    }
  }

  private func timeoutSeconds(_ arguments: [String: Any], fallback: Int) -> TimeInterval {
    let raw = (arguments["timeoutMs"] as? NSNumber)?.intValue ?? fallback
    return TimeInterval(min(max(raw, 1), Self.maxTimeoutMs)) / 1000
  }

  #if WTM_LOCAL_BG_DIAGNOSTICS

    /// Zip one operation's evidence off the main thread, then offer it to the share
    /// sheet (iOS Phase 3, internal builds only).
    ///
    /// The archive path never crosses the channel. Dart learns only whether the
    /// bundle was shared or cancelled — it has no reason to know where the file
    /// lived, and handing out a path would undo the operation-id discipline the rest
    /// of this feature is built on.
    private func exportDiagnostics(operationId: String, once: ResultOnce) {
      queue.async { [weak self] in
        guard let self, !self.detached.value else { return }
        let archive: URL
        do {
          archive = try LocalCutoutDiagnosticExporter(cache: self.cache)
            .makeArchive(operationId: operationId)
        } catch let error as LocalCutoutError {
          self.reply(once, .failure(error))
          return
        } catch {
          self.reply(once, .failure(LocalCutoutError.diagnosticsUnavailable))
          return
        }
        DispatchQueue.main.async { [weak self] in
          guard let self, !self.detached.value else { return }
          self.present(archive: archive, once: once)
        }
      }
    }

    /// Present `UIActivityViewController`. Main thread only.
    private func present(archive: URL, once: ResultOnce) {
      guard let host = Self.topmostViewController() else {
        try? FileManager.default.removeItem(at: archive)
        once.fail(LocalCutoutError.diagnosticsPresentationFailed)
        return
      }
      // Presenting over an existing modal is the classic UIKit fatal. Refuse rather
      // than crash a build whose entire purpose is to survive long enough to report.
      guard host.presentedViewController == nil else {
        try? FileManager.default.removeItem(at: archive)
        once.fail(LocalCutoutError.diagnosticsPresentationFailed)
        return
      }
      let sheet = UIActivityViewController(
        activityItems: [archive], applicationActivities: nil)
      // On iPad an action sheet without an anchor terminates the app. The founder
      // tests on iPhone, but a crash here would be indistinguishable from a Vision
      // crash and would waste a device session.
      if let popover = sheet.popoverPresentationController {
        popover.sourceView = host.view
        popover.sourceRect = CGRect(
          x: host.view.bounds.midX, y: host.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      sheet.completionWithItemsHandler = { _, completed, _, _ in
        // The ZIP is a derived artifact; the operation directory it was built from
        // stays put, so the tester can export again or inspect on the next run.
        try? FileManager.default.removeItem(at: archive)
        once.succeed(["status": completed ? "shared" : "cancelled"])
      }
      host.present(sheet, animated: true)
    }

    /// The view controller actually on screen, walking past any Flutter-presented
    /// modal. `keyWindow` is deprecated per-application, so this goes through the
    /// connected window scenes.
    private static func topmostViewController() -> UIViewController? {
      let windows =
        UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
      let window = windows.first { $0.isKeyWindow } ?? windows.first
      var top = window?.rootViewController
      while let presented = top?.presentedViewController { top = presented }
      return top
    }

  #endif

  /// Release everything on engine teardown (§8.4). After this the plugin never
  /// touches Flutter again, so a late queue callback cannot reply on a disposed
  /// engine.
  func detach() {
    guard detached.trySet() else { return }
    channel.setMethodCallHandler(nil)
    engine.cancel(nil)
    queue.async { [engine] in engine.dispose() }
  }
}

/// Guarantees a `FlutterResult` is invoked exactly once.
///
/// Without this, the timeout path and the completion path can both fire — which
/// Flutter treats as a fatal reply-after-reply on some engine versions.
final class ResultOnce {
  private let lock = NSLock()
  private var result: FlutterResult?

  init(_ result: @escaping FlutterResult) {
    self.result = result
  }

  private func take() -> FlutterResult? {
    lock.lock()
    defer { lock.unlock() }
    let pending = result
    result = nil
    return pending
  }

  func succeed(_ value: Any?) { take()?(value) }

  func notImplemented() { take()?(FlutterMethodNotImplemented) }

  /// `details` carries the operation id ONLY on a diagnostic build, so a tester can
  /// export the evidence of a run that failed. It is nil on every production build:
  /// nothing outside a diagnostic session has any use for it, and an id in an error
  /// payload is one more thing that could end up in a log.
  func fail(_ error: LocalCutoutError, details: String? = nil) {
    take()?(
      FlutterError(
        code: error.code.rawValue,
        message: error.diagnostic,
        details: details
      ))
  }
}

/// Thread-safe holder for the id of the operation a timeout may cancel.
///
/// Written on the worker queue the instant the engine claims its slot, read on the
/// main queue when the deadline fires.
final class LocalCutoutInFlightId {
  private let lock = NSLock()
  private var operationId: String?

  var value: String? {
    lock.lock()
    defer { lock.unlock() }
    return operationId
  }

  func set(_ id: String) {
    lock.lock()
    operationId = id
    lock.unlock()
  }
}

/// Minimal atomic one-way flag for the detached state.
final class LocalCutoutAtomicFlag {
  private let lock = NSLock()
  private var flag = false

  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return flag
  }

  /// Sets the flag; returns true only for the caller that flipped it.
  func trySet() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if flag { return false }
    flag = true
    return true
  }
}

/// `os.Logger`-backed logger. Only safe categories are ever passed in (§10).
struct OSLocalCutoutLogger: LocalCutoutLogging {
  private let log = OSLog(subsystem: "com.wearthemood.app", category: "local-cutout")

  func warn(_ message: String) {
    os_log("%{public}@", log: log, type: .info, message)
  }
}

/// Stands in for the Vision producer below iOS 17. It is never reached: the
/// engine's availability probe fails first. If it somehow is, it fails typed.
struct UnavailableForegroundMaskProducer: ForegroundMaskProducing {
  func produceForegroundMask(for image: CGImage) throws -> ProducedForegroundMask {
    throw LocalCutoutError.unsupportedOsVersion
  }
}

extension LocalCutoutAvailability {
  /// The exact shape `LocalCutoutCapability.fromMap` decodes in Dart.
  var channelMap: [String: Any?] {
    [
      "availability": rawValue,
      "engine": AppleVisionCutoutEngine.engineName,
      "engineVersion": AppleVisionCutoutEngine.engineVersion,
    ]
  }
}
