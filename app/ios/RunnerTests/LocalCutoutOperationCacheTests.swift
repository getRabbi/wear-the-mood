import XCTest

/// Cache containment on iOS — the Phase 1 R10b security blocker (local BG §8.3).
///
/// The threat is the same one Android closed: if cleanup took a PATH, anything
/// reaching the method channel would have a filesystem delete primitive bounded
/// only by the app sandbox. Cleanup takes an operation ID, the ID is
/// pattern-validated, and every resolved URL is re-checked for containment inside
/// one app-owned root.
///
/// These assertions are deliberately the same set as
/// `LocalCutoutCacheStoreTest.kt`, so the two platforms cannot drift.
final class LocalCutoutOperationCacheTests: XCTestCase {

  private var tempRoot: URL!
  private var cacheRoot: URL!
  private var outsideRoot: URL!
  private var cache: LocalCutoutOperationCache!

  override func setUpWithError() throws {
    tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("wtm-cache-tests-\(UUID().uuidString)", isDirectory: true)
    cacheRoot = tempRoot.appendingPathComponent(
      LocalCutoutOperationCache.rootDirectoryName, isDirectory: true)
    outsideRoot = tempRoot.appendingPathComponent("definitely-not-ours", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
    cache = LocalCutoutOperationCache(root: cacheRoot)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempRoot)
  }

  private func makeOperation() throws -> String {
    let id = LocalCutoutOperationCache.newOperationId()
    try cache.createOperationDirectory(id)
    try Data([1, 2, 3]).write(to: try cache.maskFile(id))
    try Data([4, 5, 6]).write(to: try cache.cutoutFile(id))
    return id
  }

  private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  // MARK: - Operation ids

  func testGeneratedIdsAreRandom32CharHex() {
    let a = LocalCutoutOperationCache.newOperationId()
    let b = LocalCutoutOperationCache.newOperationId()
    XCTAssertEqual(a.count, 32)
    XCTAssertTrue(LocalCutoutOperationCache.isValidOperationId(a))
    XCTAssertNotEqual(a, b, "ids must be random, and therefore non-identifying")
  }

  func testOnlyWellFormedIdsAreAccepted() {
    let rejected: [String?] = [
      nil,
      "",
      "   ",
      "..",
      "../..",
      "../../Library",
      "abc",
      "ABCDEF0123456789ABCDEF0123456789",  // uppercase
      "0123456789abcdef0123456789abcde",  // 31 chars
      "0123456789abcdef0123456789abcdef0",  // 33 chars
      "0123456789abcdef0123456789abcd/.",  // separator
      "0123456789abcdef0123456789abcd..",
      "..%2F..%2Fdefinitely-not-ours",  // encoded traversal
      "/etc/passwd",
      "0123456789abcdef0123456789abcdeg",  // non-hex character
    ]
    for id in rejected {
      XCTAssertFalse(
        LocalCutoutOperationCache.isValidOperationId(id),
        "should reject: \(id ?? "nil")")
    }
  }

  // MARK: - Containment

  func testTraversalIdCannotResolve() {
    XCTAssertThrowsError(try cache.operationDirectory("../definitely-not-ours")) { error in
      XCTAssertEqual((error as? LocalCutoutError)?.code, .cacheUnavailable)
    }
  }

  func testAbsolutePathCannotResolve() {
    XCTAssertThrowsError(try cache.operationDirectory(outsideRoot.path)) { error in
      XCTAssertEqual((error as? LocalCutoutError)?.code, .cacheUnavailable)
    }
  }

  func testContainmentAcceptsOnlyTheRootAndItsDescendants() {
    XCTAssertTrue(cache.isContained(cacheRoot))
    XCTAssertTrue(cache.isContained(cacheRoot.appendingPathComponent("abc/def")))
    XCTAssertFalse(cache.isContained(outsideRoot))
    XCTAssertFalse(cache.isContained(tempRoot))
  }

  func testSamePrefixSiblingIsNotContained() throws {
    // "…/wtm-local-cutout-evil" shares the root's string prefix but is a SIBLING.
    // A naive hasPrefix without the separator would wrongly accept it.
    let sibling = tempRoot.appendingPathComponent(
      LocalCutoutOperationCache.rootDirectoryName + "-evil", isDirectory: true)
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
    XCTAssertFalse(cache.isContained(sibling))
  }

  func testSymlinkOutOfTheRootIsNotContained() throws {
    // A link planted inside the root that points outside it is the case the id
    // pattern cannot catch — only symlink resolution does.
    let link = cacheRoot.appendingPathComponent("escape", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideRoot)
    XCTAssertFalse(cache.isContained(link))
  }

  // MARK: - Delete

  func testDeleteRemovesTheOperationDirectoryAndFiles() throws {
    let id = try makeOperation()
    let directory = try cache.operationDirectory(id)
    XCTAssertTrue(exists(directory))

    XCTAssertTrue(cache.delete(id))
    XCTAssertFalse(exists(directory))
  }

