import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// The iOS local-cutout engine (local BG §2.1, §8.3).
///
/// Orchestration mirrors Android's `GoogleSubjectSegmenterEngine` step for step, so
/// the two platforms behave identically from Dart's point of view:
///   1. availability, so an iOS 16 device costs nothing;
///   2. decode the EXACT bytes Flutter will upload as the original (§8.1);
///   3. Vision foreground-instance mask;
///   4. convert the scaled mask to soft alpha, measure, composite;
///   5. write both PNGs into the operation directory and return paths.
///
/// A cancellation checkpoint sits between each expensive stage.
///
/// Vision contact is behind `ForegroundMaskProducing` and the OS check is behind
/// `LocalCutoutAvailabilityProbing`, so the whole class is exercised by XCTest with
/// fakes — including the iOS-16 path, which a 17+ simulator could not otherwise
/// reach.
final class AppleVisionCutoutEngine {

  /// Bounded, stable engine version. Deliberately the Vision REQUEST REVISION and
  /// nothing else — no device model, no OS build, no raw metadata (§10).
  static let engineVersion = "vision-foreground-instance-mask-r1"
  static let engineName = "apple_vision"

  /// Server-side sanity bounds are the authority; these only catch a mask that is
  /// structurally useless, matching the Dart policy's hard bounds.
  private static let minForegroundAreaRatio = 0.0
  private static let maxForegroundAreaRatio = 1.0

  private let maskProducer: ForegroundMaskProducing
  private let cache: LocalCutoutOperationCache
  private let availability: LocalCutoutAvailabilityProbing
  private let guardrail: LocalCutoutOperationGuard
  private let clock: () -> Date
  private let logger: LocalCutoutLogging

  init(
    maskProducer: ForegroundMaskProducing,
    cache: LocalCutoutOperationCache,
    availability: LocalCutoutAvailabilityProbing = SystemAvailabilityProbe(),
    guardrail: LocalCutoutOperationGuard = LocalCutoutOperationGuard(),
    clock: @escaping () -> Date = Date.init,
    logger: LocalCutoutLogging = SilentLocalCutoutLogger()
  ) {
    self.maskProducer = maskProducer
    self.cache = cache
    self.availability = availability
    self.guardrail = guardrail
    self.clock = clock
    self.logger = logger
  }

  /// What this device can do right now. Never throws.
  func capability() -> LocalCutoutAvailability {
    availability.isForegroundMaskingAvailable ? .available : .unsupportedOsVersion
  }

  /// iOS has nothing to download — Vision ships with the OS. Kept so the channel
  /// contract is identical on both platforms.
  func prepare() -> LocalCutoutAvailability { capability() }

  /// Segment `jpegData` and write the results into a fresh operation directory.
  ///
  /// `onOperationStarted` fires exactly once, as soon as the single-operation slot
  /// is claimed, carrying this run's id. The plugin uses it so a timeout can cancel
  /// THIS operation specifically — cancelling "whatever is active" could kill an
  /// unrelated later run whose predecessor's deadline fired late.
  func removeBackground(
    jpegData: Data,
    captureDiagnostics: Bool = false,
    onOperationStarted: ((String) -> Void)? = nil
  ) throws -> LocalCutoutOperationResult {
    guard availability.isForegroundMaskingAvailable else {
      throw LocalCutoutError.unsupportedOsVersion
    }
    let operationId = LocalCutoutOperationCache.newOperationId()
    guard guardrail.begin(operationId) else { throw LocalCutoutError.busy }
    onOperationStarted?(operationId)
    let startedAt = clock()
    // A reference type so the stages recorded before a throw survive it — the
    // failure bundle is the whole point of the diagnostic build (§3).
    let recorder = captureDiagnostics ? DiagnosticsRecorder() : nil
    do {
      let result = try run(
        operationId: operationId, jpegData: jpegData, startedAt: startedAt,
        recorder: recorder)
      if let recorder {
        recorder.value.stage = .completed
        try? persistDiagnostics(recorder, operationId: operationId, source: jpegData)
      }
      return result
    } catch {
      let typed = (error as? LocalCutoutError) ?? LocalCutoutError.unexpected(error)
      if let recorder {
        // PRESERVE the evidence. Normally a failed operation's directory is swept
        // immediately; in a diagnostic build that would delete the only record of
        // what went wrong, which is precisely what Android's first device run
        // needed and did not have.
        recorder.value.failureCode = typed.code.rawValue
        recorder.value.failureDetail = typed.diagnostic
        recorder.value.totalMs = ms(from: startedAt)
        try? persistDiagnostics(recorder, operationId: operationId, source: jpegData)
      } else {
        // Never leave a half-written directory behind. The slot itself is released
        // by `run`'s defer, which has already fired by the time we get here.
        cache.delete(operationId)
      }
      logger.warn("local cutout failed: \(typed.code.rawValue)")
      throw typed
    }
  }

