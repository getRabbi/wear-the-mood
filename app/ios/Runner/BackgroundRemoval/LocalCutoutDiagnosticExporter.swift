import Foundation

/// Packages one operation's diagnostic artifacts into a single ZIP (iOS Phase 3).
///
/// The bundle is deliberately one file: the founder develops on Windows, so the
/// only practical route off an iPhone is the share sheet, and four separate
/// attachments invite a partial export where the mask and the cutout come from
/// different runs. Everything here belongs to ONE operation id.
///
/// Zipping uses `NSFileCoordinator(.forUploading)`, which Foundation implements by
/// producing a zip of a directory. That avoids adding a compression dependency for
/// an internal-only diagnostic (CLAUDE.md §2.2 — every dependency needs a licence
/// entry and founder sign-off; this needs neither).
///
/// SECURITY: the same rule as the rest of the cache. An operation ID comes in,
/// paths go out, and every resolved URL is proven to sit inside the one app-owned
/// root before anything is read, written or archived. Nothing here accepts a path
/// from Dart.
struct LocalCutoutDiagnosticExporter {

  static let sourceFileName = "source.bin"
  static let resultFileName = "result.json"
  static let archiveSuffix = "-diagnostic.zip"

  private let cache: LocalCutoutOperationCache
  private let fileManager: FileManager

  init(cache: LocalCutoutOperationCache, fileManager: FileManager = .default) {
    self.cache = cache
    self.fileManager = fileManager
  }

  /// Write the exact bytes Vision was given, beside its outputs.
  ///
  /// Named `.bin`, not `.jpg`: these are whatever Flutter compressed and will
  /// upload, and mislabelling the extension would invite an inspector to assume a
  /// format rather than check one. The Phase 3 report states the real type.
  @discardableResult
  func writeSource(_ data: Data, operationId: String) throws -> URL {
    guard !data.isEmpty else { throw LocalCutoutError.sourceMissing }
    let url = try file(operationId, named: Self.sourceFileName)
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw LocalCutoutError.cacheWriteFailed
    }
    return url
  }

  @discardableResult
  func writeResult(_ diagnostics: LocalCutoutDiagnostics, operationId: String) throws
    -> URL
  {
    let url = try file(operationId, named: Self.resultFileName)
    do {
      try diagnostics.encoded().write(to: url, options: .atomic)
    } catch let error as LocalCutoutError {
      throw error
    } catch {
      throw LocalCutoutError.cacheWriteFailed
    }
    return url
  }

  /// Zip the operation directory and return the archive URL.
  ///
  /// The archive is written INSIDE the operation directory's parent — the cache
  /// root — so it is swept by the same stale-cleanup as everything else and never
  /// escapes the sandboxed area the rest of this feature is confined to.
  func makeArchive(operationId: String) throws -> URL {
    let directory = try cache.operationDirectory(operationId)
    guard fileManager.fileExists(atPath: directory.path) else {
      throw LocalCutoutError.diagnosticsUnavailable
    }
    // Refuse to export a bundle that is missing the very artifacts it exists to
    // carry — a half-empty ZIP is worse than a clear failure, because it looks
    // like evidence.
    for required in [Self.resultFileName, LocalCutoutOperationCache.maskFileName] {
      let candidate = directory.appendingPathComponent(required)
      guard fileManager.fileExists(atPath: candidate.path) else {
        throw LocalCutoutError.diagnosticsUnavailable
      }
    }

    let destination = try archiveURL(operationId)
    // A stale archive from a previous export of the same id must not be shared by
    // mistake.
    if fileManager.fileExists(atPath: destination.path) {
      try? fileManager.removeItem(at: destination)
    }

    var coordinatorError: NSError?
    var copyError: Error?
    NSFileCoordinator().coordinate(
      readingItemAt: directory, options: [.forUploading], error: &coordinatorError
    ) { zipped in
      do {
        try fileManager.copyItem(at: zipped, to: destination)
      } catch {
        copyError = error
      }
    }
    if coordinatorError != nil || copyError != nil {
      throw LocalCutoutError.diagnosticsUnavailable
    }
    guard
      let size = (try? fileManager.attributesOfItem(atPath: destination.path))?[.size]
        as? Int, size > 0
    else {
      throw LocalCutoutError.diagnosticsUnavailable
    }
    return destination
  }

  /// Where this operation's archive lives. Proven contained, like every other path.
  func archiveURL(_ operationId: String) throws -> URL {
    guard LocalCutoutOperationCache.isValidOperationId(operationId) else {
      throw LocalCutoutError.malformedOperationId
    }
    let candidate = URL(fileURLWithPath: cache.rootPath, isDirectory: true)
      .appendingPathComponent(operationId + Self.archiveSuffix)
    let resolved = candidate.standardizedFileURL
    guard cache.isContained(resolved) else {
      throw LocalCutoutError.cacheNotContained
    }
    return resolved
  }

  private func file(_ operationId: String, named name: String) throws -> URL {
    let directory = try cache.createOperationDirectory(operationId)
    let url = directory.appendingPathComponent(name)
    guard cache.isContained(url) else { throw LocalCutoutError.cacheNotContained }
    return url
  }
}