  func testDeleteIsIdempotent() throws {
    let id = try makeOperation()
    XCTAssertTrue(cache.delete(id))
    XCTAssertTrue(cache.delete(id))
    XCTAssertTrue(
      cache.delete(LocalCutoutOperationCache.newOperationId()), "never existed")
  }

  func testDeleteRefusesMalformedIdsAndTouchesNothing() throws {
    let victim = outsideRoot.appendingPathComponent("important.txt")
    try Data([9]).write(to: victim)

    for id in ["", "..", "../definitely-not-ours", outsideRoot.path] {
      XCTAssertFalse(cache.delete(id), "should refuse: \(id)")
    }
    XCTAssertTrue(exists(victim), "nothing outside the root may be deleted")
    XCTAssertTrue(exists(outsideRoot))
  }

  func testNoArbitraryPathOutsideTheRootCanBeDeleted() throws {
    // The property in one test: throw every hostile string we can think of at it
    // and prove the outside file survives all of them.
    let victim = outsideRoot.appendingPathComponent("user-data.db")
    try Data([1]).write(to: victim)
    let hostile = [
      "../definitely-not-ours/user-data.db",
      "../../definitely-not-ours",
      "..%2F..%2Fdefinitely-not-ours",
      victim.path,
      "/",
      ".",
      "*",
    ]
    for id in hostile {
      _ = cache.delete(id)
      _ = try? cache.operationDirectory(id)
    }
    XCTAssertTrue(exists(victim))
    XCTAssertTrue(exists(cacheRoot))
  }

  // MARK: - Stale sweep

  func testSweepRemovesStaleAndKeepsFresh() throws {
    let stale = try makeOperation()
    let fresh = try makeOperation()
    let now = Date()
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-10 * 60 * 60)],
      ofItemAtPath: try cache.operationDirectory(stale).path)
    try FileManager.default.setAttributes(
      [.modificationDate: now],
      ofItemAtPath: try cache.operationDirectory(fresh).path)

    let removed = cache.sweepStale(maxAge: 6 * 60 * 60, now: now)

    XCTAssertEqual(removed, 1)
    XCTAssertFalse(exists(try cache.operationDirectory(stale)))
    XCTAssertTrue(exists(try cache.operationDirectory(fresh)))
  }

  func testSweepNeverLeavesTheRoot() throws {
    let victim = outsideRoot.appendingPathComponent("keepme")
    try Data([1]).write(to: victim)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 0)],
      ofItemAtPath: outsideRoot.path)

    _ = cache.sweepStale(maxAge: 1, now: Date())

    XCTAssertTrue(exists(victim))
    XCTAssertTrue(exists(outsideRoot))
  }

  func testSweepOnEmptyOrMissingRootIsZero() {
    XCTAssertEqual(cache.sweepStale(maxAge: 1, now: Date()), 0)

    let missing = tempRoot.appendingPathComponent("never-created", isDirectory: true)
    XCTAssertEqual(
      LocalCutoutOperationCache(root: missing).sweepStale(maxAge: 1, now: Date()), 0)
  }

  func testSweepIsBoundedByMaxAge() throws {
    let id = try makeOperation()
    let now = Date()
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-60)],
      ofItemAtPath: try cache.operationDirectory(id).path)

    // Inside the window: kept. Outside: removed. Never a guess.
    XCTAssertEqual(cache.sweepStale(maxAge: 600, now: now), 0)
    XCTAssertEqual(cache.sweepStale(maxAge: 30, now: now), 1)
  }

  func testClearEmptiesTheRootButKeepsTheRoot() throws {
    _ = try makeOperation()
    _ = try makeOperation()
    XCTAssertEqual(cache.clear(), 2)
    XCTAssertTrue(exists(cacheRoot))
    let remaining = try FileManager.default.contentsOfDirectory(atPath: cacheRoot.path)
    XCTAssertEqual(remaining.count, 0)
  }

  // MARK: - File placement

  func testFilesLiveInsideTheOperationDirectoryWithNonIdentifyingNames() throws {
    let id = try makeOperation()
    let mask = try cache.maskFile(id)
    let cutout = try cache.cutoutFile(id)

    XCTAssertTrue(cache.isContained(mask))
    XCTAssertTrue(cache.isContained(cutout))
    XCTAssertEqual(mask.lastPathComponent, "mask.png")
    XCTAssertEqual(cutout.lastPathComponent, "cutout.png")
    // The only variable component is the random operation id.
    XCTAssertTrue(
      LocalCutoutOperationCache.isValidOperationId(
        mask.deletingLastPathComponent().lastPathComponent))
  }

  func testCacheAndAndroidAgreeOnTheContract() {
    // If either side changes these, the two platforms have silently diverged.
    XCTAssertEqual(LocalCutoutOperationCache.rootDirectoryName, "wtm-local-cutout")
    XCTAssertEqual(LocalCutoutOperationCache.maskFileName, "mask.png")
    XCTAssertEqual(LocalCutoutOperationCache.cutoutFileName, "cutout.png")
    XCTAssertEqual(LocalCutoutOperationCache.defaultMaxAge, 6 * 60 * 60)
  }
}
