package com.fashionos.app.background

import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * The two primitives that make callback-time copying safe (local BG §2).
 *
 * Both live here, free of every Android and ML Kit type, so the behaviour that
 * actually protects us is covered by fast JVM tests rather than only by device QA.
 * That distinction is not academic: the bug these exist to prevent shipped past 83
 * green Android tests because the only coverage of the real path was a fake.
 */

/**
 * Copy a float buffer into app-owned memory, independent of the SDK's own cursor.
 *
 * Three properties matter:
 *  * it reads from position 0 to the limit, so it cannot silently depend on a
 *    position the SDK controls — the previous code used `remaining()`, which does;
 *  * it does not disturb the source buffer's position or limit, so ML Kit is free to
 *    keep using it;
 *  * the returned array shares nothing with the source, so later reuse of the
 *    SDK's native memory cannot change what we already read.
 */
internal fun copyFloatBuffer(buffer: FloatBuffer): FloatArray {
    val view = buffer.duplicate()
    view.rewind()
    val out = FloatArray(view.remaining())
    view.get(out)
    return out
}

/**
 * A one-shot result slot: whichever producer settles first wins, later ones are
 * no-ops, and a consumer can wait for it with a bound.
 *
 * ML Kit attaches success, failure and cancellation listeners to the same Task. All
 * three can in principle run, and a double completion would either lose an error or
 * complete an operation twice — so exactly-once is enforced here rather than assumed.
 */
internal class OneShotOutcome {
    private val value = AtomicReference<Any?>(null)
    private val latch = CountDownLatch(1)

    /** True when this call was the one that settled the outcome. */
    fun settle(result: Any): Boolean {
        if (!value.compareAndSet(null, result)) return false
        latch.countDown()
        return true
    }

    /** False on timeout. */
    fun await(timeoutMs: Long): Boolean =
        latch.await(timeoutMs.coerceAtLeast(1L), TimeUnit.MILLISECONDS)

    fun get(): Any? = value.get()

    val isSettled: Boolean get() = value.get() != null
}