  /// Write `source.bin` + `result.json` beside the operation's other artifacts.
  ///
  /// Best-effort by construction: a diagnostic that fails must never change the
  /// outcome of the operation it is describing, so every caller ignores the throw.
  private func persistDiagnostics(
    _ recorder: DiagnosticsRecorder, operationId: String, source: Data
  ) throws {
    let exporter = LocalCutoutDiagnosticExporter(cache: cache)
    try exporter.writeSource(source, operationId: operationId)
    try exporter.writeResult(recorder.value, operationId: operationId)
  }

  private func run(
    operationId: String, jpegData: Data, startedAt: Date,
    recorder: DiagnosticsRecorder? = nil
  ) throws -> LocalCutoutOperationResult {
    defer { guardrail.end(operationId) }

    guard !jpegData.isEmpty else { throw LocalCutoutError.sourceMissing }
    recorder?.value.sourceByteCount = jpegData.count

    let decodeStart = clock()
    let image = try PixelBufferMaskCompositor.decodeSource(jpegData)
    let width = image.width
    let height = image.height
    let decodeMs = ms(from: decodeStart)
    recorder?.record {
      $0.stage = .sourceDecoded
      $0.sourceWidth = width
      $0.sourceHeight = height
      $0.decodeMs = decodeMs
    }
    try guardrail.throwIfCancelled(operationId)

    // ONE request handler for both the request and the scaled-mask generation, as
    // the Vision API requires — the observation resolves its scaled mask against
    // the handler it came from.
    let inferenceStart = clock()
    let produced = try maskProducer.produceForegroundMask(for: image)
    let inferenceMs = ms(from: inferenceStart)
    recorder?.record {
      $0.stage = .visionCompleted
      $0.inferenceMs = inferenceMs
      $0.observationCount = produced.observationCount
      $0.instanceCount = produced.instanceCount
      // Read from the buffer Vision actually returned, not from an assumption.
      // Which format arrives on a real device is one of the open questions Phase 3
      // exists to answer.
      $0.maskPixelFormat = LocalCutoutDiagnostics.formatCode(
        CVPixelBufferGetPixelFormatType(produced.mask))
      $0.maskPlaneCount = CVPixelBufferGetPlaneCount(produced.mask)
      $0.maskBytesPerRow = CVPixelBufferGetBytesPerRow(produced.mask)
      $0.maskWidth = CVPixelBufferGetWidth(produced.mask)
      $0.maskHeight = CVPixelBufferGetHeight(produced.mask)
    }
    try guardrail.throwIfCancelled(operationId)

    guard produced.instanceCount > 0 else {
      throw LocalCutoutError.noForegroundInstances
    }
    recorder?.value.stage = .maskScaled

    let maskStart = clock()
    let extracted = try PixelBufferMaskCompositor.alphaBytes(from: produced.mask)
    recorder?.record {
      $0.stage = .maskExtracted
      $0.maskStatistics = extracted.statistics
    }
    // The scaled mask is generated for the source image, so a mismatch means
    // something upstream changed the geometry. Refuse rather than resample: the
    // backend requires exact dimensions and would reject it anyway (§8.1).
    guard extracted.width == width, extracted.height == height else {
      throw LocalCutoutError.maskDimensionMismatch
    }
    let maskMs = ms(from: maskStart)
    recorder?.value.maskMs = maskMs
    try guardrail.throwIfCancelled(operationId)

    let metrics = try LocalCutoutMaskMath.measure(
      alpha: extracted.alpha,
      width: width,
      height: height,
      subjectCount: produced.instanceCount
    )
    recorder?.value.meanAlphaCoverage = metrics.foregroundAreaRatio
    if metrics.foregroundAreaRatio <= Self.minForegroundAreaRatio {
      throw LocalCutoutError.maskEffectivelyEmpty
    }
    if metrics.foregroundAreaRatio >= Self.maxForegroundAreaRatio {
      throw LocalCutoutError.maskEffectivelyFull
    }
    try guardrail.throwIfCancelled(operationId)

    let compositeStart = clock()
    let sourcePixels = try PixelBufferMaskCompositor.bgraBytes(from: image)
    // BGRA in little-endian memory puts alpha at byte 3 of each pixel.
    let composited = try LocalCutoutMaskMath.composite(
      source: sourcePixels, alpha: extracted.alpha, alphaOffset: 3
    )
    let maskPNG = try PixelBufferMaskCompositor.encodeMaskPNG(
      alpha: extracted.alpha, width: width, height: height
    )
    let cutoutPNG = try PixelBufferMaskCompositor.encodeCutoutPNG(
      bgra: composited, width: width, height: height
    )
    guard !maskPNG.isEmpty, !cutoutPNG.isEmpty else {
      throw LocalCutoutError.emptyOutput
    }
    // Non-empty bytes are not evidence of a usable image. Decode both back and prove
    // the geometry, because everything downstream — the Flutter preview, the
    // local-cutout upload, the closet grid — decodes them for real. A
    // well-formed-but-wrong or truncated PNG must become a typed fallback here, not
    // a saved item that renders broken (§4).
    let decodedMask = try PixelBufferMaskCompositor.decodedDimensions(of: maskPNG)
    let decodedCutout = try PixelBufferMaskCompositor.decodedDimensions(of: cutoutPNG)
    guard
      decodedMask.width == width, decodedMask.height == height,
      decodedCutout.width == width, decodedCutout.height == height
    else {
      throw LocalCutoutError.maskDimensionMismatch
    }
    let compositeMs = ms(from: compositeStart)
    recorder?.record {
      $0.stage = .encoded
      $0.compositeMs = compositeMs
      $0.encodeMs = compositeMs
      $0.cutoutWidth = decodedCutout.width
      $0.cutoutHeight = decodedCutout.height
    }
    try guardrail.throwIfCancelled(operationId)

    let writeStart = clock()
    try cache.createOperationDirectory(operationId)
    let maskURL = try cache.maskFile(operationId)
    let cutoutURL = try cache.cutoutFile(operationId)
    do {
      try maskPNG.write(to: maskURL, options: .atomic)
      try cutoutPNG.write(to: cutoutURL, options: .atomic)
    } catch {
      throw LocalCutoutError.cacheWriteFailed
    }
    // A result must never point at a missing or empty file (§4).
    guard
      let maskSize = fileSize(maskURL), maskSize > 0,
      let cutoutSize = fileSize(cutoutURL), cutoutSize > 0
    else {
      throw LocalCutoutError.cacheWriteFailed
    }
    // Re-prove containment on the paths actually being returned. `maskFile`/
    // `cutoutFile` already resolve inside the root, but these two strings are what
    // crosses the channel and what `cleanup` will later be asked to remove, so the
    // invariant is asserted on the values that escape rather than on the values used
    // to derive them (R10b).
    guard cache.isContained(maskURL), cache.isContained(cutoutURL) else {
      throw LocalCutoutError.cacheNotContained
    }
    recorder?.record {
      $0.stage = .written
      $0.writeMs = ms(from: writeStart)
      $0.totalMs = ms(from: startedAt)
    }

    // Structured stage timings (§10): durations and bucketed counts only — no
    // paths, no filenames, no operation id, no bytes, no exact ratios beyond the
    // coarse coverage figure the quality policy already reasons about.
    logger.warn(
      "local cutout stages"
        + " decode_ms=\(decodeMs)"
        + " inference_ms=\(inferenceMs)"
        + " mask_ms=\(maskMs)"
        + " composite_ms=\(compositeMs)"
        + " write_ms=\(ms(from: writeStart))"
        + " total_ms=\(ms(from: startedAt))"
        + " subjects=\(produced.instanceCount)"
        + " coverage=\(String(format: "%.2f", metrics.foregroundAreaRatio))"
    )
    return LocalCutoutOperationResult(
      operationId: operationId,
      engineVersion: Self.engineVersion,
      maskFilePath: maskURL.path,
      cutoutFilePath: cutoutURL.path,
      metrics: metrics,
      latencyMs: Int(max(0, clock().timeIntervalSince(startedAt) * 1000).rounded())
    )
  }

