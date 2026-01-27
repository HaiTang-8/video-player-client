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
        private const val TAG = "MultiThreadDownloader"
        private const val MIN_CHUNK_SIZE = 1024 * 1024L // 1MB
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
        onProgress: (DownloadProgress) -> Unit
    ) {
        val cancelFlag = AtomicBoolean(false)
        val pauseFlag = AtomicBoolean(false)
        cancelFlags[taskId] = cancelFlag
        pauseFlags[taskId] = pauseFlag

        val job = CoroutineScope(Dispatchers.IO).launch {
            try {
                download(taskId, url, savePath, headers, cancelFlag, pauseFlag, onProgress)
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

        Log.d(TAG, "File size: $fileSize, threads: $threadCount")

        val file = File(savePath)
        file.parentFile?.mkdirs()

        // Calculate chunks - ensure chunk count equals thread count for 115 links
        val chunkCount = threadCount
        val chunkSize = (fileSize + chunkCount - 1) / chunkCount
        val chunks = mutableListOf<LongRange>()

        var offset = 0L
        while (offset < fileSize) {
            val end = minOf(offset + chunkSize - 1, fileSize - 1)
            chunks.add(offset..end)
            offset = end + 1
        }

        Log.d(TAG, "Created ${chunks.size} chunks")

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

            // Start all chunks simultaneously (like aria2)
            val chunkJobs = chunks.mapIndexed { index, range ->
                CoroutineScope(Dispatchers.IO).async {
                    activeThreads.incrementAndGet()
                    try {
                        downloadChunk(
                            url = url,
                            headers = effectiveHeaders,
                            range = range,
                            file = file,
                            cancelFlag = cancelFlag,
                            pauseFlag = pauseFlag,
                            onBytesDownloaded = { bytes ->
                                downloadedBytes.addAndGet(bytes)
                            }
                        )
                        Log.d(TAG, "Chunk $index completed")
                        true
                    } catch (e: Exception) {
                        Log.e(TAG, "Chunk $index failed", e)
                        false
                    } finally {
                        activeThreads.decrementAndGet()
                    }
                }
            }

            // Wait for all chunks
            val results = chunkJobs.awaitAll()
            progressJob.cancel()

            if (cancelFlag.get()) {
                onProgress(DownloadProgress(taskId, downloadedBytes.get(), fileSize, 0.0, 0, "cancelled"))
                return
            }

            if (results.all { it }) {
                onProgress(DownloadProgress(taskId, fileSize, fileSize, 0.0, 0, "completed"))
            } else {
                onProgress(DownloadProgress(taskId, downloadedBytes.get(), fileSize, 0.0, 0, "failed", "Some chunks failed"))
            }
        } finally {
            progressJob.cancel()
        }
    }

    private suspend fun downloadChunk(
        url: String,
        headers: Map<String, String>,
        range: LongRange,
        file: File,
        cancelFlag: AtomicBoolean,
        pauseFlag: AtomicBoolean,
        onBytesDownloaded: (Long) -> Unit
    ) {
        val requestBuilder = Request.Builder()
            .url(url)
            .header("Range", "bytes=${range.first}-${range.last}")

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
                raf.seek(range.first)

                body.byteStream().use { input ->
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        if (cancelFlag.get()) break

                        while (pauseFlag.get() && !cancelFlag.get()) {
                            delay(100)
                        }

                        if (cancelFlag.get()) break

                        raf.write(buffer, 0, bytesRead)
                        onBytesDownloaded(bytesRead.toLong())
                    }
                }
            }
        }
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
