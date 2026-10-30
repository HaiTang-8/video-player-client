package com.mediaserver.media_player

import android.util.Log
import kotlinx.coroutines.*
import okhttp3.*
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.max

data class DownloadProgress(
    val taskId: String,
    val downloadedBytes: Long,
    val totalBytes: Long,
    val speed: Double,
    val activeThreads: Int,
    val status: String,
    val error: String? = null
)

class MultiThreadDownloader(
    private val client: OkHttpClient,
    private val threadCount: Int = 8
) {
    companion object {
        // 分片连接数可达 256（参照 quarklite），Dispatchers.IO 默认最多 64 个线程
        @OptIn(ExperimentalCoroutinesApi::class)
        private val chunkDispatcher = Dispatchers.IO.limitedParallelism(256)
        private const val TAG = "MultiThreadDownloader"
        private const val MIN_CHUNK_SIZE = 1024 * 1024L // 1MB

        /** 切出的每一半至少这么大：新请求约有 0.5 秒首字节延迟 */
        private const val MIN_SPLIT = 2L * 1024 * 1024
        private const val DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57"
    }

    private val downloadJobs = ConcurrentHashMap<String, Job>()
    private val cancelFlags = ConcurrentHashMap<String, AtomicBoolean>()
    private val pauseFlags = ConcurrentHashMap<String, AtomicBoolean>()

    fun startDownload(
        taskId: String,
        url: String,
        savePath: String,
        headers: Map<String, String>,
        threads: Int? = null,
        onProgress: (DownloadProgress) -> Unit
    ) {
        val cancelFlag = AtomicBoolean(false)
        val pauseFlag = AtomicBoolean(false)
        cancelFlags[taskId] = cancelFlag
        pauseFlags[taskId] = pauseFlag

        val job = CoroutineScope(Dispatchers.IO).launch {
            try {
                download(taskId, url, savePath, headers, threads ?: threadCount, cancelFlag, pauseFlag, onProgress)
            } catch (e: CancellationException) {
                Log.d(TAG, "Download cancelled: $taskId")
            } catch (e: Exception) {
                Log.e(TAG, "Download error: $taskId", e)
                onProgress(DownloadProgress(taskId, 0, 0, 0.0, 0, "failed", e.message))
            } finally {
                downloadJobs.remove(taskId)
                cancelFlags.remove(taskId)
                pauseFlags.remove(taskId)
            }
        }
        downloadJobs[taskId] = job
    }

    fun pauseDownload(taskId: String) {
        pauseFlags[taskId]?.set(true)
    }

    fun resumeDownload(taskId: String) {
        pauseFlags[taskId]?.set(false)
    }

    fun cancelDownload(taskId: String) {
        cancelFlags[taskId]?.set(true)
        downloadJobs[taskId]?.cancel()
    }

    private suspend fun download(
        taskId: String,
        url: String,
        savePath: String,
        headers: Map<String, String>,
        threads: Int,
        cancelFlag: AtomicBoolean,
        pauseFlag: AtomicBoolean,
        onProgress: (DownloadProgress) -> Unit
    ) {
        val effectiveHeaders = headers.toMutableMap()
        if (!effectiveHeaders.containsKey("User-Agent")) {
            effectiveHeaders["User-Agent"] = DEFAULT_USER_AGENT
        }

        // Get file size
        val fileSize = getFileSize(url, effectiveHeaders)
        if (fileSize == null || fileSize <= 0) {
            onProgress(DownloadProgress(taskId, 0, 0, 0.0, 0, "failed", "Cannot get file size"))
            return
        }

        Log.d(TAG, "File size: $fileSize, threads: $threads")

        val file = File(savePath)
        file.parentFile?.mkdirs()

        // 分段数等于线程数（115 链接为 1）；之后由动态分段把慢的分段切给空闲连接
        val plan = SegmentPlan(fileSize, threads, MIN_SPLIT)

        // Progress tracking
        val downloadedBytes = AtomicLong(0)
        val activeThreads = java.util.concurrent.atomic.AtomicInteger(0)
        var lastUpdateTime = System.currentTimeMillis()
        var lastBytes = 0L
        var smoothedSpeed = 0.0

        // Progress reporter
        val progressJob = CoroutineScope(Dispatchers.IO).launch {
            while (isActive && !cancelFlag.get()) {
                delay(500)
                val now = System.currentTimeMillis()
                val elapsed = now - lastUpdateTime
                if (elapsed > 0) {
                    val currentBytes = downloadedBytes.get()
                    val bytesDiff = currentBytes - lastBytes
                    val instantSpeed = bytesDiff * 1000.0 / elapsed
                    smoothedSpeed = if (smoothedSpeed == 0.0) instantSpeed else 0.3 * instantSpeed + 0.7 * smoothedSpeed
                    lastUpdateTime = now
                    lastBytes = currentBytes

                    onProgress(DownloadProgress(
                        taskId = taskId,
                        downloadedBytes = currentBytes,
                        totalBytes = fileSize,
                        speed = smoothedSpeed,
                        activeThreads = activeThreads.get(),
                        status = if (pauseFlag.get()) "paused" else "downloading"
                    ))
                }
            }
        }

        try {
            // Pre-allocate file
            RandomAccessFile(file, "rw").use { raf ->
                raf.setLength(fileSize)
            }

            // 每个连接循环领取分段，领不到（全部完成或剩余太小不值得再切）时退出
            val workers = (1..threads).map {
                CoroutineScope(chunkDispatcher).async {
                    activeThreads.incrementAndGet()
                    try {
                        while (!cancelFlag.get()) {
                            val segment = plan.claim() ?: break
                            var error = false
                            try {
                                downloadSegment(url, effectiveHeaders, plan, segment, file, cancelFlag, pauseFlag) { bytes ->
                                    downloadedBytes.addAndGet(bytes)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Segment failed at ${segment.pos}", e)
                                error = true
                            } finally {
                                plan.release(segment, error)
                            }
                        }
                    } finally {
                        activeThreads.decrementAndGet()
                    }
                }
            }
            workers.awaitAll()
            progressJob.cancel()
            Log.d(TAG, "Segments split ${plan.splits} times")

            if (cancelFlag.get()) {
                onProgress(DownloadProgress(taskId, downloadedBytes.get(), fileSize, 0.0, 0, "cancelled"))
                return
            }

            if (plan.isComplete()) {
                onProgress(DownloadProgress(taskId, fileSize, fileSize, 0.0, 0, "completed"))
            } else {
                onProgress(DownloadProgress(taskId, downloadedBytes.get(), fileSize, 0.0, 0, "failed", "Some segments failed"))
            }
        } finally {
            progressJob.cancel()
        }
    }

    private suspend fun downloadSegment(
        url: String,
        headers: Map<String, String>,
        plan: SegmentPlan,
        segment: SegmentPlan.Segment,
        file: File,
        cancelFlag: AtomicBoolean,
        pauseFlag: AtomicBoolean,
        onBytesDownloaded: (Long) -> Unit
    ) {
        val (from, to) = plan.window(segment)
        if (from >= to) return
        val requestBuilder = Request.Builder()
            .url(url)
            .header("Range", "bytes=$from-${to - 1}")

        headers.forEach { (key, value) ->
            requestBuilder.header(key, value)
        }

        client.newCall(requestBuilder.build()).execute().use { response ->
            // Range downloads must return 206; a 200 response would corrupt the preallocated file.
            if (response.code != 206) {
                throw Exception("HTTP ${response.code}: ${response.message}")
            }

            val body = response.body ?: throw Exception("Empty response body")
            val buffer = ByteArray(8192)

            RandomAccessFile(file, "rw").use { raf ->
                body.byteStream().use { input ->
                    var bytesRead: Int
                    reading@ while (input.read(buffer).also { bytesRead = it } != -1) {
                        if (cancelFlag.get()) return

                        while (pauseFlag.get() && !cancelFlag.get()) {
                            delay(100)
                        }

                        if (cancelFlag.get()) return

                        var written = 0
                        while (written < bytesRead) {
                            val slice = plan.reserve(segment, bytesRead - written)
                            // 分段被切短后写到新终点即停，后面的数据由领走后一半的连接负责
                            if (slice.length == 0) break@reading
                            try {
                                raf.seek(slice.offset)
                                raf.write(buffer, written, slice.length)
                            } catch (e: java.io.IOException) {
                                plan.fail()
                                throw e
                            }
                            written += slice.length
                            onBytesDownloaded(slice.length.toLong())
                        }
                    }
                }
            }
        }
        val (pos, end) = plan.window(segment)
        if (pos < end && !cancelFlag.get()) throw java.io.IOException("Segment ended early")
    }

    private fun getFileSize(url: String, headers: Map<String, String>): Long? {
        // Try Range request first (works for 115)
        try {
            val requestBuilder = Request.Builder()
                .url(url)
                .header("Range", "bytes=0-0")

            headers.forEach { (key, value) ->
                requestBuilder.header(key, value)
            }

            val response = client.newCall(requestBuilder.build()).execute()
            val contentRange = response.header("Content-Range")
            response.close()

            if (contentRange != null) {
                val match = Regex("/(\\d+)").find(contentRange)
                if (match != null) {
                    return match.groupValues[1].toLongOrNull()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Range request failed", e)
        }

        // Fallback to HEAD request
        try {
            val requestBuilder = Request.Builder()
                .url(url)
                .head()

            headers.forEach { (key, value) ->
                requestBuilder.header(key, value)
            }

            val response = client.newCall(requestBuilder.build()).execute()
            val contentLength = response.header("Content-Length")
            response.close()

            return contentLength?.toLongOrNull()
        } catch (e: Exception) {
            Log.e(TAG, "HEAD request failed", e)
        }

        return null
    }
}