  func cancel(_ operationId: String?) { guardrail.cancel(operationId) }

  /// Delete one operation's files. Idempotent; id-based, never path-based.
  @discardableResult
  func cleanup(_ operationId: String) -> Bool { cache.delete(operationId) }

  @discardableResult
  func sweepCache(maxAge: TimeInterval) -> Int {
    cache.sweepStale(maxAge: maxAge, now: clock())
  }

  /// Release scratch files on disposal. Safe to call twice.
  func dispose() {
    guardrail.cancel(nil)
    cache.clear()
  }

  /// Whole milliseconds since `start`, per the injected clock.
  private func ms(from start: Date) -> Int {
    Int(max(0, clock().timeIntervalSince(start) * 1000).rounded())
  }

  private func fileSize(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
  }
}

/// A successful local removal, ready to serialise onto the method channel.
struct LocalCutoutOperationResult {
  let operationId: String
  let engineVersion: String
  let maskFilePath: String
  let cutoutFilePath: String
  let metrics: LocalCutoutMaskMetrics
  let latencyMs: Int

  /// The exact shape `LocalCutoutResult.fromMap` decodes in Dart (§4).
  ///
  /// Note what is NOT here: the operation DIRECTORY. Dart reads the two files but
  /// never receives a path it is expected to delete — cleanup goes back over the
  /// channel as an operation id (blocker R10b). Identical to Android.
  var channelMap: [String: Any?] {
    [
      "engine": AppleVisionCutoutEngine.engineName,
      "engineVersion": engineVersion,
      "operationId": operationId,
      "maskFilePath": maskFilePath,
      "cutoutFilePath": cutoutFilePath,
      "latencyMs": latencyMs,
      "metrics": metrics.channelMap,
    ]
  }
}

