package com.fashionos.app.background

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The one-operation-at-a-time guard (local BG §8.2).
 *
 * Segmentation holds a decoded bitmap, a float confidence buffer and two pixel
 * arrays simultaneously — tens of MB for a 1600px photo. Letting two run at once
 * on a mid-range device is how this feature would OOM, so admission control is
 * tested rather than assumed.
 */
class SingleOperationGuardTest {

    @Test
    fun `the first caller wins the slot`() {
        val guard = SingleOperationGuard()
        assertTrue(guard.begin("a"))
        assertTrue(guard.isBusy)
        assertEquals("a", guard.activeOperationId)
    }

    @Test
    fun `a second caller is refused while the first holds it`() {
        val guard = SingleOperationGuard()
        guard.begin("a")
        assertFalse(guard.begin("b"))
    }

    @Test
    fun `the slot is reusable after release`() {
        val guard = SingleOperationGuard()
        guard.begin("a")
        guard.end("a")
        assertFalse(guard.isBusy)
        assertNull(guard.activeOperationId)
        assertTrue(guard.begin("b"))
    }

    @Test
    fun `a stale release cannot free someone else's slot`() {
        val guard = SingleOperationGuard()
        guard.begin("a")
        guard.end("stale-id")
        assertTrue(guard.isBusy)
        assertEquals("a", guard.activeOperationId)
    }

    @Test
    fun `only one of many racing threads is admitted`() {
        val guard = SingleOperationGuard()
        val threads = 16
        val ready = CountDownLatch(threads)
        val go = CountDownLatch(1)
        val admitted = AtomicInteger(0)

        val workers = (0 until threads).map { i ->
            Thread {
                ready.countDown()
                go.await(5, TimeUnit.SECONDS)
                if (guard.begin("op-$i")) admitted.incrementAndGet()
            }
        }
        workers.forEach { it.start() }
        assertTrue(ready.await(5, TimeUnit.SECONDS))
        go.countDown()
        workers.forEach { it.join(5_000) }

        assertEquals(1, admitted.get())
    }

    @Test
    fun `cancel flags the active operation`() {
        val guard = SingleOperationGuard()
        guard.begin("a")
        guard.cancel()
        assertTrue(guard.isCancelled("a"))
    }

    @Test
    fun `cancelling a different id leaves the active run alone`() {
        val guard = SingleOperationGuard()
        guard.begin("a")
        guard.cancel("some-other-op")
        assertFalse(guard.isCancelled("a"))
    }

    @Test
    fun `cancel with no active operation is a no-op`() {
        val guard = SingleOperationGuard()
        guard.cancel()
        guard.cancel("anything")
        assertFalse(guard.isCancelled("anything"))
    }

    @Test
    fun `a checkpoint throws CANCELLED once flagged`() {
        val guard = SingleOperationGuard()
        guard.begin("a")
        guard.throwIfCancelled("a") // not cancelled yet: must not throw
        guard.cancel("a")

        val e = runCatching { guard.throwIfCancelled("a") }
            .exceptionOrNull() as? LocalCutoutException
        assertEquals(LocalCutoutErrors.CANCELLED, e?.code)
    }

    @Test
    fun `a new operation clears a previous cancellation`() {
        // Otherwise one cancelled run would poison every subsequent add.
        val guard = SingleOperationGuard()
        guard.begin("a")
        guard.cancel("a")
        guard.end("a")

        assertTrue(guard.begin("b"))
        assertFalse(guard.isCancelled("b"))
        guard.throwIfCancelled("b")
    }
}
