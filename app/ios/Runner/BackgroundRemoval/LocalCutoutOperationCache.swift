import Foundation

/// Operation-ID-scoped cache for local cutout output (local BG §8.3, blocker R10b).
///
/// Deliberately identical in behaviour to Android's `LocalCutoutCacheStore`, down
/// to the id pattern and the file names, so the two platforms cannot drift.
///
/// THE SECURITY RULE: Dart never hands us a path to delete. It hands us an
/// OPERATION ID, validated against a strict pattern and resolved inside a single
/// app-owned root. A `cleanup(path)` contract would be a filesystem delete
/// primitive reachable from the method channel, scoped only by the app sandbox.
/// So identifiers flow in and paths flow out.
///
/// `standardizedFileURL` + `resolvingSymlinksInPath` is applied before every create
/// and delete, which catches what the pattern cannot: a symlink planted inside the
/// root that points outside it.
struct LocalCutoutOperationCache {

  /// Directory name under the app caches directory. Nothing outside it is ours.
  static let rootDirectoryName = "wtm-local-cutout"
  static let maskFileName = "mask.png"
  static let cutoutFileName = "cutout.png"

  /// Default stale window, matching Android and the Dart default.
  static let defaultMaxAge: TimeInterval = 6 * 60 * 60

  /// 32 lowercase hex characters. Deliberately narrow: no separators, no dots, no
  /// case variance, so traversal, absolute paths, percent-encoding and alternate
  /// representations are rejected by construction rather than by blacklist.
  private static let idLength = 32
  private static let allowedIdCharacters = Set("0123456789abcdef")

  /// The one directory this cache may ever touch, fully resolved.
  private let root: URL
  private let fileManager: FileManager

  var rootPath: String { root.path }

  init(root: URL, fileManager: FileManager = .default) {
    self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    self.fileManager = fileManager
  }

  /// The engine's real cache root: `<Caches>/wtm-local-cutout/`.
  static func inCachesDirectory(fileManager: FileManager = .default) throws
    -> LocalCutoutOperationCache
  {
    guard
      let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    else {
      throw LocalCutoutError.cacheWriteFailed
    }
    let root = caches.appendingPathComponent(rootDirectoryName, isDirectory: true)
    try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    return LocalCutoutOperationCache(root: root, fileManager: fileManager)
  }

  static func isValidOperationId(_ id: String?) -> Bool {
    guard let id, id.count == idLength else { return false }
    return id.allSatisfy { allowedIdCharacters.contains($0) }
  }

  /// A random, non-identifying operation id (§4: no user data in file names).
  static func newOperationId() -> String {
    var bytes = [UInt8](repeating: 0, count: idLength / 2)
    if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
      // Fall back to the system RNG; this id is a scratch-file name, not a secret.
      bytes = (0..<bytes.count).map { _ in UInt8.random(in: 0...255) }
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  /// True when `candidate` is the root itself or lives strictly beneath it.
  ///
  /// The trailing-separator comparison matters: a sibling directory named
  /// `wtm-local-cutout-evil` shares the root's string prefix but is NOT contained.
  func isContained(_ candidate: URL) -> Bool {
    let target = candidate.standardizedFileURL.resolvingSymlinksInPath().path
    let base = root.path
    if target == base { return true }
    return target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
  }

  /// Resolve an operation directory, proving containment.
  func operationDirectory(_ operationId: String) throws -> URL {
    guard Self.isValidOperationId(operationId) else {
      throw LocalCutoutError.malformedOperationId
    }
    let candidate = root.appendingPathComponent(operationId, isDirectory: true)
    // Resolve BEFORE checking: standardization collapses `..` and `.`, and symlink
    // resolution defeats a planted link. Only then is containment meaningful.
    let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
    guard isContained(resolved) else { throw LocalCutoutError.cacheNotContained }
    return resolved
  }

  @discardableResult
  func createOperationDirectory(_ operationId: String) throws -> URL {
    let directory = try operationDirectory(operationId)
    if !fileManager.fileExists(atPath: directory.path) {
      do {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      } catch {
        throw LocalCutoutError.cacheWriteFailed
      }
    }
    return directory
  }

  func maskFile(_ operationId: String) throws -> URL {
    try operationDirectory(operationId).appendingPathComponent(Self.maskFileName)
  }

  func cutoutFile(_ operationId: String) throws -> URL {
    try operationDirectory(operationId).appendingPathComponent(Self.cutoutFileName)
  }

  /// Delete one operation's directory.
  ///
  /// Idempotent — an unknown or already-removed id is a success. A malformed id is
  /// a silent `false` rather than a throw: cleanup runs on teardown paths where
  /// raising helps nobody.
  @discardableResult
  func delete(_ operationId: String) -> Bool {
    guard let directory = try? operationDirectory(operationId) else { return false }
    return removeIfContained(directory)
  }

  /// Remove operation directories last modified before `now - maxAge` — recovery
  /// for anything a crash or force-quit orphaned.
  ///
  /// Only immediate children of the root are considered, and each is
  /// containment-checked, so this can never walk out of the cache root.
  @discardableResult
  func sweepStale(maxAge: TimeInterval = defaultMaxAge, now: Date = Date()) -> Int {
    guard
      let children = try? fileManager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsSubdirectoryDescendants]
      )
    else { return 0 }

    let cutoff = now.addingTimeInterval(-max(0, maxAge))
    var removed = 0
    for child in children {
      let modified =
        (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate
      // An unreadable timestamp is treated as fresh: never delete on a guess.
      guard let modified, modified < cutoff else { continue }
      if removeIfContained(child) { removed += 1 }
    }
    return removed
  }

  /// Remove everything under the root (engine disposal / hard reset).
  @discardableResult
  func clear() -> Int {
    guard
      let children = try? fileManager.contentsOfDirectory(
        at: root, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
    else { return 0 }
    return children.reduce(0) { removeIfContained($1) ? $0 + 1 : $0 }
  }

  /// The only place this type deletes anything: containment is re-proved here, so
  /// no caller can bypass it.
  private func removeIfContained(_ target: URL) -> Bool {
    guard isContained(target) else { return false }
    if !fileManager.fileExists(atPath: target.path) { return true }
    do {
      try fileManager.removeItem(at: target)
      return true
    } catch {
      // Left for the next sweep; an orphan is recoverable, a crash is not.
      return false
    }
  }
}
