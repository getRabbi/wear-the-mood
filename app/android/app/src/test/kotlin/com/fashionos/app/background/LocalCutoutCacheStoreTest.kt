package com.fashionos.app.background

import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Cache containment — the Phase 1 R10b security blocker (local BG §8.2).
 *
 * The threat: Dart asking native to delete something. If cleanup took a PATH,
 * anything that could reach the method channel would have a filesystem delete
 * primitive scoped only by app sandbox permissions. So cleanup takes an operation
 * ID, the ID is pattern-validated, and every resolved path is re-checked for
 * canonical containment inside one app-owned root.
 *
 * These tests exist to prove no path outside that root can be deleted.
 */
class LocalCutoutCacheStoreTest {

    private lateinit var tempRoot: File
    private lateinit var cacheRoot: File
    private lateinit var outsideRoot: File
    private lateinit var store: LocalCutoutCacheStore

    @Before
    fun setUp() {
        tempRoot = File.createTempFile("wtm-cache-test", "").let {
            it.delete()
            it.mkdirs()
            it
        }
        cacheRoot = File(tempRoot, LocalCutoutCacheStore.ROOT_DIR_NAME).apply { mkdirs() }
        outsideRoot = File(tempRoot, "definitely-not-ours").apply { mkdirs() }
        store = LocalCutoutCacheStore(cacheRoot)
    }

    @After
    fun tearDown() {
        tempRoot.deleteRecursively()
    }

    private fun newOperation(): String {
        val id = LocalCutoutCacheStore.newOperationId()
        val dir = store.createOperationDir(id)
        File(dir, LocalCutoutCacheStore.MASK_FILE_NAME).writeBytes(byteArrayOf(1, 2, 3))
        File(dir, LocalCutoutCacheStore.CUTOUT_FILE_NAME).writeBytes(byteArrayOf(4, 5, 6))
        return id
    }

    // ── operation ids ───────────────────────────────────────────────────────

    @Test
    fun `generated ids are random 32-char hex`() {
        val a = LocalCutoutCacheStore.newOperationId()
        val b = LocalCutoutCacheStore.newOperationId()
        assertTrue(LocalCutoutCacheStore.isValidOperationId(a))
        assertEquals(32, a.length)
        assertTrue(a != b) // random, and therefore non-identifying
    }

    @Test
    fun `only well-formed ids are accepted`() {
        val rejected = listOf(
            null,
            "",
            "   ",
            "..",
            "../..",
            "../../databases",
            "abc",
            "ABCDEF0123456789ABCDEF0123456789", // uppercase
            "0123456789abcdef0123456789abcde", // 31 chars
            "0123456789abcdef0123456789abcdef0", // 33 chars
            "0123456789abcdef0123456789abcde/", // separator
            "0123456789abcdef0123456789abcde\\",
            "/etc/passwd",
            "C:\\Windows\\System32",
            "0123456789abcdef0123456789abcd..",
            "0123456789abcdef0123456789abcde\u0000",
        )
        for (id in rejected) {
            assertFalse("should reject: $id", LocalCutoutCacheStore.isValidOperationId(id))
        }
    }

    // ── containment ─────────────────────────────────────────────────────────

    @Test
    fun `a traversal id cannot resolve to a directory`() {
        val e = runCatching { store.operationDir("../definitely-not-ours") }
            .exceptionOrNull() as? LocalCutoutException
        assertEquals(LocalCutoutErrors.CACHE_UNAVAILABLE, e?.code)
    }

    @Test
    fun `an absolute path cannot resolve to a directory`() {
        val e = runCatching { store.operationDir(outsideRoot.absolutePath) }
            .exceptionOrNull() as? LocalCutoutException
        assertEquals(LocalCutoutErrors.CACHE_UNAVAILABLE, e?.code)
    }

    @Test
    fun `containment accepts the root and its descendants only`() {
        assertTrue(store.isContained(cacheRoot))
        assertTrue(store.isContained(File(cacheRoot, "abc/def")))
        assertFalse(store.isContained(outsideRoot))
        assertFalse(store.isContained(tempRoot))
        assertFalse(store.isContained(File(cacheRoot, "../definitely-not-ours")))
    }

    @Test
    fun `a sibling directory with the same prefix is NOT contained`() {
        // "…/wtm-local-cutout-evil" starts with the root string but is a sibling;
        // a naive startsWith without the separator would wrongly accept it.
        val sibling = File(tempRoot, LocalCutoutCacheStore.ROOT_DIR_NAME + "-evil")
            .apply { mkdirs() }
        assertFalse(store.isContained(sibling))
    }

