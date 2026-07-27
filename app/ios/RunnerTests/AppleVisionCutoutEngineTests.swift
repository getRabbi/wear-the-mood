import CoreGraphics
import CoreVideo
import XCTest

/// Engine orchestration against deterministic fakes (local BG §11.4).
///
/// Vision needs iOS 17 and a real photo; both are behind seams, so the parts that
/// decide BEHAVIOUR — availability mapping, error typing, cancellation, cleanup,
/// the single-operation guard — are provable on any simulator, including the iOS-16
/// branch a 17+ simulator could not otherwise reach.
final class AppleVisionCutoutEngineTests: XCTestCase {

  private var tempRoot: URL!
  private var cache: LocalCutoutOperationCache!

  private let width = 6
  private let height = 4

  override func setUpWithError() throws {
    tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("wtm-engine-tests-\(UUID().uuidString)", isDirectory: true)
    let root = tempRoot.appendingPathComponent(
      LocalCutoutOperationCache.rootDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    cache = LocalCutoutOperationCache(root: root)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempRoot)
  }

  // MARK: - Fakes

  private struct FakeProbe: LocalCutoutAvailabilityProbing {
    let isForegroundMaskingAvailable: Bool
  }

  private final class FakeMaskProducer: ForegroundMaskProducing {
    var instanceCount = 1
    var error: Error?
    var maskFill: (Int, Int) -> Double = { _, _ in 1.0 }
    var maskWidth: Int?
    var maskHeight: Int?
    var onProduce: (() -> Void)?
    private(set) var callCount = 0

    func produceForegroundMask(for image: CGImage) throws -> ProducedForegroundMask {
      callCount += 1
      onProduce?()
      if let error { throw error }
      let w = maskWidth ?? image.width
      let h = maskHeight ?? image.height
      var buffer: CVPixelBuffer?
      let status = CVPixelBufferCreate(
        kCFAllocatorDefault, w, h, kCVPixelFormatType_OneComponent8, nil, &buffer)
      guard status == kCVReturnSuccess, let buffer else {
        throw LocalCutoutError.invalidOutput
      }
      CVPixelBufferLockBaseAddress(buffer, [])
      let stride = CVPixelBufferGetBytesPerRow(buffer)
      if let base = CVPixelBufferGetBaseAddress(buffer) {
        for y in 0..<h {
          for x in 0..<w {
            base.advanced(by: y * stride + x)
              .assumingMemoryBound(to: UInt8.self)
              .pointee = UInt8((min(max(maskFill(x, y), 0), 1) * 255).rounded())
          }
        }
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      return ProducedForegroundMask(mask: buffer, instanceCount: instanceCount)
    }
  }

  /// A real PNG the decoder will accept, at the test dimensions.
  private func sourceData() throws -> Data {
    try PixelBufferMaskCompositor.encodeCutoutPNG(
      bgra: [UInt8](repeating: 180, count: width * height * 4),
      width: width, height: height)
  }

  private func makeEngine(
    producer: ForegroundMaskProducing,
    available: Bool = true,
    guardrail: LocalCutoutOperationGuard = LocalCutoutOperationGuard(),
    clock: @escaping () -> Date = Date.init
  ) -> AppleVisionCutoutEngine {
    AppleVisionCutoutEngine(
      maskProducer: producer,
      cache: cache,
      availability: FakeProbe(isForegroundMaskingAvailable: available),
      guardrail: guardrail,
      clock: clock
    )
  }

