package com.mediaserver.nativeplayer

import android.content.Context
import android.graphics.Typeface
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
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
import com.mediaserver.nativeplayer.dovi.DoviSupport
import io.github.peerless2012.ass.media.AssHandler
import io.github.peerless2012.ass.media.AssHandlerConfig
import io.github.peerless2012.ass.media.factory.AssRenderersFactory
import io.github.peerless2012.ass.media.parser.AssSubtitleParserFactory
import io.github.peerless2012.ass.media.type.AssRenderType
import io.github.peerless2012.ass.media.widget.AssSubtitleView
import java.io.File
import java.util.Locale
import java.util.UUID

/** 基于 Media3 ExoPlayer 的播放器：系统解码器负责杜比视界 / HDR，画面交给 [NativeVideoView] 的 SurfaceView */
@OptIn(UnstableApi::class)
class Media3PlayerBackend(
  private val context: Context,
  private val events: PlayerEventSink,
  private val subtitleTypeface: Typeface?,
) : Player.Listener {
  /** 没有杜比视界解码器但 GPU 能重建时，封装声明的 P5 也交给普通 HEVC 解码器，由 [DoviGlRenderer] 还原颜色 */
  private val reshapeDeclaredProfile5 = DoviSupport.available && !DeviceCapabilities.hasDolbyVisionDecoder
  /** ASS / SSA 由 libass 渲染（特效、卡拉 OK、内嵌字体），画在 SubtitleView 内的叠加层上；其余字幕仍走 Media3 */
  private val ass = AssHandler(AssRenderType.OVERLAY_OPEN_GL, AssHandlerConfig(maxRenderPixels = 1920 * 1080))
  private val subtitleParsers = PgsSubtitleParserFactory(AssSubtitleParserFactory(ass))
  private val player =
    ExoPlayer.Builder(
        context,
        AssRenderersFactory(
          ass,
          DefaultRenderersFactory(context)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            .apply { if (reshapeDeclaredProfile5) setMediaCodecSelector(DoviSupport.hevcForDolbyVision) },
        ),
      )
      .build()
  private val handler = Handler(Looper.getMainLooper())
  /** 当前片源的逐帧 RPU（GPU 能重建时才有） */
  @Volatile private var doviStore: DoviFrameStore? = null
  /** 第一次遇到 P5 时创建，之后复用 */
  private var dovi: DoviGlRenderer? = null
  /** 画面经 [dovi] 重建后送显，而不是由解码器直接输出到 SurfaceView */
  private var reshaping = false
  private val positionTicker =
    object : Runnable {
      override fun run() {
        events.position(player.currentPosition)
        handler.postDelayed(this, POSITION_INTERVAL_MS)
      }
    }
  /** 暂停时也会继续缓冲，所以独立于 [positionTicker] 一直运行，值变化才上报 */
  private val bufferedTicker =
    object : Runnable {
      override fun run() {
        val buffered = player.bufferedPosition
        if (buffered != lastBufferedMs) {
          lastBufferedMs = buffered
          events.bufferedPosition(buffered)
        }
        handler.postDelayed(this, BUFFERED_INTERVAL_MS)
      }
    }
  private val retryPrepare = Runnable { player.prepare() }
  private var mediaSourceFactory: DefaultMediaSourceFactory? = null
  private var view: NativeVideoView? = null
  private var assView: AssSubtitleView? = null
  /** GPU 重建时播放器输出到渲染器的输入 Surface，报告的尺寸无效，libass 改按 SurfaceView 的尺寸排版 */
  private val assSurfaceSize =
    View.OnLayoutChangeListener { surface, _, _, _, _, _, _, _, _ -> if (reshaping) syncAssSurfaceSize(surface) }
  private var fit = NativeVideoFit.CONTAIN
  private var subtitleStyle: NativeSubtitleStyle? = null
  private var aspectRatio = 0f
  private var playing = false
  private var lastDurationMs = C.TIME_UNSET
  private var lastBufferedMs = -1L
  private var videoDecoder: String? = null
  private var audioDecoder: String? = null
  private var dynamicRange = NativeDynamicRange.UNKNOWN
  private val subtitleFiles = mutableListOf<File>()
  private var pendingSubtitleId: String? = null
  /** 已经请求过换内核，同一次打开不再重复上报 */
  private var fallbackReported = false
  /** seek、换渲染目标后 Media3 会再次回调首帧，每次打开只上报一次 */
  private var firstFrameReported = false
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
    ass.init(player)
    ass.renderCallback = { render -> subtitleStyle?.let { render?.setFontScale(it.scale.toFloat()) } }
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
    if (DoviSupport.available) {
      player.setVideoFrameMetadataListener { presentationUs, releaseNs, _, _ ->
        doviStore?.onFrameReleased(presentationUs, releaseNs)
      }
    }
  }

  /** 准备好就返回；之后的失败（含需要换内核的情况）通过错误事件上报 */
  fun open(source: NativeSource, autoPlay: Boolean) {
    handler.removeCallbacks(retryPrepare)
    fallbackReported = false
    firstFrameReported = false
    networkRetries = 0
    rpuDetected = false
    val generation = ++openGeneration
    pendingSubtitleId = null
    videoDecoder = null
    audioDecoder = null
    lastDurationMs = C.TIME_UNSET
    lastBufferedMs = -1L
    handler.removeCallbacks(bufferedTicker)
    handler.post(bufferedTicker)
    clearSubtitleFiles()
    deactivateReshaping()
    val store =
      if (DoviSupport.available) {
        DoviFrameStore(
          onProfile5 = { handler.post { if (generation == openGeneration) activateReshaping() } },
          onUnusable = { reason -> handler.post { if (generation == openGeneration) reportFallback(reason) } },
        )
      } else {
        null
      }
    doviStore = store
    val http =
      DefaultHttpDataSource.Factory()
        .setAllowCrossProtocolRedirects(true)
        .setDefaultRequestProperties(source.httpHeaders)
    source.httpHeaders.entries
      .firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }
      ?.let { http.setUserAgent(it.value) }
    val extractors =
      DolbyVisionProbeExtractorsFactory(
        AssExtractorsFactory(DefaultExtractorsFactory(), subtitleParsers, ass),
        { handler.post { if (generation == openGeneration) onDolbyVisionRpu() } },
        store?.let { it::onSampleRpu },
        reshapeDeclaredProfile5,
      )
    val factory =
      DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http), extractors)
        .setSubtitleParserFactory(subtitleParsers)
    mediaSourceFactory = factory
    val uri = if (source.isLocalFile) Uri.fromFile(File(source.url)) else Uri.parse(source.url)
    player.setMediaSource(
      factory.createMediaSource(MediaItem.fromUri(uri)),
      source.startPositionMs ?: C.TIME_UNSET,
    )
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
    doviStore?.onSeek()
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
    // 同名字幕（偏移后重新加载）替换旧的那条，不重复出现在轨道列表里
    val existing = item.localConfiguration?.subtitleConfigurations.orEmpty().filter { it.label != title }
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

  fun setSubtitleStyle(style: NativeSubtitleStyle) {
    subtitleStyle = style
    view?.setSubtitleStyle(style, subtitleTypeface)
    ass.render?.setFontScale(style.scale.toFloat())
    refreshAssView()
  }

  fun attach(view: NativeVideoView) {
    this.view?.let(::detachSurface)
    this.view = view
    attachSurface(view)
    view.setFit(fit)
    view.setSubtitleStyle(subtitleStyle, subtitleTypeface)
    if (aspectRatio > 0) view.setAspectRatio(aspectRatio)
    view.setCues(player.currentCues.cues)
    removeAssView()
    assView = AssSubtitleView(view.subtitleView.context, ass).also(view.subtitleView::addView)
    view.surfaceView.addOnLayoutChangeListener(assSurfaceSize)
    if (reshaping) syncAssSurfaceSize(view.surfaceView)
    view.setKeepScreenOn(playing)
  }

  fun detach(view: NativeVideoView) {
    if (this.view !== view) return
    detachSurface(view)
    removeAssView()
    view.surfaceView.removeOnLayoutChangeListener(assSurfaceSize)
    this.view = null
  }

  private fun attachSurface(view: NativeVideoView) {
    val renderer = dovi
    if (reshaping && renderer != null) renderer.attach(view.surfaceView) else player.setVideoSurfaceView(view.surfaceView)
  }

  private fun detachSurface(view: NativeVideoView) {
    if (reshaping) dovi?.detach() else player.clearVideoSurfaceView(view.surfaceView)
  }

  private fun removeAssView() {
    assView?.let { (it.parent as? ViewGroup)?.removeView(it) }
    assView = null
  }

  private fun syncAssSurfaceSize(surface: View) {
    if (surface.width > 0 && surface.height > 0) ass.onSurfaceSizeChanged(surface.width, surface.height)
  }

  /** libass 叠加层只在播放推进时重画；暂停时切换字幕或 seek 后手动画一次当前时间 */
  private fun refreshAssView() {
    if (!player.isPlaying) ass.videoTimeCallback?.invoke(ass.videoTime)
  }

  /**
   * 关闭字幕时叠加层被清空，但 libass 仍记着上一帧，重新打开同一条字幕时报告“没有变化”而不重画。
   * 帧尺寸变化会让 libass 重新排版、清掉上一帧
   */
  private fun resetAssFrame() {
    val render = ass.render ?: return
    val size = ass.computeRenderSize(ass.surfaceSize.width, ass.surfaceSize.height)
    if (size.width <= 0 || size.height <= 0) return
    render.setFrameSize(size.width, size.height + 2)
    render.setFrameSize(size.width, size.height)
  }

  /** 发现 P5 后改由 GPU 重建：解码器输出切到渲染器，渲染器接管 SurfaceView */
  private fun activateReshaping() {
    val store = doviStore ?: return
    if (reshaping) return
    val renderer =
      dovi
        ?: runCatching { DoviGlRenderer() }
          .onFailure { Log.e(DoviSupport.TAG, "renderer init failed", it) }
          .getOrNull()
          ?.also { dovi = it }
    if (renderer == null) {
      reportFallback("此设备无法用 GPU 还原杜比视界 Profile 5 的颜色")
      return
    }
    view?.let { player.clearVideoSurfaceView(it.surfaceView) }
    renderer.bind(store)
    reshaping = true
    player.setVideoSurface(renderer.inputSurface)
    view?.let {
      renderer.attach(it.surfaceView)
      syncAssSurfaceSize(it.surfaceView)
    }
    Log.i(DoviSupport.TAG, "Dolby Vision profile 5 is reshaped to HDR10 on the GPU")
  }

  private fun deactivateReshaping() {
    if (!reshaping) return
    reshaping = false
    val renderer = dovi ?: return
    renderer.detach()
    player.clearVideoSurface(renderer.inputSurface)
    view?.let { player.setVideoSurfaceView(it.surfaceView) }
  }

  fun diagnostics(): NativeDiagnostics {
    val info = linkedMapOf<String, String>()
    val video = player.videoFormat
    video?.let { format ->
      info["视频编码"] = codecName(format)
      if (format.width > 0) info["分辨率"] = "${format.width}x${format.height}"
      if (format.frameRate > 0) info["帧率"] = String.format(Locale.US, "%.2f fps", format.frameRate)
      if (format.bitrate > 0) info["视频码率"] = "${format.bitrate / 1000} kbps"
    }
    player.audioFormat?.let { format ->
      info["音频编码"] =
        codecName(format) + if (format.channelCount > 0) " ${format.channelCount}ch" else ""
    }
    audioDecoder?.let { info["音频解码"] = it }
    if (reshaping) {
      info["杜比视界处理"] = "GPU 重建为 HDR10"
      dovi?.hdrMetadataDescription?.let { info["HDR10 元数据"] = it }
    }
    info["杜比视界解码器"] = DeviceCapabilities.dolbyVisionDescription
    info["屏幕 HDR"] = DeviceCapabilities.displayHdrDescription(context)
    return NativeDiagnostics(videoDecoder, video?.let(::outputDynamicRange), info)
  }

  /**
   * 送显信号：GPU 重建为 HDR10；杜比视界片源不是由杜比视界解码器解码时输出的是基础层；
   * 屏幕不支持 HDR 时由系统映射为 SDR
   */
  private fun outputDynamicRange(format: Format): NativeDynamicRange? {
    val signal =
      when {
        reshaping -> NativeDynamicRange.HDR10
        dynamicRange == NativeDynamicRange.DOLBY_VISION &&
          !DeviceCapabilities.isDolbyVisionDecoder(videoDecoder) ->
          when (DolbyVisionProbeExtractorsFactory.colorTransfer(format)) {
            C.COLOR_TRANSFER_ST2084 -> NativeDynamicRange.HDR10
            C.COLOR_TRANSFER_HLG -> NativeDynamicRange.HLG
            else -> NativeDynamicRange.SDR
          }
        else -> dynamicRange
      }
    return when {
      signal == NativeDynamicRange.UNKNOWN -> null
      signal == NativeDynamicRange.SDR || DeviceCapabilities.displaySupportsHdr(context) -> signal
      else -> NativeDynamicRange.SDR
    }
  }

  fun dispose() {
    handler.removeCallbacks(positionTicker)
    handler.removeCallbacks(bufferedTicker)
    handler.removeCallbacks(retryPrepare)
    view?.let { detach(it) }
    player.removeListener(this)
    player.release()
    ass.release()
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

  override fun onRenderedFirstFrame() {
    refreshAssView()
    if (firstFrameReported) return
    firstFrameReported = true
    events.firstFrame()
  }

  override fun onCues(cueGroup: CueGroup) {
    view?.setCues(cueGroup.cues)
  }

  override fun onTracksChanged(tracks: Tracks) {
    resetAssFrame()
    refreshAssView()
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
    // 能用 GPU 重建时由 doviStore 在解析出 P5 后切换，不需要换内核
    if (dolbyVisionProfile(format) != null || doviStore != null) return
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
    if (fallbackReported) return
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

  private fun clearSubtitleFiles() {
    subtitleFiles.forEach { it.delete() }
    subtitleFiles.clear()
  }

  private companion object {
    const val TAG = "NativePlayer"
    const val POSITION_INTERVAL_MS = 250L
    const val BUFFERED_INTERVAL_MS = 500L
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

    /** 基础层是 HDR10 / HLG 时按 P8 处理，否则（基础层不可直接显示）是 P5 */
    fun unsignaledProfile(transfer: Int): Int =
      if (transfer == C.COLOR_TRANSFER_ST2084 || transfer == C.COLOR_TRANSFER_HLG) 8 else 5

    fun dolbyVisionProfile(format: Format): Int? = DolbyVisionProbeExtractorsFactory.dolbyVisionProfile(format)

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
