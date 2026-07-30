import CoreVideo
import Foundation
import XCTest

/// Diagnostics payload and export bundle (iOS Phase 3).
///
/// Two things are worth proving here, and they pull in opposite directions:
/// the bundle must carry enough to diagnose a real device failure, and it must
/// carry nothing that could leak a credential or identify a person. The allow-list
/// test below is the one that matters — it fails if anybody adds a field without
/// thinking about it, which is exactly the mistake a share sheet punishes.
final class LocalCutoutDiagnosticsTests: XCTestCase {

  private var tempRoot: URL!
  private var cache: LocalCutoutOperationCache!
  private var exporter: LocalCutoutDiagnosticExporter!

  override func setUpWithError() throws {
    tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("wtm-diag-tests-\(UUID().uuidString)", isDirectory: true)
    let root = tempRoot.appendingPathComponent(
      LocalCutoutOperationCache.rootDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    cache = LocalCutoutOperationCache(root: root)
    exporter = LocalCutoutDiagnosticExporter(cache: cache)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempRoot)
  }

  /// A diagnostics object with EVERY optional populated, so the allow-list test
  /// sees the widest payload the type can produce.
  private func fullyPopulated() -> LocalCutoutDiagnostics {
    var d = LocalCutoutDiagnostics.current()
    d.stage = .completed
    d.sourceWidth = 1600
    d.sourceHeight = 1200
    d.maskWidth = 1600
    d.maskHeight = 1200
    d.cutoutWidth = 1600
    d.cutoutHeight = 1200
    d.sourceByteCount = 412_345
    d.observationCount = 1
    d.instanceCount = 2
    d.maskPixelFormat = "L00f"
    d.maskPlaneCount = 1
    d.maskBytesPerRow = 6400
    d.maskStatistics = PixelBufferMaskCompositor.inspectFloatMask(
      [0.0, 0.5, 1.0] as [Float32])
    d.meanAlphaCoverage = 0.42
    d.decodeMs = 12
    d.inferenceMs = 800
    d.maskMs = 40
    d.compositeMs = 55
    d.encodeMs = 90
    d.writeMs = 8
    d.totalMs = 1005
    d.localEndpointStatus = 201
    d.failureCode = "invalid_output"
    d.failureDetail = "Mask failed the safety envelope: total=3 nan=0."
    return d
  }

  // MARK: - The allow-list

  func testPayloadKeysAreExactlyTheAllowList() throws {
    let keys = Set(fullyPopulated().payload.keys)
    let expected: Set<String> = [
      "schema", "platform", "engine", "engine_version",
      "app_version", "app_build", "ios_version", "device_model", "stage",
      "mask_safety_low", "mask_safety_high", "max_invalid_mask_ratio",
      "source_width", "source_height", "mask_width", "mask_height",
      "cutout_width", "cutout_height", "source_byte_count",
      "observation_count", "instance_count",
      "mask_pixel_format", "mask_plane_count", "mask_bytes_per_row",
      "mask_total_pixels", "mask_nan_count", "mask_positive_infinity_count",
      "mask_negative_infinity_count", "mask_out_of_envelope_count",
      "mask_invalid_ratio", "mask_finite_min", "mask_finite_max",
      "mean_alpha_coverage",
      "decode_ms", "inference_ms", "mask_ms", "composite_ms", "encode_ms",
      "write_ms", "total_ms",
      "local_endpoint_status", "failure_code", "failure_detail",
    ]
    XCTAssertEqual(
      keys, expected,
      """
      The diagnostic payload changed. This bundle leaves the device through a \
      share sheet, so every field is deliberate: update this list only after \
      confirming the new value cannot carry a token, a user id, a signed URL, an \
      R2 key or a filesystem path.
      """)
  }

  func testPayloadCarriesNoCredentialOrPathShapedValues() throws {
    let json = String(data: try fullyPopulated().encoded(), encoding: .utf8) ?? ""
    XCTAssertFalse(json.isEmpty)
    for forbidden in [
      "token", "bearer", "authorization", "supabase", "apikey", "api_key",
      "secret", "password", "signature", "x-amz", "r2.", "http://", "https://",
      "/Users/", "/var/mobile", "file://", "@",
    ] {
      XCTAssertFalse(
        json.lowercased().contains(forbidden.lowercased()),
        "diagnostic JSON must not contain \(forbidden)")
    }
  }

  func testPayloadOmitsUnsetFieldsRatherThanEmittingNulls() throws {
    let sparse = LocalCutoutDiagnostics.current()
    let keys = Set(sparse.payload.keys)
    XCTAssertFalse(keys.contains("source_width"))
    XCTAssertFalse(keys.contains("mask_finite_min"))
    XCTAssertFalse(keys.contains("failure_code"))
    // The fixed environment block is always present.
    XCTAssertTrue(keys.contains("device_model"))
    XCTAssertTrue(keys.contains("ios_version"))
    XCTAssertTrue(keys.contains("stage"))
  }

  func testPayloadRecordsTheEnvelopeUnderTest() throws {
    let payload = fullyPopulated().payload
    // Phase 3 exists to judge these numbers, so the bundle must state which ones
    // were in force when it was captured.
    XCTAssertEqual(try XCTUnwrap(payload["mask_safety_low"] as? Double), -0.10, accuracy: 1e-6)
    XCTAssertEqual(try XCTUnwrap(payload["mask_safety_high"] as? Double), 1.10, accuracy: 1e-6)
    XCTAssertEqual(try XCTUnwrap(payload["mask_finite_min"] as? Double), 0.0, accuracy: 1e-6)
    XCTAssertEqual(try XCTUnwrap(payload["mask_finite_max"] as? Double), 1.0, accuracy: 1e-6)
  }

