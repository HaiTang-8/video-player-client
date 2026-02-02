package com.mediaserver.media_player

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.StatFs
import android.util.Log
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.Collections

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "media_player/downloader"
        private const val EVENT_CHANNEL = "media_player/downloader/progress"
        private const val STORAGE_CHANNEL = "media_player/storage"
        private const val ORIENTATION_CHANNEL = "media_player/orientation"
    }

    private var downloadService: DownloadService? = null
    private var serviceBound = false
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingServiceCallbacks: MutableList<(DownloadService?) -> Unit> =
        Collections.synchronizedList(mutableListOf())
    private var serviceStartInProgress = false
    private var serviceStartTimeoutRunnable: Runnable? = null

    private fun flushPendingServiceCallbacks(service: DownloadService?) {
        val callbacks = synchronized(pendingServiceCallbacks) {
            val snapshot = pendingServiceCallbacks.toList()
            pendingServiceCallbacks.clear()
            snapshot
        }
        callbacks.forEach { it(service) }
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Log.d(TAG, "Service connected")
            val binder = service as? DownloadService.DownloadBinder
            if (binder == null) {
                Log.e(TAG, "Unexpected binder type or null binder for DownloadService")
                downloadService = null
                serviceBound = false
                serviceStartInProgress = false
                flushPendingServiceCallbacks(null)
                return
            }

            downloadService = binder.getService()
            serviceBound = true
            serviceStartInProgress = false

            serviceStartTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
            serviceStartTimeoutRunnable = null

            downloadService?.setProgressCallback { progress ->
                runOnUiThread {
                    eventSink?.success(mapOf(
                        "taskId" to progress.taskId,
                        "downloadedBytes" to progress.downloadedBytes,
                        "totalBytes" to progress.totalBytes,
                        "speed" to progress.speed,
                        "activeThreads" to progress.activeThreads,
                        "status" to progress.status,
                        "error" to progress.error
                    ))
                }
            }

            flushPendingServiceCallbacks(downloadService)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "Service disconnected")
            downloadService = null
            serviceBound = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Storage channel (mirrors iOS implementation).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableSpace" -> {
                    try {
                        val stat = StatFs(filesDir.absolutePath)
                        result.success(stat.availableBytes)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Orientation channel (for notch-side detection in landscape).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ORIENTATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNotchSide" -> {
                    result.success(getNotchSide())
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> {
                    result.success(true)
                }
                "startDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    val url = call.argument<String>("url")!!
                    val savePath = call.argument<String>("savePath")!!
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val displayName = call.argument<String>("displayName")

                    ensureServiceStarted(onReady = { service ->
                        service.startDownload(taskId, url, savePath, headers, displayName)
                        result.success(taskId)
                    }, onError = { message ->
                        result.error("SERVICE_UNAVAILABLE", message, null)
                    })
                }
                "pauseDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    ensureServiceStarted(onReady = { service ->
                        service.pauseDownload(taskId)
                        result.success(null)
                    }, onError = { message ->
                        result.error("SERVICE_UNAVAILABLE", message, null)
                    })
                }
                "resumeDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    ensureServiceStarted(onReady = { service ->
                        service.resumeDownload(taskId)
                        result.success(null)
                    }, onError = { message ->
                        result.error("SERVICE_UNAVAILABLE", message, null)
                    })
                }
                "cancelDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    ensureServiceStarted(onReady = { service ->
                        service.cancelDownload(taskId)
                        result.success(null)
                    }, onError = { message ->
                        result.error("SERVICE_UNAVAILABLE", message, null)
                    })
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    // 根据当前 DisplayCutout 的位置判断刘海在左/右侧。
    //
    // 为什么不直接用 Flutter 的 viewPadding？
    // - 部分机型/系统在横屏下可能给出左右对称的 inset（或左右都非 0），仅靠 inset 大小无法判断刘海方向；
    // - 播放列表面板固定在屏幕右侧，我们需要准确知道刘海是否在右侧，来决定是否给右侧留安全距离。
    private fun getNotchSide(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return "unknown"
        }

        val decorView: View = window?.decorView ?: return "unknown"
        val insets = decorView.rootWindowInsets ?: return "unknown"
        val cutout = insets.displayCutout ?: return "none"

        val rects = cutout.boundingRects
        if (rects.isNullOrEmpty()) return "none"

        // 只在横屏时才有“左/右侧”的意义；竖屏时直接返回 unknown，让 Flutter 侧用兜底逻辑处理。
        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        if (width <= 0 || height <= 0 || width < height) {
            return "unknown"
        }

        val leftInset = cutout.safeInsetLeft
        val rightInset = cutout.safeInsetRight
        if (rightInset > leftInset) return "right"
        if (leftInset > rightInset) return "left"
        if (leftInset == 0 && rightInset == 0) return "none"

        // inset 相等时（系统可能为了对称），用 cutout 的实际位置兜底判断。
        val rect = rects.maxByOrNull { r -> r.width() * r.height() } ?: rects[0]
        val centerX = (rect.left + rect.right) / 2.0
        return if (centerX >= width / 2.0) "right" else "left"
    }

    private fun ensureServiceStarted(onReady: (DownloadService) -> Unit, onError: (String) -> Unit) {
        val existing = downloadService
        if (serviceBound && existing != null) {
            onReady(existing)
            return
        }

        // Queue callbacks until we are actually bound.
        pendingServiceCallbacks.add { service ->
            if (service != null) {
                onReady(service)
            } else {
                onError("DownloadService is not available")
            }
        }

        if (serviceStartInProgress) return
        serviceStartInProgress = true

        val intent = Intent(this, DownloadService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start DownloadService", e)
            serviceStartInProgress = false
            flushPendingServiceCallbacks(null)
            return
        }

        val bound = bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        if (!bound) {
            Log.e(TAG, "bindService returned false for DownloadService")
            serviceStartInProgress = false
            flushPendingServiceCallbacks(null)
            return
        }

        // Time out instead of calling onReady blindly after a fixed delay.
        serviceStartTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        val weakSelf = WeakReference(this)
        val timeout = Runnable {
            val self = weakSelf.get() ?: return@Runnable
            if (!self.serviceBound || self.downloadService == null) {
                Log.e(TAG, "Timed out waiting for DownloadService to bind")
                self.serviceStartInProgress = false
                self.serviceStartTimeoutRunnable = null
                self.flushPendingServiceCallbacks(null)
            }
        }
        serviceStartTimeoutRunnable = timeout
        mainHandler.postDelayed(timeout, 5000)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (serviceBound) {
            downloadService?.setProgressCallback(null)
            unbindService(serviceConnection)
            serviceBound = false
        }
        serviceStartTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        serviceStartTimeoutRunnable = null
        flushPendingServiceCallbacks(null)
    }
}
