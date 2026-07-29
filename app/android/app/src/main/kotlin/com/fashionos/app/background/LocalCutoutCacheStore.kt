package com.fashionos.app.background

import java.io.File
import java.security.SecureRandom

/**
 * Operation-ID-scoped cache for local cutout output (local BG §8.2, blocker R10b).
 *
 * THE SECURITY RULE: Dart never hands us a path to delete. It hands us an
 * OPERATION ID, which is validated against a strict pattern and resolved inside a
 * single app-owned root. A path that arrived over the method channel could be
 * anything — `../../databases`, an absolute path, a symlink — and deleting it
 * because "native returned it" would be a filesystem-wide delete primitive
 * reachable from Dart. So paths flow OUT only; identifiers flow IN.
 *
 * Every create and delete additionally re-checks canonical containment, which
 * catches the case the pattern cannot: a symlink planted inside the root that
 * points outside it.
 *
 * Pure `java.io` — no Android framework types — so all of this is unit-testable
 * against a temp directory with plain JUnit.
 */
class LocalCutoutCacheStore(root: File) {

    /** The one directory this store may ever touch, fully resolved. */
    private val canonicalRoot: File = root.canonicalFile

    val rootPath: String get() = canonicalRoot.path

    companion object {
        /** Directory name under the app cache dir. Nothing outside it is ours. */
        const val ROOT_DIR_NAME = "wtm-local-cutout"

        const val MASK_FILE_NAME = "mask.png"
        const val CUTOUT_FILE_NAME = "cutout.png"

        /**
         * 32 lowercase hex characters. Deliberately narrow: no separators, no dots,
         * no case variance, so traversal, absolute paths and alternate encodings are
         * all rejected by construction rather than by blacklist.
         */
        private val ID_PATTERN = Regex("^[a-f0-9]{32}$")

        private val RANDOM = SecureRandom()

        fun isValidOperationId(id: String?): Boolean =
            id != null && ID_PATTERN.matches(id)

        /** A random, non-identifying operation id (§4: no user data in file names). */
        fun newOperationId(): String {
            val bytes = ByteArray(16)
            RANDOM.nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }

    /**
     * Resolve an operation directory, proving it stays inside the root.
     *
     * Throws [LocalCutoutException] with [LocalCutoutErrors.CACHE_UNAVAILABLE] for a
     * malformed id or any path that escapes containment.
     */
    fun operationDir(operationId: String): File {
        if (!isValidOperationId(operationId)) {
            throw LocalCutoutException(
                LocalCutoutErrors.CACHE_UNAVAILABLE,
                "Malformed operation id.",
            )
        }
        val dir = File(canonicalRoot, operationId)
        // Canonicalisation resolves `..`, `.` and symlinks; only then is the
        // containment check meaningful.
        val resolved = dir.canonicalFile
        if (!isContained(resolved)) {
            throw LocalCutoutException(
                LocalCutoutErrors.CACHE_UNAVAILABLE,
                "Operation directory escapes the cache root.",
            )
        }
        return resolved
    }

    /** True when [candidate] is the root itself or lives strictly beneath it. */
    fun isContained(candidate: File): Boolean {
        val target = candidate.canonicalFile.path
        val base = canonicalRoot.path
        if (target == base) return true
        return target.startsWith(base + File.separator)
    }

    /** Create (or reuse) an operation directory. */
    fun createOperationDir(operationId: String): File {
        val dir = operationDir(operationId)
        if (!dir.isDirectory && !dir.mkdirs()) {
            throw LocalCutoutException(
                LocalCutoutErrors.CACHE_UNAVAILABLE,
                "Could not create the operation directory.",
            )
        }
        return dir
    }

    fun maskFile(operationId: String): File = File(operationDir(operationId), MASK_FILE_NAME)

    fun cutoutFile(operationId: String): File = File(operationDir(operationId), CUTOUT_FILE_NAME)

    /**
     * Delete one operation's directory. Idempotent — an unknown or already-removed
     * id is a success. A malformed id is a silent no-op returning false rather than
     * an error: cleanup runs on teardown paths where throwing helps nobody.
     */
    fun delete(operationId: String): Boolean {
        val dir = try {
            operationDir(operationId)
        } catch (_: LocalCutoutException) {
            return false
        }
        return deleteRecursively(dir)
    }

    /**
     * Remove operation directories last modified before `nowMs - maxAgeMs` — the
     * recovery sweep for anything a crash or force-kill orphaned. Only immediate
     * children of the root are considered, and each is containment-checked, so this
     * can never walk out of the cache root. Returns how many were removed.
     */
    fun sweepStale(maxAgeMs: Long, nowMs: Long = System.currentTimeMillis()): Int {
        val children = canonicalRoot.listFiles() ?: return 0
        val cutoff = nowMs - maxAgeMs
        var removed = 0
        for (child in children) {
            if (child.lastModified() >= cutoff) continue
            if (!isContained(child)) continue // a symlink out of the root: leave it
            if (deleteRecursively(child)) removed++
        }
        return removed
    }

    /** Remove everything under the root (engine detach / hard reset). */
    fun clear(): Int {
        val children = canonicalRoot.listFiles() ?: return 0
        var removed = 0
        for (child in children) {
            if (isContained(child) && deleteRecursively(child)) removed++
        }
        return removed
    }

    /**
     * Depth-first delete that refuses to follow anything out of the root. Returns
     * true when the target is gone (including when it never existed).
     */
    private fun deleteRecursively(target: File): Boolean {
        if (!target.exists()) return true
        if (!isContained(target)) return false
        if (target.isDirectory) {
            target.listFiles()?.forEach { deleteRecursively(it) }
        }
        return target.delete() || !target.exists()
    }
}
