package com.fashionos.app.background

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The primitives behind callback-time copying (local BG §2).
 *
 * [copyFloatBuffer] is what makes the copy independent of ML Kit's memory, and
 * [OneShotOutcome] is what makes completion exactly-once across the three listeners
 * ML Kit can fire. Both are covered here in pure JVM because the class that uses them
 * cannot be — and because the bug that made them necessary hid behind a fake.
 */
class LocalCutoutAsyncTest {

    private fun direct(values: FloatArray): FloatBuffer =
        ByteBuffer.allocateDirect(values.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(values); rewind() }

    // ── deep copy ────────────────────────────────────────────────────────────

    @Test
    fun `copies the whole buffer from position zero`() {
        val values = floatArrayOf(0.1f, 0.2f, 0.3f, 0.4f)
        assertArrayEquals(values, copyFloatBuffer(direct(values)), 1e-6f)
    }

    @Test
    fun `copies the whole buffer even when the SDK left the position mid-way`() {
        // The old code used `remaining()`, so a non-zero position silently truncated
        // the mask. rewind() makes the copy independent of the SDK's cursor.
        val values = floatArrayOf(0.1f, 0.2f, 0.3f, 0.4f)
        val buffer = direct(values).apply { position(2) }
        assertArrayEquals(values, copyFloatBuffer(buffer), 1e-6f)
    }

    @Test
    fun `does not disturb the source buffer position`() {
        val buffer = direct(floatArrayOf(1f, 2f, 3f)).apply { position(1) }
        copyFloatBuffer(buffer)
        assertEquals("ML Kit must still be able to use its own buffer", 1, buffer.position())
    }

    @Test
    fun `the copy is isolated from later mutation of the source`() {
        // This is the whole point: once copied, ML Kit reusing that native memory
        // cannot change what we already read.
        val buffer = direct(floatArrayOf(0.5f, 0.5f, 0.5f))
        val copy = copyFloatBuffer(buffer)
        buffer.rewind()
        buffer.put(floatArrayOf(Float.NaN, 9e37f, -1f)) // simulate reuse/garbage
        assertArrayEquals(floatArrayOf(0.5f, 0.5f, 0.5f), copy, 1e-6f)
    }

    @Test
    fun `an empty buffer copies to an empty array`() {
        assertEquals(0, copyFloatBuffer(direct(FloatArray(0))).size)
    }

    // ── exactly-once completion ──────────────────────────────────────────────

    @Test
    fun `the first settle wins and later ones are refused`() {
        val outcome = OneShotOutcome()
        assertTrue(outcome.settle("first"))
        assertFalse(outcome.settle("second"))
        assertFalse(outcome.settle(IllegalStateException("late failure")))
        assertEquals("first", outcome.get())
    }

    @Test
    fun `a failure arriving before success is the one kept`() {
        // ML Kit could fire failure then success; the error must not be lost.
        val outcome = OneShotOutcome()
        val boom = IllegalStateException("boom")
        assertTrue(outcome.settle(boom))
        assertFalse(outcome.settle(SegmentationOutput(FloatArray(4), emptyList())))
        assertEquals(boom, outcome.get())
    }

    @Test
    fun `exactly one of many concurrent settles wins`() {
        val outcome = OneShotOutcome()
        val pool = Executors.newFixedThreadPool(8)
        val winners = AtomicInteger()
        try {
            val tasks = (0 until 64).map { i ->
                pool.submit { if (outcome.settle("v$i")) winners.incrementAndGet() }
            }
            tasks.forEach { it.get(10, TimeUnit.SECONDS) }
        } finally {
            pool.shutdownNow()
        }
        assertEquals(1, winners.get())
        assertTrue(outcome.isSettled)
    }

    @Test
    fun `await returns immediately once settled`() {
        val outcome = OneShotOutcome()
        outcome.settle("done")
        assertTrue(outcome.await(60_000))
    }

    @Test
    fun `await times out when nothing settles, and reports nothing`() {
        val outcome = OneShotOutcome()
        val started = System.nanoTime()
        assertFalse(outcome.await(60))
        assertTrue(System.nanoTime() - started >= 50_000_000L)
        assertNull(outcome.get())
        assertFalse(outcome.isSettled)
    }

    @Test
    fun `a settle from another thread releases a waiter`() {
        val outcome = OneShotOutcome()
        val pool = Executors.newSingleThreadExecutor()
        try {
            pool.submit {
                Thread.sleep(30)
                outcome.settle("late")
            }
            assertTrue(outcome.await(10_000))
            assertEquals("late", outcome.get())
        } finally {
            pool.shutdownNow()
        }
    }

    @Test
    fun `a non-positive timeout still waits briefly rather than dividing by zero`() {
        val outcome = OneShotOutcome()
        assertFalse(outcome.await(0))
        assertFalse(outcome.await(-5))
    }
}
