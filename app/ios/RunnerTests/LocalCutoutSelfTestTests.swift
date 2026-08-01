import CoreGraphics
import XCTest

/// The native contract self-test (local BG §4).
///
/// These assertions matter because they are the only ones that look at what the
/// REAL encoders produce. `encodeCutoutPNG` had never once worked on any device —
/// it composed through a `CGBitmapContext` in a pixel format CoreGraphics cannot
/// represent, so it returned nil every time — and that survived a green compile
/// check, 75 green Swift tests and a typed cloud fallback that made the result look
/// normal to a user.
///
/// So the self-test is proven here to actually DISCRIMINATE: it must pass on a
/// healthy encoder and fail on each specific way an encoder can be broken. A
/// self-test that always passes is worse than none, because it converts an unknown
/// into a false assurance.
///
/// The mirror of `LocalCutoutSelfTestTest.kt`, so the two platforms cannot drift.
final class LocalCutoutSelfTestTests: XCTestCase {

  private var tempRoot: URL!
  private var cache: LocalCutoutOperationCache!

  override func setUpWithError() throws {
    tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("wtm-selftest-\(UUID().uuidString)", isDirectory: true)
    let cacheRoot = tempRoot.appendingPathComponent(
      LocalCutoutOperationCache.rootDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    cache = LocalCutoutOperationCache(root: cacheRoot)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempRoot)
  }

  // MARK: - the contract half

  func testPassesWithTheRealEncodersAndCache() {
    let reply = LocalCutoutSelfTest.run(
      cache: cache, engineVersion: AppleVisionCutoutEngine.engineVersion,
      platformAvailable: false)
    XCTAssertEqual(reply["status"] as? String, "pass")
    XCTAssertEqual(reply["failureCode"] as? String, LocalCutoutSelfTest.Failure.none)
    XCTAssertEqual(reply["encoderOk"] as? Bool, true)
    XCTAssertEqual(reply["cacheOk"] as? Bool, true)
    XCTAssertEqual(reply["engine"] as? String, AppleVisionCutoutEngine.engineName)
  }

  /// Below iOS 17 the correct answer is "no model", not "broken encoder". A device
  /// that reports a failure here would look like an engine defect in the dashboards.
  func testUnsupportedPlatformStillPassesTheContract() {
    let reply = LocalCutoutSelfTest.run(
      cache: cache, engineVersion: "v", platformAvailable: false)
    XCTAssertEqual(reply["status"] as? String, "pass")
    XCTAssertEqual(reply["modelAvailable"] as? Bool, false)
    XCTAssertEqual(reply["platformAvailable"] as? Bool, false)
  }

  func testBlankEngineVersionIsAFailure() {
    let reply = LocalCutoutSelfTest.run(
      cache: cache, engineVersion: "   ", platformAvailable: false)
    XCTAssertEqual(reply["status"] as? String, "fail")
    XCTAssertEqual(reply["failureCode"] as? String, LocalCutoutSelfTest.Failure.engineVersion)
  }

  /// An unwritable cache root must be reported as a CACHE failure, not as an
  /// encoder failure — the two route to completely different investigations.
  ///
  /// The root is blocked by a regular FILE, exactly as `LocalCutoutSelfTestTest.kt`
  /// does it. A merely absent directory is not unwritable: `createDirectory` is
  /// called `withIntermediateDirectories: true`, so it would create the whole
  /// chain and the self-test would correctly report a pass — which is what this
  /// test originally asserted against, and it was the test that was wrong.
  func testUnwritableCacheRootFailsTyped() throws {
    let blocker = tempRoot.appendingPathComponent("not-a-directory")
    try Data([0]).write(to: blocker)
    let broken = LocalCutoutOperationCache(
      root: blocker.appendingPathComponent("cache", isDirectory: true))
    let reply = LocalCutoutSelfTest.run(
      cache: broken, engineVersion: "v", platformAvailable: false)
    XCTAssertEqual(reply["status"] as? String, "fail")
    XCTAssertEqual(reply["cacheOk"] as? Bool, false)
  }

  func testLeavesNoScratchBehind() throws {
    _ = LocalCutoutSelfTest.run(
      cache: cache, engineVersion: "v", platformAvailable: false)
    let root = tempRoot.appendingPathComponent(
      LocalCutoutOperationCache.rootDirectoryName, isDirectory: true)
    let children = try FileManager.default.contentsOfDirectory(atPath: root.path)
    XCTAssertTrue(children.isEmpty, "the self test must clean up after itself")
  }

