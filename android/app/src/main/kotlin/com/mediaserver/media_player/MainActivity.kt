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
