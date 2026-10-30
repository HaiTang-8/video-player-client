package com.mediaserver.media_player

/**
 * 动态分段：空闲连接先领取没人负责的分段（含失败退回的），没有时把剩余最多的分段从中间切开、领走后一半。
 * 写入前先在锁内预留位置，分段被切短后原连接写到新终点就停，两边不会重叠
 */
class SegmentPlan(
    fileSize: Long,
    count: Int,
    private val minSplit: Long,
    private val maxFailures: Int = 3
) {
    class Segment internal constructor(start: Long, end: Long) {
        /** 下一个待写入的字节 */
        var pos: Long = start
            internal set

        /** 终点（不含） */
        var end: Long = end
            internal set
        internal var owned = false
        internal var failures = 0
        val remaining: Long get() = end - pos
    }

    data class Slice(val offset: Long, val length: Int)

    private val segments = mutableListOf<Segment>()

    var failed = false
        private set

    var splits = 0
        private set

    init {
        val n = maxOf(1, count)
        val size = (fileSize + n - 1) / n
        var offset = 0L
        while (offset < fileSize) {
            val end = minOf(offset + size, fileSize)
            segments.add(Segment(offset, end))
            offset = end
        }
    }

    @Synchronized
    fun claim(): Segment? {
        if (failed) return null
        segments.firstOrNull { !it.owned && it.remaining > 0 }?.let {
            it.owned = true
            return it
        }
        val victim = segments
            .filter { it.owned && it.remaining >= 2 * minSplit }
            .maxByOrNull { it.remaining } ?: return null
        val mid = victim.pos + victim.remaining / 2
        val piece = Segment(mid, victim.end).also { it.owned = true }
        victim.end = mid
        segments.add(piece)
        splits++
        return piece
    }

    /** 请求时的区间（含起点，不含终点） */
    @Synchronized
    fun window(segment: Segment): Pair<Long, Long> = segment.pos to segment.end

    /** 预留最多 [wanted] 字节的写入位置；分段已写满（含被切短）时长度为 0 */
    @Synchronized
    fun reserve(segment: Segment, wanted: Int): Slice {
        val length = minOf(wanted.toLong(), segment.remaining).toInt()
        val slice = Slice(segment.pos, maxOf(length, 0))
        segment.pos += slice.length
        return slice
    }

    /** 连接结束时归还；[error] 且还有剩余时计一次失败，同一分段失败超过上限则整体失败 */
    @Synchronized
    fun release(segment: Segment, error: Boolean) {
        segment.owned = false
        if (error && segment.remaining > 0 && ++segment.failures > maxFailures) failed = true
    }

    @Synchronized
    fun fail() {
        failed = true
    }

    @Synchronized
    fun isComplete(): Boolean = !failed && segments.all { it.remaining <= 0 }
}
