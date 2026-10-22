package com.mediaserver.nativeplayer

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.DefaultExtractorsFactory
import com.mediaserver.nativeplayer.dovi.DoviFrameStore
import com.mediaserver.nativeplayer.dovi.DoviGlRenderer
import com.mediaserver.nativeplayer.dovi.DoviSpike
import java.io.File
import java.util.Locale
import java.util.UUID

/** 基于 Media3 ExoPlayer 的播放器：系统解码器负责杜比视界 / HDR，画面交给 [NativeVideoView] 的 SurfaceView */
@OptIn(UnstableApi::class)
class Media3PlayerBackend(private val context: Context, private val events: PlayerEventSink) :
  Player.Listener {
  private val player =
    ExoPlayer.Builder(
        context,
        DefaultRenderersFactory(context)
          .setEnableDecoderFallback(true)
          .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
          .apply { if (DoviSpike.enabled) setMediaCodecSelector(DoviSpike.hevcForDolbyVision) },
      )
      .build()
  private val handler = Handler(Looper.getMainLooper())
  private val doviStore: DoviFrameStore? = if (DoviSpike.enabled) DoviFrameStore() else null
  private val dovi: DoviGlRenderer? =
    doviStore?.let { store ->
      player.setVideoFrameMetadataListener { presentationUs, releaseNs, _, _ ->
        store.onFrameReleased(presentationUs, releaseNs)
      }
      DoviGlRenderer(store).also { player.setVideoSurface(it.inputSurface) }
    }
  private val positionTicker =
    object : Runnable {
      override fun run() {
        events.position(player.currentPosition)
        handler.postDelayed(this, POSITION_INTERVAL_MS)
      }
    }
  private val retryPrepare = Runnable { player.prepare() }
  private var mediaSourceFactory: DefaultMediaSourceFactory? = null
  private var view: NativeVideoView? = null
  private var fit = NativeVideoFit.CONTAIN
  private var aspectRatio = 0f
  private var playing = false
  private var lastDurationMs = C.TIME_UNSET
  private var videoDecoder: String? = null
  private var audioDecoder: String? = null
  private var dynamicRange = NativeDynamicRange.UNKNOWN
  private val subtitleFiles = mutableListOf<File>()
  private var pendingSubtitleId: String? = null
  /** 已经请求过换内核，同一次打开不再重复上报 */
  private var fallbackReported = false
  private var networkRetries = 0
  private var openGeneration = 0
  /** 码流里发现了杜比视界 RPU（封装没有声明时 Media3 不会把它识别为杜比视界） */
  private var rpuDetected = false

  init {
    // 来电或其他应用播放时让出音频焦点并暂停；拔出耳机时暂停，避免外放
    player.setAudioAttributes(
      AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
        .build(),
      true,
    )
    player.setHandleAudioBecomingNoisy(true)
    player.addListener(this)
    player.addAnalyticsListener(
      object : AnalyticsListener {
        override fun onVideoDecoderInitialized(
          eventTime: AnalyticsListener.EventTime,
          decoderName: String,
          initializedTimestampMs: Long,
          initializationDurationMs: Long,
        ) {
          videoDecoder = decoderName
        }

        override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime, droppedFrames: Int, elapsedMs: Long) {
          Log.i(DoviSpike.TAG, "decoder dropped $droppedFrames frames in ${elapsedMs}ms")
        }

        override fun onAudioDecoderInitialized(
          eventTime: AnalyticsListener.EventTime,
          decoderName: String,
          initializedTimestampMs: Long,
          initializationDurationMs: Long,
        ) {
          audioDecoder = decoderName
        }
      }
    )
  }

  /** 准备好就返回；之后的失败（含需要换内核的情况）通过错误事件上报 */
  fun open(source: NativeSource, autoPlay: Boolean) {
    handler.removeCallbacks(retryPrepare)
    fallbackReported = false
    networkRetries = 0
    rpuDetected = false
    val generation = ++openGeneration
    pendingSubtitleId = null
    videoDecoder = null
    audioDecoder = null
    lastDurationMs = C.TIME_UNSET
    clearSubtitleFiles()
    val http =
      DefaultHttpDataSource.Factory()
        .setAllowCrossProtocolRedirects(true)
        .setDefaultRequestProperties(source.httpHeaders)
    source.httpHeaders.entries
      .firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }
      ?.let { http.setUserAgent(it.value) }
    val extractors =
      DolbyVisionProbeExtractorsFactory(
        DefaultExtractorsFactory(),
        { handler.post { if (generation == openGeneration) onDolbyVisionRpu() } },
        doviStore?.let { it::onSampleRpu },
      )
    val factory = DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http), extractors)
    mediaSourceFactory = factory
    val uri = if (source.isLocalFile) Uri.fromFile(File(source.url)) else Uri.parse(source.url)
    player.setMediaSource(factory.createMediaSource(MediaItem.fromUri(uri)))
    player.playWhenReady = autoPlay
    player.prepare()
  }

  fun play() {
    if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
    player.play()
  }

  fun pause() = player.pause()

  fun playOrPause() = if (player.playWhenReady) pause() else play()

  fun seek(positionMs: Long) {
    player.seekTo(positionMs)
    events.position(positionMs)
  }

  fun setRate(rate: Double) = player.setPlaybackSpeed(rate.coerceIn(MIN_RATE, MAX_RATE).toFloat())

  fun setVolume(volume: Double) {
    player.volume = volume.coerceIn(0.0, 1.0).toFloat()
  }

  fun selectAudioTrack(id: String) = selectTrack(C.TRACK_TYPE_AUDIO, id)

  fun selectSubtitleTrack(id: String?) = selectTrack(C.TRACK_TYPE_TEXT, id)

  /** 外挂字幕只能随媒体一起加载，所以带上字幕从当前位置重新准备 */
  fun addExternalSubtitle(text: String, title: String, formatHint: String?) {
    val factory = mediaSourceFactory ?: error("没有正在播放的媒体")
    val item = player.currentMediaItem ?: error("没有正在播放的媒体")
    val extension = formatHint?.lowercase(Locale.ROOT) ?: "srt"
    val directory = File(context.cacheDir, "native_player_subtitles").apply { mkdirs() }
    val file = File(directory, "${UUID.randomUUID()}.$extension").apply { writeText(text) }
    subtitleFiles += file
    val id = "external-${subtitleFiles.size}"
    val subtitle =
      MediaItem.SubtitleConfiguration.Builder(Uri.fromFile(file))
        .setMimeType(subtitleMimeType(extension))
        .setLabel(title)
        .setId(id)
        .build()
    val existing = item.localConfiguration?.subtitleConfigurations.orEmpty()
    pendingSubtitleId = id
    player.setMediaSource(
      factory.createMediaSource(item.buildUpon().setSubtitleConfigurations(existing + subtitle).build()),
      player.currentPosition,
    )
    player.prepare()
  }

  fun setVideoFit(fit: NativeVideoFit) {
    this.fit = fit
    view?.setFit(fit)
  }

  fun attach(view: NativeVideoView) {
    this.view?.let { if (dovi == null) player.clearVideoSurfaceView(it.surfaceView) }
    this.view = view
    if (dovi != null) dovi.attach(view.surfaceView) else player.setVideoSurfaceView(view.surfaceView)
    view.setFit(fit)
    if (aspectRatio > 0) view.setAspectRatio(aspectRatio)
    view.subtitleView.setCues(player.currentCues.cues)
    view.setKeepScreenOn(playing)
  }

  fun detach(view: NativeVideoView) {
    if (this.view !== view) return
    if (dovi != null) dovi.detach() else player.clearVideoSurfaceView(view.surfaceView)
    this.view = null
  }

  fun diagnostics(): Map<String, String> {
    val info = linkedMapOf<String, String>()
    player.videoFormat?.let { format ->
      info["视频编码"] = codecName(format)
      if (format.width > 0) info["分辨率"] = "${format.width}x${format.height}"
      if (format.frameRate > 0) info["帧率"] = String.format(Locale.US, "%.2f fps", format.frameRate)
      if (format.bitrate > 0) info["视频码率"] = "${format.bitrate / 1000} kbps"
    }
    videoDecoder?.let { info["视频解码"] = it }
    player.audioFormat?.let { format ->
      info["音频编码"] =
        codecName(format) + if (format.channelCount > 0) " ${format.channelCount}ch" else ""
    }
    audioDecoder?.let { info["音频解码"] = it }
    info["动态范围"] = dynamicRangeLabel()
    info["杜比视界解码器"] = DeviceCapabilities.dolbyVisionDescription
    info["屏幕 HDR"] = DeviceCapabilities.displayHdrDescription(context)
    return info
  }

  fun dispose() {
    handler.removeCallbacks(positionTicker)
    handler.removeCallbacks(retryPrepare)
    view?.let { detach(it) }
    player.removeListener(this)
    player.release()
    dovi?.release()
    clearSubtitleFiles()
  }

  override fun onPlaybackStateChanged(playbackState: Int) {
    if (playbackState == Player.STATE_READY) networkRetries = 0
    events.buffering(playbackState == Player.STATE_BUFFERING)
    events.completed(playbackState == Player.STATE_ENDED)
    reportDuration()
    updatePlaying()
  }

  override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) = updatePlaying()

  override fun onTimelineChanged(timeline: Timeline, reason: Int) = reportDuration()

  override fun onPositionDiscontinuity(
    oldPosition: Player.PositionInfo,
    newPosition: Player.PositionInfo,
    reason: Int,
  ) = events.position(newPosition.positionMs)

  override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) =
    events.rate(playbackParameters.speed.toDouble())

  override fun onVolumeChanged(volume: Float) = events.volume(volume.toDouble())

  override fun onVideoSizeChanged(videoSize: VideoSize) {
    if (videoSize.width <= 0 || videoSize.height <= 0) return
    aspectRatio = videoSize.width * videoSize.pixelWidthHeightRatio / videoSize.height
    view?.setAspectRatio(aspectRatio)
  }

  override fun onCues(cueGroup: CueGroup) {
    view?.subtitleView?.setCues(cueGroup.cues)
  }

  override fun onTracksChanged(tracks: Tracks) {
    val audio = mutableListOf<NativeTrack>()
    val subtitles = mutableListOf<NativeTrack>()
    var selectedAudio: String? = null
    var selectedSubtitle: String? = null
    var pendingTrack: String? = null
    tracks.groups.forEachIndexed { groupIndex, group ->
      for (trackIndex in 0 until group.length) {
        val format = group.getTrackFormat(trackIndex)
        val id = "$groupIndex:$trackIndex"
        val track = NativeTrack(id, format.label, format.language)
        when (group.type) {
          C.TRACK_TYPE_AUDIO -> {
            audio += track
            if (group.isTrackSelected(trackIndex)) selectedAudio = id
          }
          C.TRACK_TYPE_TEXT -> {
            subtitles += track
            if (group.isTrackSelected(trackIndex)) selectedSubtitle = id
            val pending = pendingSubtitleId
            if (pending != null && format.id?.contains(pending) == true) pendingTrack = id
          }
        }
      }
    }
    events.tracks(audio, subtitles)
    events.selectedTracks(selectedAudio, selectedSubtitle, selectedSubtitle == null)
    reportVideoInfo(tracks)
    reportUnplayable(tracks)
    pendingTrack?.let {
      pendingSubtitleId = null
      selectSubtitleTrack(it)
    }
  }

  override fun onPlayerError(error: PlaybackException) {
    Log.w(TAG, "playback error ${error.errorCodeName}", error)
    // 网络抖动时重新准备：Media3 准备阶段的加载重试会清掉 MKV 轨道的 format 并抛 NPE（IO_UNSPECIFIED），
    // 重新准备会换新的解析器
    if (error.errorCode in RETRYABLE_ERRORS && networkRetries < MAX_NETWORK_RETRIES) {
      networkRetries++
      events.buffering(true)
      handler.postDelayed(retryPrepare, networkRetries * RETRY_DELAY_MS)
      return
    }
    events.error(mapError(error))
  }

  private fun selectTrack(type: Int, id: String?) {
    val builder = player.trackSelectionParameters.buildUpon()
    if (id == null) {
      builder.setTrackTypeDisabled(type, true)
    } else {
      val parts = id.split(':').mapNotNull { it.toIntOrNull() }
      if (parts.size != 2) return
      val group = player.currentTracks.groups.getOrNull(parts[0])?.takeIf { it.type == type } ?: return
      builder
        .setTrackTypeDisabled(type, false)
        .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, parts[1]))
    }
    player.trackSelectionParameters = builder.build()
  }

  private fun updatePlaying() {
    val now =
      player.playWhenReady &&
        player.playbackState != Player.STATE_ENDED &&
        player.playbackState != Player.STATE_IDLE
    if (now == playing) return
    playing = now
    events.playing(now)
    view?.setKeepScreenOn(now)
    handler.removeCallbacks(positionTicker)
    if (now) handler.post(positionTicker) else events.position(player.currentPosition)
  }

  private fun reportDuration() {
    val duration = player.duration
    if (duration == C.TIME_UNSET || duration == lastDurationMs) return
    lastDurationMs = duration
    events.duration(duration)
  }

  private fun reportVideoInfo(tracks: Tracks) {
    val group = tracks.groups.firstOrNull { it.type == C.TRACK_TYPE_VIDEO } ?: return
    val index = (0 until group.length).firstOrNull { group.isTrackSelected(it) } ?: 0
    val format = group.getTrackFormat(index)
    val transfer = DolbyVisionProbeExtractorsFactory.colorTransfer(format)
    val profile = dolbyVisionProfile(format) ?: if (rpuDetected) unsignaledProfile(transfer) else null
    dynamicRange =
      when {
        profile != null || format.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION ->
          NativeDynamicRange.DOLBY_VISION
        transfer == C.COLOR_TRANSFER_ST2084 -> NativeDynamicRange.HDR10
        transfer == C.COLOR_TRANSFER_HLG -> NativeDynamicRange.HLG
        else -> NativeDynamicRange.SDR
      }
    events.videoInfo(NativeVideoInfo(dynamicRange, profile?.toLong()))
  }

  /**
   * 封装没有声明的杜比视界由 HEVC 解码器按基础层解码：P8 的基础层是 HDR10 / HLG，可以正常播放；
   * P5 没有兼容的基础层，会显示成偏绿偏紫的画面，所以请求换内核
   */
  private fun onDolbyVisionRpu() {
    if (rpuDetected) return
    rpuDetected = true
    val tracks = player.currentTracks
    reportVideoInfo(tracks)
    val format =
      tracks.groups.firstOrNull { it.type == C.TRACK_TYPE_VIDEO }?.getTrackFormat(0) ?: return
    if (dolbyVisionProfile(format) != null || dovi != null) return
    val transfer = DolbyVisionProbeExtractorsFactory.colorTransfer(format)
    if (unsignaledProfile(transfer) != 5 || fallbackReported) return
    val reason =
      if (DeviceCapabilities.hasDolbyVisionDecoder) {
        "此视频的杜比视界信息没有写在封装里，系统播放器无法正确显示"
      } else {
        "此设备无法解码杜比视界 Profile 5 视频"
      }
    reportFallback(reason)
  }

  private fun reportFallback(reason: String) {
    fallbackReported = true
    player.pause()
    events.error(NativeError(NativeErrorKind.DECODER, reason, null, recoverable = false, fallbackSuggested = true))
  }

  /**
   * 没有解码器的轨道 ExoPlayer 不会报错，只会不播放它（如无杜比视界解码器时 P5 只有声音、DTS 没有声音），
   * 所以有视频或音频轨但一条都放不了时主动请求换内核
   */
  private fun reportUnplayable(tracks: Tracks) {
    if (fallbackReported || dovi != null) return
    val reason =
      listOf(C.TRACK_TYPE_VIDEO to "视频", C.TRACK_TYPE_AUDIO to "音频").firstNotNullOfOrNull {
        (type, label) ->
        val groups = tracks.groups.filter { it.type == type }
        if (groups.isEmpty() || groups.any { it.isSupported(true) }) {
          null
        } else {
          "此设备无法解码${describe(groups.first().getTrackFormat(0), label)}"
        }
      } ?: return
    reportFallback(reason)
  }

  private fun mapError(error: PlaybackException): NativeError {
    val code = error.errorCode
    val name = error.errorCodeName
    return when {
      code == PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS -> {
        val status = (error.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode
        NativeError(NativeErrorKind.HTTP, "服务器返回 HTTP ${status ?: "错误"}", status?.toLong(), false, false)
      }
      code in 2000..2999 -> NativeError(NativeErrorKind.NETWORK, "网络错误（$name）", null, false, false)
      code in 3000..3999 -> NativeError(NativeErrorKind.SOURCE, "无法解析媒体（$name）", null, false, true)
      code in 4000..4999 -> NativeError(NativeErrorKind.DECODER, "解码失败（$name）", null, false, true)
      // 音频输出初始化失败时 ExoPlayer 已经停止，按解码失败处理以便换内核
      code in 5000..5999 -> NativeError(NativeErrorKind.DECODER, "音频输出失败（$name）", null, false, true)
      else -> NativeError(NativeErrorKind.UNKNOWN, error.message ?: name, null, false, false)
    }
  }

  private fun dynamicRangeLabel(): String =
    when (dynamicRange) {
      NativeDynamicRange.UNKNOWN -> "未知"
      NativeDynamicRange.SDR -> "SDR"
      NativeDynamicRange.HDR10 -> "HDR10"
      NativeDynamicRange.HDR10PLUS -> "HDR10+"
      NativeDynamicRange.HLG -> "HLG"
      NativeDynamicRange.DOLBY_VISION -> "杜比视界"
    }

  private fun clearSubtitleFiles() {
    subtitleFiles.forEach { it.delete() }
    subtitleFiles.clear()
  }

  private companion object {
    const val TAG = "NativePlayer"
    const val POSITION_INTERVAL_MS = 250L
    const val MIN_RATE = 0.25
    const val MAX_RATE = 3.0
    const val MAX_NETWORK_RETRIES = 3
    const val RETRY_DELAY_MS = 1000L
    val RETRYABLE_ERRORS =
      setOf(
        PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
        PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
      )
    val DOLBY_VISION_CODECS = setOf("dvhe", "dvh1", "dvav", "dva1", "dav1")

    /** 基础层是 HDR10 / HLG 时按 P8 处理，否则（基础层不可直接显示）是 P5 */
    fun unsignaledProfile(transfer: Int): Int =
      if (transfer == C.COLOR_TRANSFER_ST2084 || transfer == C.COLOR_TRANSFER_HLG) 8 else 5

    /** codecs 形如 dvhe.05.06，第二段是 profile */
    fun dolbyVisionProfile(format: Format): Int? {
      val parts = format.codecs?.split('.') ?: return null
      if (parts.size < 2 || parts[0] !in DOLBY_VISION_CODECS) return null
      return parts[1].toIntOrNull()
    }

    fun describe(format: Format, label: String): String {
      dolbyVisionProfile(format)?.let { return "杜比视界 Profile $it $label" }
      return " ${codecName(format)} $label"
    }

    fun codecName(format: Format): String =
      when (format.sampleMimeType) {
        MimeTypes.VIDEO_DOLBY_VISION -> "Dolby Vision"
        MimeTypes.VIDEO_H265 -> "HEVC"
        MimeTypes.VIDEO_H264 -> "H.264"
        MimeTypes.VIDEO_AV1 -> "AV1"
        MimeTypes.VIDEO_VP9 -> "VP9"
        MimeTypes.AUDIO_AAC -> "AAC"
        MimeTypes.AUDIO_AC3 -> "AC3"
        MimeTypes.AUDIO_E_AC3 -> "E-AC3"
        MimeTypes.AUDIO_E_AC3_JOC -> "E-AC3 Atmos"
        MimeTypes.AUDIO_AC4 -> "AC4"
        MimeTypes.AUDIO_DTS, MimeTypes.AUDIO_DTS_EXPRESS -> "DTS"
        MimeTypes.AUDIO_DTS_HD -> "DTS-HD"
        MimeTypes.AUDIO_TRUEHD -> "TrueHD"
        MimeTypes.AUDIO_FLAC -> "FLAC"
        MimeTypes.AUDIO_OPUS -> "Opus"
        else -> format.sampleMimeType?.substringAfter('/')?.uppercase(Locale.ROOT) ?: "未知"
      } + (format.codecs?.let { " ($it)" } ?: "")

    fun subtitleMimeType(extension: String): String =
      when (extension) {
        "ass", "ssa" -> MimeTypes.TEXT_SSA
        "vtt" -> MimeTypes.TEXT_VTT
        "ttml", "dfxp" -> MimeTypes.APPLICATION_TTML
        else -> MimeTypes.APPLICATION_SUBRIP
      }
  }
}