  func testEncodedPayloadIsValidSortedJSON() throws {
    let data = try fullyPopulated().encoded()
    let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?["platform"] as? String, "ios")
    XCTAssertEqual(decoded?["engine"] as? String, "apple_vision")
  }

  func testHardwareModelIsAModelNotADeviceName() {
    let model = LocalCutoutDiagnostics.hardwareModel()
    XCTAssertFalse(model.isEmpty)
    // `uname` machine strings have no spaces; a user-chosen device name usually
    // does ("Rabbi's iPhone"), which is exactly what must never appear here.
    XCTAssertFalse(model.contains(" "))
    XCTAssertFalse(model.contains("'"))
  }

  func testFormatCodeRendersTheCoreVideoFourCC() {
    XCTAssertEqual(
      LocalCutoutDiagnostics.formatCode(kCVPixelFormatType_OneComponent8), "L008")
    XCTAssertEqual(
      LocalCutoutDiagnostics.formatCode(kCVPixelFormatType_OneComponent32Float),
      "L00f")
  }

  // MARK: - Export bundle

  private func stageArtifacts(_ id: String) throws {
    try cache.createOperationDirectory(id)
    try Data([1, 2, 3, 4]).write(to: try cache.maskFile(id))
    try Data([5, 6, 7, 8]).write(to: try cache.cutoutFile(id))
    try exporter.writeSource(Data(repeating: 9, count: 64), operationId: id)
    try exporter.writeResult(fullyPopulated(), operationId: id)
  }

  func testArchiveContainsTheOperationAndIsNonEmpty() throws {
    let id = LocalCutoutOperationCache.newOperationId()
    try stageArtifacts(id)

    let archive = try exporter.makeArchive(operationId: id)

    XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    let size =
      (try FileManager.default.attributesOfItem(atPath: archive.path))[.size] as? Int
    XCTAssertGreaterThan(size ?? 0, 0)
    XCTAssertTrue(cache.isContained(archive), "the archive must stay inside the root")
    XCTAssertTrue(archive.lastPathComponent.hasPrefix(id), "one id, one bundle")
  }

  func testExportRefusesAMalformedOperationId() {
    for bad in ["", "..", "../escape", "NOTHEX", "/etc/passwd"] {
      XCTAssertThrowsError(try exporter.archiveURL(bad), "should refuse: \(bad)")
      XCTAssertThrowsError(try exporter.makeArchive(operationId: bad))
    }
  }

  /// A ZIP that is missing the artifacts it exists to carry looks like evidence but
  /// is not, so it must fail loudly rather than export a shell.
  func testExportRefusesWhenArtifactsAreMissing() throws {
    let id = LocalCutoutOperationCache.newOperationId()
    try cache.createOperationDirectory(id)
    // Mask present, result.json absent.
    try Data([1, 2, 3]).write(to: try cache.maskFile(id))

    XCTAssertThrowsError(try exporter.makeArchive(operationId: id)) {
      XCTAssertEqual(($0 as? LocalCutoutError)?.code, .internalError)
    }
  }

  func testExportRefusesAnUnknownOperation() {
    let id = LocalCutoutOperationCache.newOperationId()
    XCTAssertThrowsError(try exporter.makeArchive(operationId: id))
  }

  func testWritingSourceRefusesEmptyBytes() {
    let id = LocalCutoutOperationCache.newOperationId()
    XCTAssertThrowsError(try exporter.writeSource(Data(), operationId: id)) {
      XCTAssertEqual(($0 as? LocalCutoutError)?.code, .invalidOutput)
    }
  }

  func testArtifactsAllLiveInsideTheSameOperationDirectory() throws {
    let id = LocalCutoutOperationCache.newOperationId()
    try stageArtifacts(id)
    let directory = try cache.operationDirectory(id)

    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

    XCTAssertTrue(names.contains(LocalCutoutOperationCache.maskFileName))
    XCTAssertTrue(names.contains(LocalCutoutOperationCache.cutoutFileName))
    XCTAssertTrue(names.contains(LocalCutoutDiagnosticExporter.sourceFileName))
    XCTAssertTrue(names.contains(LocalCutoutDiagnosticExporter.resultFileName))
    for name in names {
      XCTAssertTrue(
        cache.isContained(directory.appendingPathComponent(name)),
        "\(name) escaped the operation directory")
    }
  }

  func testRewritingAnArchiveReplacesTheStaleOne() throws {
    let id = LocalCutoutOperationCache.newOperationId()
    try stageArtifacts(id)
    let first = try exporter.makeArchive(operationId: id)
    let firstSize =
      (try FileManager.default.attributesOfItem(atPath: first.path))[.size] as? Int

    // Add another artifact, re-export: the bundle must reflect the new state.
    try Data(repeating: 7, count: 4096).write(
      to: try cache.operationDirectory(id).appendingPathComponent("extra.bin"))
    let second = try exporter.makeArchive(operationId: id)
    let secondSize =
      (try FileManager.default.attributesOfItem(atPath: second.path))[.size] as? Int

    XCTAssertEqual(first, second, "same id, same archive path")
    XCTAssertNotEqual(firstSize, secondSize, "a stale archive must not be reshared")
  }

  func testDeletingTheOperationRemovesItsArtifacts() throws {
    let id = LocalCutoutOperationCache.newOperationId()
    try stageArtifacts(id)
    let directory = try cache.operationDirectory(id)

    XCTAssertTrue(cache.delete(id))

    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }
}