    // ── delete ──────────────────────────────────────────────────────────────

    @Test
    fun `delete removes the operation directory and its files`() {
        val id = newOperation()
        val dir = store.operationDir(id)
        assertTrue(dir.isDirectory)

        assertTrue(store.delete(id))
        assertFalse(dir.exists())
    }

    @Test
    fun `delete is idempotent`() {
        val id = newOperation()
        assertTrue(store.delete(id))
        assertTrue(store.delete(id))
        assertTrue(store.delete(LocalCutoutCacheStore.newOperationId())) // never existed
    }

    @Test
    fun `delete refuses a malformed id and touches nothing`() {
        val victim = File(outsideRoot, "important.txt").apply { writeBytes(byteArrayOf(9)) }

        for (id in listOf("", "..", "../definitely-not-ours", outsideRoot.absolutePath)) {
            assertFalse("should refuse: $id", store.delete(id))
        }
        assertTrue("nothing outside the root may be deleted", victim.exists())
        assertTrue(outsideRoot.exists())
    }

    @Test
    fun `no arbitrary path outside the root can be deleted`() {
        // The property in one assertion: build every hostile string we can think of
        // and prove the outside file survives all of them.
        val victim = File(outsideRoot, "user-data.db").apply { writeBytes(byteArrayOf(1)) }
        val hostile = listOf(
            "../definitely-not-ours/user-data.db",
            "../../definitely-not-ours",
            "..%2F..%2Fdefinitely-not-ours",
            victim.absolutePath,
            "/",
            ".",
            "*",
        )
        for (id in hostile) {
            store.delete(id)
            runCatching { store.operationDir(id) }
        }
        assertTrue(victim.exists())
        assertTrue(cacheRoot.exists())
    }

    // ── stale sweep ─────────────────────────────────────────────────────────

    @Test
    fun `sweep removes stale operations and keeps fresh ones`() {
        val stale = newOperation()
        val fresh = newOperation()
        val now = System.currentTimeMillis()
        store.operationDir(stale).setLastModified(now - 10 * 60 * 60 * 1000)
        store.operationDir(fresh).setLastModified(now)

        val removed = store.sweepStale(maxAgeMs = 6 * 60 * 60 * 1000, nowMs = now)

        assertEquals(1, removed)
        assertFalse(store.operationDir(stale).exists())
        assertTrue(store.operationDir(fresh).exists())
    }

    @Test
    fun `sweep never leaves the root`() {
        val victim = File(outsideRoot, "keepme").apply { writeBytes(byteArrayOf(1)) }
        victim.setLastModified(0) // ancient
        outsideRoot.setLastModified(0)

        store.sweepStale(maxAgeMs = 1, nowMs = System.currentTimeMillis())

        assertTrue(victim.exists())
        assertTrue(outsideRoot.exists())
    }

    @Test
    fun `sweep on an empty or missing root is zero, not an error`() {
        assertEquals(0, store.sweepStale(1, System.currentTimeMillis()))

        val missing = File(tempRoot, "never-created")
        val emptyStore = LocalCutoutCacheStore(missing)
        assertEquals(0, emptyStore.sweepStale(1, System.currentTimeMillis()))
    }

    @Test
    fun `clear empties the root but leaves the root itself`() {
        newOperation()
        newOperation()
        assertEquals(2, store.clear())
        assertTrue(cacheRoot.isDirectory)
        assertEquals(0, cacheRoot.listFiles()?.size ?: -1)
    }

    // ── file placement ──────────────────────────────────────────────────────

    @Test
    fun `mask and cutout files live inside the operation directory`() {
        val id = newOperation()
        val mask = store.maskFile(id)
        val cutout = store.cutoutFile(id)

        assertTrue(store.isContained(mask))
        assertTrue(store.isContained(cutout))
        assertEquals(store.operationDir(id), mask.parentFile)
        assertTrue(mask.isFile && mask.length() > 0)
        assertTrue(cutout.isFile && cutout.length() > 0)
    }

    @Test
    fun `file names carry no user data`() {
        val id = newOperation()
        assertEquals("mask.png", store.maskFile(id).name)
        assertEquals("cutout.png", store.cutoutFile(id).name)
        // The only variable component is the random operation id.
        assertTrue(LocalCutoutCacheStore.isValidOperationId(store.operationDir(id).name))
    }
}