/// Mutable diagnostics carrier for one operation (iOS Phase 3, internal builds).
///
/// A class rather than a struct on purpose: the stages recorded before a failure
/// must survive the `throw` that unwinds `run`, because the failure bundle is the
/// entire reason the diagnostic build exists. A value type would be discarded with
/// the frame, leaving exactly the blind spot Android had on its first device run.
///
/// Never allocated unless diagnostics are explicitly requested, so a production
/// build carries no per-operation cost.
final class DiagnosticsRecorder {
  var value: LocalCutoutDiagnostics

  init(_ value: LocalCutoutDiagnostics = .current()) {
    self.value = value
  }

  /// Apply several fields at once, keeping call sites in `run` compact.
  func record(_ mutate: (inout LocalCutoutDiagnostics) -> Void) {
    mutate(&value)
  }
}

/// Availability, mirroring Dart's `LocalCutoutAvailability` wire values.
enum LocalCutoutAvailability: String {
  case available = "available"
  /// iOS 15.5–16.x: the deployment floor stays 15.5, the feature needs 17.
  case unsupportedOsVersion = "unsupported_os"
  case temporarilyUnavailable = "temporarily_unavailable"
}

// MARK: - Seams

/// Whether the Vision foreground-instance API can run. Injected so the iOS 16
/// branch is testable on a 17+ simulator.
protocol LocalCutoutAvailabilityProbing {
  var isForegroundMaskingAvailable: Bool { get }
}

struct SystemAvailabilityProbe: LocalCutoutAvailabilityProbing {
  var isForegroundMaskingAvailable: Bool {
    if #available(iOS 17.0, *) { return true }
    return false
  }
}

