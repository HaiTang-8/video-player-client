package com.mediaserver.media_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

class DownloadService : Service() {
    companion object {
        private const val TAG = "DownloadService"
        private const val CHANNEL_ID = "download_channel"
        private const val NOTIFICATION_ID = 1001

        @Volatile
        private var instance: DownloadService? = null

        fun getInstance(): DownloadService? = instance
    }

    private val binder = DownloadBinder()
    private lateinit var downloader: MultiThreadDownloader
    private lateinit var notificationManager: NotificationManager

    private val activeTasks = ConcurrentHashMap<String, TaskInfo>()
    private var progressCallback: ((DownloadProgress) -> Unit)? = null
    private var notificationUpdateJob: Job? = null

    data class TaskInfo(
        val taskId: String,
        val displayName: String,
        var downloadedBytes: Long = 0,
        var totalBytes: Long = 0,
        var speed: Double = 0.0,
        var status: String = "downloading"
    )

    inner class DownloadBinder : Binder() {
        fun getService(): DownloadService = this@DownloadService
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "DownloadService created")

        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(2, TimeUnit.HOURS)
            .writeTimeout(2, TimeUnit.HOURS)
            .build()

        downloader = MultiThreadDownloader(client, 8)
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand")
        startForeground(NOTIFICATION_ID, createNotification())
        startNotificationUpdater()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        notificationUpdateJob?.cancel()
        Log.d(TAG, "DownloadService destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "下载服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "显示下载进度"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val taskCount = activeTasks.size
        if (taskCount == 0) {
            return NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("下载服务运行中")
                .setContentText("等待下载任务...")
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setSilent(true)
                .build()
        }

        val totalDownloaded = activeTasks.values.sumOf { it.downloadedBytes }
        val totalSize = activeTasks.values.sumOf { it.totalBytes }
        val totalSpeed = activeTasks.values.sumOf { it.speed }
        val progress = if (totalSize > 0) ((totalDownloaded * 100) / totalSize).toInt() else 0

        val title = if (taskCount == 1) {
            activeTasks.values.first().displayName
        } else {
            "正在下载 $taskCount 个文件"
        }

        val speedText = formatSpeed(totalSpeed)
        val sizeText = "${formatBytes(totalDownloaded)} / ${formatBytes(totalSize)}"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("$sizeText · $speedText")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(100, progress, false)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun startNotificationUpdater() {
        notificationUpdateJob?.cancel()
        notificationUpdateJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                delay(1000)
                if (activeTasks.isNotEmpty()) {
                    notificationManager.notify(NOTIFICATION_ID, createNotification())
                }
            }
        }
    }

    fun setProgressCallback(callback: ((DownloadProgress) -> Unit)?) {
        progressCallback = callback
    }

    fun startDownload(
        taskId: String,
        url: String,
        savePath: String,
        headers: Map<String, String>,
        displayName: String?
    ) {
        val name = displayName ?: taskId
        activeTasks[taskId] = TaskInfo(taskId, name)

        notificationManager.notify(NOTIFICATION_ID, createNotification())

        downloader.startDownload(taskId, url, savePath, headers) { progress ->
            activeTasks[taskId]?.apply {
                downloadedBytes = progress.downloadedBytes
                totalBytes = progress.totalBytes
                speed = progress.speed
                status = progress.status
            }

            progressCallback?.invoke(progress)

            if (progress.status in listOf("completed", "failed", "cancelled")) {
                activeTasks.remove(taskId)
                checkAndStopService()
            }
        }
    }

    fun pauseDownload(taskId: String) {
        downloader.pauseDownload(taskId)
        activeTasks[taskId]?.status = "paused"
    }

    fun resumeDownload(taskId: String) {
        downloader.resumeDownload(taskId)
        activeTasks[taskId]?.status = "downloading"
    }

    fun cancelDownload(taskId: String) {
        downloader.cancelDownload(taskId)
        activeTasks.remove(taskId)
        checkAndStopService()
    }

    private fun checkAndStopService() {
        if (activeTasks.isEmpty()) {
            Log.d(TAG, "No active tasks, stopping service")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    fun hasActiveTasks(): Boolean = activeTasks.isNotEmpty()

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes >= 1024 * 1024 * 1024 -> String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024))
            bytes >= 1024 * 1024 -> String.format("%.2f MB", bytes / (1024.0 * 1024))
            bytes >= 1024 -> String.format("%.2f KB", bytes / 1024.0)
            else -> "$bytes B"
        }
    }

    private fun formatSpeed(bytesPerSecond: Double): String {
        return when {
            bytesPerSecond >= 1024 * 1024 -> String.format("%.2f MB/s", bytesPerSecond / (1024 * 1024))
            bytesPerSecond >= 1024 -> String.format("%.2f KB/s", bytesPerSecond / 1024)
            else -> String.format("%.0f B/s", bytesPerSecond)
        }
    }
}
