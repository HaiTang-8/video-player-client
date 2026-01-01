package com.mediaserver.media_player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val CHANNEL = "media_player/downloader"
    private val EVENT_CHANNEL = "media_player/downloader/progress"

    private lateinit var downloader: MultiThreadDownloader
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(2, TimeUnit.HOURS)
            .writeTimeout(2, TimeUnit.HOURS)
            .build()

        downloader = MultiThreadDownloader(client, 8)

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
                    val threadCount = call.argument<Int>("threadCount") ?: 8

                    downloader.startDownload(taskId, url, savePath, headers) { progress ->
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
                    result.success(taskId)
                }
                "pauseDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    downloader.pauseDownload(taskId)
                    result.success(null)
                }
                "resumeDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    downloader.resumeDownload(taskId)
                    result.success(null)
                }
                "cancelDownload" -> {
                    val taskId = call.argument<String>("taskId")!!
                    downloader.cancelDownload(taskId)
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
}
