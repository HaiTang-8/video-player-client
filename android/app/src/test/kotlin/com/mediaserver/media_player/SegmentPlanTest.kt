package com.mediaserver.media_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SegmentPlanTest {
    private val mib = 1024L * 1024

    @Test
    fun idleConnectionTakesTheBackHalfOfTheLargestSegment() {
        val plan = SegmentPlan(fileSize = 16 * mib, count = 2, minSplit = 2 * mib)
        val a = plan.claim()!!
        val b = plan.claim()!!
        assertEquals(0L to 8 * mib, plan.window(a))
        // b 下完，a 只写了 2 MiB：空闲连接领走 a 剩余 6 MiB 的后一半
        plan.reserve(b, (8 * mib).toInt())
        plan.release(b, error = false)
        plan.reserve(a, (2 * mib).toInt())
        val piece = plan.claim()!!
        assertEquals(5 * mib to 8 * mib, plan.window(piece))
        assertEquals(2 * mib to 5 * mib, plan.window(a))
        assertEquals(1, plan.splits)
    }

    @Test
    fun shrunkSegmentStopsAtTheNewEndWithoutOverlap() {
        val plan = SegmentPlan(fileSize = 8 * mib, count = 1, minSplit = 1 * mib)
        val a = plan.claim()!!
        assertEquals(SegmentPlan.Slice(0, 1024), plan.reserve(a, 1024))
        val piece = plan.claim()!!
        val (mid, _) = plan.window(piece)
        // a 只能写到 mid，之后预留长度为 0
        var written = 1024L
        while (true) {
            val slice = plan.reserve(a, 1 shl 20)
            if (slice.length == 0) break
            assertEquals(written, slice.offset)
            written += slice.length
        }
        assertEquals(mid, written)
        plan.reserve(piece, (8 * mib).toInt())
        plan.release(a, error = false)
        plan.release(piece, error = false)
        assertTrue(plan.isComplete())
    }

    @Test
    fun smallRemaindersAreNotSplit() {
        val plan = SegmentPlan(fileSize = 3 * mib, count = 1, minSplit = 2 * mib)
        plan.claim()!!
        assertNull(plan.claim())
    }

    @Test
    fun failedSegmentIsRetriedThenFailsTheTask() {
        val plan = SegmentPlan(fileSize = 4 * mib, count = 1, minSplit = 4 * mib, maxFailures = 2)
        repeat(2) {
            val s = plan.claim()!!
            plan.release(s, error = true)
            assertFalse(plan.failed)
        }
        val s = plan.claim()!!
        plan.release(s, error = true)
        assertTrue(plan.failed)
        assertNull(plan.claim())
        assertFalse(plan.isComplete())
    }
}