  /// The reply is telemetry. It must never carry a path, bytes or anything that
  /// could identify a person or a photo (§10).
  func testReplyCarriesOnlyBoundedSafeFields() {
    let reply = LocalCutoutSelfTest.run(
      cache: cache, engineVersion: "v", platformAvailable: false)
    let allowed: Set<String> = [
      "status", "engine", "engineVersion", "channelVersion", "encoderOk", "cacheOk",
      "platformAvailable", "modelAvailable", "failureCode",
    ]
    XCTAssertEqual(Set(reply.keys), allowed)
    for (key, value) in reply {
      if let text = value as? String {
        XCTAssertFalse(text.contains("/"), "\(key) looks like a path")
        XCTAssertFalse(text.contains(tempRoot.path), "\(key) leaked the cache root")
      }
    }
  }

  // MARK: - the encoders it is meant to catch

  /// The exact defect fixed in bf945e2: a cutout encoder that cannot represent
  /// straight alpha returned nil for every call. Prove the round trip really keeps
  /// a transparent pixel transparent and a half-alpha pixel half.
  func testCutoutEncoderRoundTripPreservesTransparencyAndSoftAlpha() throws {
    let width = 4
    let height = 4
    var bgra = [UInt8](repeating: 0, count: width * height * 4)
    for index in 0..<(width * height) {
      let offset = index * 4
      switch index % 3 {
      case 0: bgra[offset + 3] = 0
      case 1: bgra[offset + 2] = 255; bgra[offset + 3] = 128
      default: bgra[offset + 1] = 255; bgra[offset + 3] = 255
      }
    }
    let png = try PixelBufferMaskCompositor.encodeCutoutPNG(
      bgra: bgra, width: width, height: height)
    XCTAssertFalse(png.isEmpty)

    let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, width)
    XCTAssertEqual(image.height, height)
    XCTAssertTrue(image.alphaInfo != .none, "a cutout PNG without alpha is an opaque rectangle")
  }

  /// The Android mirror of the same class of defect: the mask value must live in a
  /// channel the server reads. A uniformly opaque mask made every ingest 422.
  func testMaskEncoderRoundTripPreservesTheValue() throws {
    let width = 4
    let height = 4
    let alpha: [UInt8] = (0..<(width * height)).map { UInt8(($0 * 17) % 256) }
    let png = try PixelBufferMaskCompositor.encodeMaskPNG(
      alpha: alpha, width: width, height: height)
    XCTAssertFalse(png.isEmpty)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, width)
    XCTAssertEqual(image.height, height)
  }

  // MARK: - the Vision fixture

  func testFixtureImageIsGeneratedAndUsable() throws {
    let image = try XCTUnwrap(LocalCutoutSelfTest.makeFixtureImage(width: 64, height: 96))
    XCTAssertEqual(image.width, 64)
    XCTAssertEqual(image.height, 96)
  }

  /// Broad structural invariants, never exact pixels — an OS revision that changes
  /// resampling by a hair must not be reported as a broken engine.
  func testFixtureOutcomeAcceptsAHealthyMask() {
    XCTAssertEqual(
      LocalCutoutSelfTest.fixtureOutcome(
        maskWidth: 64, maskHeight: 96, sourceWidth: 64, sourceHeight: 96,
        instanceCount: 1, coverage: 0.3),
      .passed)
  }

  func testFixtureOutcomeRejectsNoInstance() {
    XCTAssertEqual(
      LocalCutoutSelfTest.fixtureOutcome(
        maskWidth: 64, maskHeight: 96, sourceWidth: 64, sourceHeight: 96,
        instanceCount: 0, coverage: 0.3),
      .failed)
  }

  func testFixtureOutcomeRejectsMismatchedDimensions() {
    XCTAssertEqual(
      LocalCutoutSelfTest.fixtureOutcome(
        maskWidth: 32, maskHeight: 96, sourceWidth: 64, sourceHeight: 96,
        instanceCount: 1, coverage: 0.3),
      .failed)
  }

  func testFixtureOutcomeRejectsAnEmptyOrFullMask() {
    for coverage in [0.0, 0.005, 0.995, 1.0] {
      XCTAssertEqual(
        LocalCutoutSelfTest.fixtureOutcome(
          maskWidth: 64, maskHeight: 96, sourceWidth: 64, sourceHeight: 96,
          instanceCount: 1, coverage: coverage),
        .failed,
        "coverage \(coverage) must not be accepted")
    }
  }

  func testFixtureOutcomeRejectsNonFiniteCoverage() {
    XCTAssertEqual(
      LocalCutoutSelfTest.fixtureOutcome(
        maskWidth: 64, maskHeight: 96, sourceWidth: 64, sourceHeight: 96,
        instanceCount: 1, coverage: .nan),
      .failed)
  }
}
