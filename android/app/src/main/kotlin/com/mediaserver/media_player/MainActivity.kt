package com.mediaserver.media_player

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "media_player/downloader"
        private const val EVENT_CHANNEL = "media_player/downloader/progress"
    }

    private var downloadService: DownloadService? = null
    private var serviceBound = false
    private var eventSink: EventChannel.EventSink? = null

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Log.d(TAG, "Service connected")
            val binder = service as DownloadService.DownloadBinder
            downloadService = binder.getService()
            serviceBound = true

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
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "Service disconnected")
            downloadService = null
            serviceBound = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

                    ensureServiceStarted {
                        downloadService?.startDownload(taskId, url, savePath, headers, displayName)
                        result.success(taskId)
                    }
                }
                "pauseDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    downloadService?.pauseDownload(taskId)
                    result.success(null)
                }
                "resumeDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    downloadService?.resumeDownload(taskId)
                    result.success(null)
                }
                "cancelDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    downloadService?.cancelDownload(taskId)
                    result.success(null)
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

    private fun ensureServiceStarted(onReady: () -> Unit) {
        if (serviceBound && downloadService != null) {
            onReady()
            return
        }

        val intent = Intent(this, DownloadService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)

        // Wait for service to connect
        android.os.Handler(mainLooper).postDelayed({
            onReady()
        }, 100)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (serviceBound) {
            downloadService?.setProgressCallback(null)
            unbindService(serviceConnection)
            serviceBound = false
        }
    }
}
