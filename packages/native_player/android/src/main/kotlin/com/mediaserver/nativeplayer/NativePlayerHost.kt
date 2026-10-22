package com.mediaserver.nativeplayer

import android.content.Context
import com.mediaserver.nativeplayer.dovi.DoviSupport

/** Pigeon HostApi 的实现：按 playerId 管理播放器实例；Pigeon 回调都在主线程 */
class NativePlayerHost(private val context: Context, private val events: NativePlayerEventsApi) :
  NativePlayerHostApi {
  private var nextId = 1L
  private val players = mutableMapOf<Long, Media3PlayerBackend>()

  fun backend(playerId: Long): Media3PlayerBackend? = players[playerId]

  /** 有杜比视界解码器或 GPU 能重建时 P5 颜色正确；都没有时会回退到 mpv */
  override fun capabilities() =
    NativeCapabilities(
      dolbyVisionColor = DeviceCapabilities.hasDolbyVisionDecoder || DoviSupport.available,
      maxVolume = 1.0,
      maxRate = 3.0,
    )

  /** Android 的字幕由 Media3 的 SubtitleView 用系统字体绘制 */
  override fun configureSubtitleFonts(assetKeys: List<String>) {}

  override fun create(): Long {
    val id = nextId++
    players[id] = Media3PlayerBackend(context, PlayerEventSink(id, events))
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
