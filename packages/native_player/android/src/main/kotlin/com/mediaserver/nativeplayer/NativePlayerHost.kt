package com.mediaserver.nativeplayer

import android.content.Context
import android.graphics.Typeface
import android.util.Log
import com.mediaserver.nativeplayer.dovi.DoviSupport

/** Pigeon HostApi 的实现：按 playerId 管理播放器实例；Pigeon 回调都在主线程 */
class NativePlayerHost(
  private val context: Context,
  private val events: NativePlayerEventsApi,
  private val assetPath: (String) -> String,
) : NativePlayerHostApi {
  private var nextId = 1L
  private var subtitleTypeface: Typeface? = null
  private val players = mutableMapOf<Long, Media3PlayerBackend>()

  fun backend(playerId: Long): Media3PlayerBackend? = players[playerId]

  /** 有杜比视界解码器或 GPU 能重建时 P5 颜色正确；都没有时会回退到 mpv */
  override fun capabilities() =
    NativeCapabilities(
      dolbyVisionColor = DeviceCapabilities.hasDolbyVisionDecoder || DoviSupport.available,
      maxVolume = 1.0,
      maxRate = 3.0,
      subtitleDelay = false,
    )

  /** 只用于 Media3 SubtitleView 绘制的文本字幕；ASS 由 libass 用系统字体渲染 */
  override fun configureSubtitleFonts(assetKeys: List<String>) {
    if (subtitleTypeface != null) return
    val key = assetKeys.firstOrNull() ?: return
    subtitleTypeface =
      runCatching { Typeface.createFromAsset(context.assets, assetPath(key)) }
        .onFailure { Log.w("NativePlayerHost", "字幕字体加载失败: $key", it) }
        .getOrNull()
  }

  override fun create(): Long {
    val id = nextId++
    players[id] = Media3PlayerBackend(context, PlayerEventSink(id, events), subtitleTypeface)
    return id
  }

  override fun open(
    playerId: Long,
    source: NativeSource,
    autoPlay: Boolean,
    callback: (Result<Unit>) -> Unit,
  ) = complete(callback) { backendOrThrow(playerId).open(source, autoPlay) }

  override fun play(playerId: Long) = backendOrThrow(playerId).play()

  override fun pause(playerId: Long) = backendOrThrow(playerId).pause()

  override fun playOrPause(playerId: Long) = backendOrThrow(playerId).playOrPause()

  override fun seek(playerId: Long, positionMs: Long, callback: (Result<Unit>) -> Unit) =
    complete(callback) { backendOrThrow(playerId).seek(positionMs) }

  override fun setRate(playerId: Long, rate: Double) = backendOrThrow(playerId).setRate(rate)

  override fun setVolume(playerId: Long, volume: Double) = backendOrThrow(playerId).setVolume(volume)

  override fun selectAudioTrack(playerId: Long, trackId: String) =
    backendOrThrow(playerId).selectAudioTrack(trackId)

  override fun selectSubtitleTrack(playerId: Long, trackId: String?) =
    backendOrThrow(playerId).selectSubtitleTrack(trackId)

  override fun addExternalSubtitle(
    playerId: Long,
    text: String,
    title: String,
    formatHint: String?,
    callback: (Result<Unit>) -> Unit,
  ) = complete(callback) { backendOrThrow(playerId).addExternalSubtitle(text, title, formatHint) }

  override fun setVideoFit(playerId: Long, fit: NativeVideoFit) = backendOrThrow(playerId).setVideoFit(fit)

  override fun setSubtitleStyle(playerId: Long, style: NativeSubtitleStyle) =
    backendOrThrow(playerId).setSubtitleStyle(style)

  /** Media3 没有字幕偏移接口；外挂字幕由 Dart 平移时间轴后重新加载 */
  override fun setSubtitleDelay(playerId: Long, delayMs: Long) {}

  override fun diagnostics(playerId: Long): NativeDiagnostics = backendOrThrow(playerId).diagnostics()

  override fun dispose(playerId: Long) {
    players.remove(playerId)?.dispose()
  }

  fun disposeAll() {
    players.values.forEach { it.dispose() }
    players.clear()
  }

  private fun backendOrThrow(playerId: Long): Media3PlayerBackend =
    players[playerId] ?: throw FlutterError("no_player", "播放器不存在: $playerId", null)

  private fun complete(callback: (Result<Unit>) -> Unit, action: () -> Unit) {
    callback(runCatching(action))
  }
}