  private func rootEntryCount() -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: cache.rootPath))?.count ?? -1
  }

  private func code(_ block: () throws -> Void) -> LocalCutoutErrorCode? {
    do {
      try block()
      return nil
    } catch let error as LocalCutoutError {
      return error.code
    } catch {
      return nil
    }
  }

  // MARK: - Availability

  func testAvailabilityMapsToTheDartWireValues() {
    XCTAssertEqual(
      makeEngine(producer: FakeMaskProducer(), available: true).capability(), .available)
    XCTAssertEqual(
      makeEngine(producer: FakeMaskProducer(), available: false).capability(),
      .unsupportedOsVersion)
    // These strings are the shipped contract Dart decodes.
    XCTAssertEqual(LocalCutoutAvailability.available.rawValue, "available")
    XCTAssertEqual(LocalCutoutAvailability.unsupportedOsVersion.rawValue, "unsupported_os")
  }

  func testIosSixteenRefusesBeforeDoingAnyWork() throws {
    // The deployment floor stays 15.5, so this is the live path on a real iOS 16
    // device: refuse immediately, never touch Vision, never create a directory.
    let producer = FakeMaskProducer()
    let engine = makeEngine(producer: producer, available: false)
    let data = try sourceData()

    XCTAssertEqual(
      code { _ = try engine.removeBackground(jpegData: data) }, .unsupported)
    XCTAssertEqual(producer.callCount, 0)
    XCTAssertEqual(rootEntryCount(), 0)
  }

  func testPrepareIsAnAvailabilityCheckOnIos() {
    // Nothing to download: Vision ships with the OS.
    XCTAssertEqual(makeEngine(producer: FakeMaskProducer()).prepare(), .available)
  }

  // MARK: - Happy path

  func testSuccessWritesBothFilesAndReportsMetrics() throws {
    let producer = FakeMaskProducer()
    producer.instanceCount = 2
    // Left half opaque, right half transparent.
    producer.maskFill = { x, _ in x < 3 ? 1.0 : 0.0 }
    let engine = makeEngine(producer: producer)

    let result = try engine.removeBackground(jpegData: try sourceData())

    XCTAssertTrue(LocalCutoutOperationCache.isValidOperationId(result.operationId))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.maskFilePath))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.cutoutFilePath))
    XCTAssertEqual(result.metrics.width, width)
    XCTAssertEqual(result.metrics.height, height)
    XCTAssertEqual(result.metrics.subjectCount, 2, "from allInstances.count")
    XCTAssertEqual(result.metrics.foregroundAreaRatio, 0.5, accuracy: 1e-9)
    XCTAssertNotNil(result.metrics.bounds)
  }

  func testOutputFilesLiveInsideTheCacheRoot() throws {
    let result = try makeEngine(producer: FakeMaskProducer())
      .removeBackground(jpegData: try sourceData())

    XCTAssertTrue(cache.isContained(URL(fileURLWithPath: result.maskFilePath)))
    XCTAssertTrue(cache.isContained(URL(fileURLWithPath: result.cutoutFilePath)))
  }

  func testChannelMapMatchesTheDartContract() throws {
    let producer = FakeMaskProducer()
    producer.maskFill = { x, _ in x < 3 ? 1.0 : 0.0 }
    let map = try makeEngine(producer: producer)
      .removeBackground(jpegData: try sourceData()).channelMap

    XCTAssertEqual(map["engine"] as? String, "apple_vision")
    XCTAssertEqual(map["engineVersion"] as? String, AppleVisionCutoutEngine.engineVersion)
    XCTAssertNotNil(map["operationId"] as? String)
    XCTAssertNotNil(map["maskFilePath"] as? String)
    XCTAssertNotNil(map["cutoutFilePath"] as? String)
    XCTAssertNotNil(map["latencyMs"] as? Int)
    // Deliberately absent: Dart must never receive a deletable directory (R10b).
    XCTAssertNil(map["operationDirectory"] ?? nil)

    let metrics = map["metrics"] as? [String: Any?]
    XCTAssertNotNil(metrics)
    for key in [
      "width", "height", "subjectCount", "foregroundAreaRatio",
      "borderForegroundRatio", "uncertainPixelRatio", "meanForegroundConfidence",
    ] {
      XCTAssertNotNil(metrics?[key] ?? nil, "missing \(key)")
    }
  }

  func testEngineVersionIsBoundedAndCarriesNoDeviceInformation() {
    let version = AppleVisionCutoutEngine.engineVersion
    XCTAssertLessThanOrEqual(version.count, 64)
    // The Vision request revision only — no model, no OS build, no identifiers.
    XCTAssertEqual(version, "vision-foreground-instance-mask-r1")
  }

  func testLatencyIsMeasured() throws {
    var now = Date(timeIntervalSince1970: 1000)
    let producer = FakeMaskProducer()
    producer.maskFill = { x, _ in x < 3 ? 1.0 : 0.0 }
    // Advance the injected clock while "Vision" runs, so the measured latency is
    // deterministic rather than dependent on how fast the simulator happens to be.
    producer.onProduce = { now = now.addingTimeInterval(1.5) }

    let result = try makeEngine(producer: producer, clock: { now })
      .removeBackground(jpegData: try sourceData())

    XCTAssertEqual(result.latencyMs, 1500)
  }

  // MARK: - Typed failures

  func testEmptySourceIsRejected() {
    XCTAssertEqual(
      code { _ = try makeEngine(producer: FakeMaskProducer()).removeBackground(jpegData: Data()) },
      .invalidOutput)
  }

  func testUndecodableSourceIsRejectedAndLeavesNoDirectory() {
    XCTAssertEqual(
      code {
        _ = try makeEngine(producer: FakeMaskProducer())
          .removeBackground(jpegData: Data([9, 9, 9, 9]))
      }, .invalidOutput)
    XCTAssertEqual(rootEntryCount(), 0)
  }

  func testNoInstancesIsNoSubject() throws {
    let producer = FakeMaskProducer()
    producer.instanceCount = 0
    let data = try sourceData()

    XCTAssertEqual(
      code { _ = try makeEngine(producer: producer).removeBackground(jpegData: data) },
      .noSubject)
    XCTAssertEqual(rootEntryCount(), 0)
  }

  func testVisionFailureIsTypedAndNotLeakedRaw() throws {
    let producer = FakeMaskProducer()
    producer.error = LocalCutoutError.visionRequestFailed
    let data = try sourceData()

    XCTAssertEqual(
      code { _ = try makeEngine(producer: producer).removeBackground(jpegData: data) },
      .internal)
  }

  func testAnUnexpectedErrorIsWrappedNotLeaked() throws {
    struct Surprise: Error { let secret = "should never reach Dart" }
    let producer = FakeMaskProducer()
    producer.error = Surprise()
    let data = try sourceData()

    do {
      _ = try makeEngine(producer: producer).removeBackground(jpegData: data)
      XCTFail("expected a typed failure")
    } catch let error as LocalCutoutError {
      XCTAssertEqual(error.code, .internalError)
      XCTAssertFalse(
        error.diagnostic.contains("should never reach Dart"),
        "raw error contents must not reach the diagnostic")
    }
  }

  func testMaskDimensionMismatchIsRefusedRatherThanResampled() throws {
    // The backend requires exact dimensions; resampling here would produce a mask
    // the server rejects anyway (§8.1).
    let producer = FakeMaskProducer()
    producer.maskWidth = width - 1
    let data = try sourceData()

    XCTAssertEqual(
      code { _ = try makeEngine(producer: producer).removeBackground(jpegData: data) },
      .invalidOutput)
    XCTAssertEqual(rootEntryCount(), 0)
  }

  func testAnEffectivelyEmptyMaskIsRefused() throws {
    let producer = FakeMaskProducer()
    producer.maskFill = { _, _ in 0.0 }
    let data = try sourceData()

    XCTAssertEqual(
      code { _ = try makeEngine(producer: producer).removeBackground(jpegData: data) },
      .invalidOutput)
    XCTAssertEqual(rootEntryCount(), 0)
  }

  func testAnEffectivelyFullMaskIsRefused() throws {
    let producer = FakeMaskProducer()
    producer.maskFill = { _, _ in 1.0 }
    let data = try sourceData()

    XCTAssertEqual(
      code { _ = try makeEngine(producer: producer).removeBackground(jpegData: data) },
      .invalidOutput)
  }

  // MARK: - Concurrency, cancellation, lifecycle

  func testASecondConcurrentOperationIsRefusedAsBusy() throws {
    let guardrail = LocalCutoutOperationGuard()
    let started = XCTestExpectation(description: "first operation started")
    let release = XCTestExpectation(description: "first operation released")

    let slow = FakeMaskProducer()
    slow.onProduce = {
      started.fulfill()
      _ = XCTWaiter.wait(for: [release], timeout: 5)
    }
    let slowEngine = makeEngine(producer: slow, guardrail: guardrail)
    let secondEngine = makeEngine(producer: FakeMaskProducer(), guardrail: guardrail)
    let data = try sourceData()

    DispatchQueue.global().async {
      _ = try? slowEngine.removeBackground(jpegData: data)
    }
    wait(for: [started], timeout: 5)

    let busy = code { _ = try secondEngine.removeBackground(jpegData: data) }
    release.fulfill()

    XCTAssertEqual(busy, .busy)
  }

  func testTheGuardIsReleasedAfterSuccessAndAfterFailure() throws {
    let guardrail = LocalCutoutOperationGuard()
    let producer = FakeMaskProducer()
    producer.maskFill = { x, _ in x < 3 ? 1.0 : 0.0 }
    let engine = makeEngine(producer: producer, guardrail: guardrail)

    _ = try engine.removeBackground(jpegData: try sourceData())
    XCTAssertFalse(guardrail.isBusy)
    XCTAssertNil(guardrail.activeOperationId)

    producer.instanceCount = 0
    _ = code { _ = try engine.removeBackground(jpegData: try self.sourceData()) }
    XCTAssertFalse(guardrail.isBusy, "the slot must free even on failure")
  }

  func testCancellationAbortsAndCleansUp() throws {
    let guardrail = LocalCutoutOperationGuard()
    let producer = FakeMaskProducer()
    // Cancel mid-flight, at the moment Vision is "running".
    producer.onProduce = { guardrail.cancel(nil) }
    let data = try sourceData()

    XCTAssertEqual(
      code {
        _ = try makeEngine(producer: producer, guardrail: guardrail)
          .removeBackground(jpegData: data)
      }, .cancelled)
    XCTAssertEqual(rootEntryCount(), 0, "no partial output may survive")
  }

  func testGuardAdmitsOnlyOneOfManyRacingCallers() {
    let guardrail = LocalCutoutOperationGuard()
    let admitted = LocalCutoutAtomicCounter()
    let group = DispatchGroup()

    for i in 0..<16 {
      group.enter()
      DispatchQueue.global().async {
        if guardrail.begin("op-\(i)") { admitted.increment() }
        group.leave()
      }
    }
    group.wait()

    XCTAssertEqual(admitted.value, 1)
  }

  func testGuardCancellationSemantics() {
    let guardrail = LocalCutoutOperationGuard()
    XCTAssertTrue(guardrail.begin("a"))
    XCTAssertFalse(guardrail.begin("b"), "second caller refused")

    guardrail.cancel("some-other-op")
    XCTAssertFalse(guardrail.isCancelled("a"), "cancelling another id is a no-op")

    guardrail.cancel("a")
    XCTAssertTrue(guardrail.isCancelled("a"))
    XCTAssertThrowsError(try guardrail.throwIfCancelled("a"))

    guardrail.end("a")
    XCTAssertTrue(guardrail.begin("c"))
    XCTAssertFalse(
      guardrail.isCancelled("c"),
      "a new operation must not inherit a previous cancellation")
  }

  func testAStaleReleaseCannotFreeAnotherCallersSlot() {
    let guardrail = LocalCutoutOperationGuard()
    XCTAssertTrue(guardrail.begin("a"))
    guardrail.end("stale-id")
    XCTAssertTrue(guardrail.isBusy)
    XCTAssertEqual(guardrail.activeOperationId, "a")
  }

  func testCleanupByOperationIdIsIdempotentAndIdOnly() throws {
    let producer = FakeMaskProducer()
    producer.maskFill = { x, _ in x < 3 ? 1.0 : 0.0 }
    let engine = makeEngine(producer: producer)
    let result = try engine.removeBackground(jpegData: try sourceData())

    XCTAssertTrue(engine.cleanup(result.operationId))
    XCTAssertFalse(FileManager.default.fileExists(atPath: result.maskFilePath))
    XCTAssertTrue(engine.cleanup(result.operationId))

    // Anything that is not a valid id is refused outright.
    XCTAssertFalse(engine.cleanup(""))
    XCTAssertFalse(engine.cleanup("../.."))
    XCTAssertFalse(engine.cleanup(tempRoot.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempRoot.path))
  }

  func testSweepUsesTheEngineClock() throws {
    var now = Date(timeIntervalSince1970: 10_000)
    let producer = FakeMaskProducer()
    producer.maskFill = { x, _ in x < 3 ? 1.0 : 0.0 }
    let engine = makeEngine(producer: producer, clock: { now })
    let result = try engine.removeBackground(jpegData: try sourceData())
    try FileManager.default.setAttributes(
      [.modificationDate: now],
      ofItemAtPath: try cache.operationDirectory(result.operationId).path)

    XCTAssertEqual(engine.sweepCache(maxAge: 600), 0)
    now = now.addingTimeInterval(1200)
    XCTAssertEqual(engine.sweepCache(maxAge: 600), 1)
  }

  func testDisposeClearsScratchFilesAndIsSafeTwice() throws {
    let producer = FakeMaskProducer()
    producer.maskFill = { x, _ in x < 3 ? 1.0 : 0.0 }
    let engine = makeEngine(producer: producer)
    _ = try engine.removeBackground(jpegData: try sourceData())
    XCTAssertGreaterThan(rootEntryCount(), 0)

    engine.dispose()
    XCTAssertEqual(rootEntryCount(), 0)
    engine.dispose()  // must not throw or crash
  }
}

/// Tiny thread-safe counter for the racing-callers test.
final class LocalCutoutAtomicCounter {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}