/// One foreground mask for one image.
struct ProducedForegroundMask {
  /// Single-component mask at the SOURCE dimensions, from
  /// `generateScaledMaskForImage(forInstances:from:)`.
  let mask: CVPixelBuffer
  /// `allInstances.count` — the number of foreground instances Vision found.
  let instanceCount: Int
  /// `request.results?.count`. Diagnostic only: it distinguishes "Vision returned
  /// nothing" from "Vision returned an observation with no instances", which look
  /// identical from the outside but mean different things on a device.
  var observationCount: Int = 1
}

/// The Vision surface the engine uses. Blocking; the caller is already off the
/// main thread.
protocol ForegroundMaskProducing {
  func produceForegroundMask(for image: CGImage) throws -> ProducedForegroundMask
}

/// Minimal logging seam. Messages are safe categories only — never bytes, paths,
/// filenames or raw Apple error text (§10).
protocol LocalCutoutLogging {
  func warn(_ message: String)
}

struct SilentLocalCutoutLogger: LocalCutoutLogging {
  func warn(_ message: String) {}
}

/// Admits one removal at a time.
///
/// Vision holds the source CGImage, a full-resolution mask buffer and two pixel
/// arrays at once — tens of MB for a 1600px photo. Two concurrent runs is the
/// shape of a memory termination, so the second caller is REFUSED with `busy`
/// (Dart treats that as temporarily unavailable and uses the cloud path), exactly
/// as on Android.
final class LocalCutoutOperationGuard {
  private let lock = NSLock()
  private var active: String?
  private var cancelledId: String?

  var isBusy: Bool {
    lock.lock()
    defer { lock.unlock() }
    return active != nil
  }

  var activeOperationId: String? {
    lock.lock()
    defer { lock.unlock() }
    return active
  }

  func begin(_ operationId: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if active != nil { return false }
    active = operationId
    cancelledId = nil
    return true
  }

  func end(_ operationId: String) {
    lock.lock()
    defer { lock.unlock() }
    if active == operationId { active = nil }
  }

  /// Flag the in-flight run so it aborts at its next checkpoint. `nil` cancels
  /// whatever is active.
  func cancel(_ operationId: String?) {
    lock.lock()
    defer { lock.unlock() }
    guard let current = active else { return }
    if operationId == nil || operationId == current { cancelledId = current }
  }

  func isCancelled(_ operationId: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelledId == operationId
  }

  /// Abort at a checkpoint, so teardown never has to interrupt a thread mid-Vision.
  func throwIfCancelled(_ operationId: String) throws {
    if isCancelled(operationId) { throw LocalCutoutError.cancelled }
  }
}

// MARK: - The real Vision implementation

/// The ONLY type that touches Vision (local BG §2.1).
///
/// Uses the STABLE `VN*` API surface, not the newer beta Swift
/// `GenerateForegroundInstanceMaskRequest` / `InstanceMaskObservation`, because the
/// app's deployment floor is 15.5 and the stable API covers iOS 17 fine.
///
/// The important distinction: `observation.instanceMask` is an instance-LABEL map
/// (0 = background, other values = instance identifiers). Those values are ids,
/// not alpha or confidence, and using them as alpha would produce a hard stencil
/// with arbitrary brightness. The authoritative full-image mask is
/// `generateScaledMaskForImage(forInstances: allInstances, from: handler)`, whose
/// intermediate edge values are preserved verbatim.
@available(iOS 17.0, *)
struct VisionForegroundMaskProducer: ForegroundMaskProducing {

  func produceForegroundMask(for image: CGImage) throws -> ProducedForegroundMask {
    let request = VNGenerateForegroundInstanceMaskRequest()
    // ONE handler, used for both `perform` and the scaled-mask generation.
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw LocalCutoutError.visionRequestFailed
    }
    guard let observation = request.results?.first else {
      throw LocalCutoutError.noObservation
    }
    let instances = observation.allInstances
    guard !instances.isEmpty else {
      throw LocalCutoutError.noForegroundInstances
    }
    do {
      let mask = try observation.generateScaledMaskForImage(
        forInstances: instances, from: handler
      )
      return ProducedForegroundMask(
        mask: mask,
        instanceCount: instances.count,
        observationCount: request.results?.count ?? 0
      )
    } catch {
      throw LocalCutoutError.visionRequestFailed
    }
  }
}
