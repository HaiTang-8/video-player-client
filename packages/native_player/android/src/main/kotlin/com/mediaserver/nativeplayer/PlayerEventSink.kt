package com.mediaserver.nativeplayer

/** 某个播放器实例的事件出口；Dart 侧回执无需处理 */
class PlayerEventSink(private val playerId: Long, private val api: NativePlayerEventsApi) {
  fun position(ms: Long) = api.onPosition(playerId, ms) {}

  fun duration(ms: Long) = api.onDuration(playerId, ms) {}

  fun playing(value: Boolean) = api.onPlaying(playerId, value) {}

  fun buffering(value: Boolean) = api.onBuffering(playerId, value) {}

  fun completed(value: Boolean) = api.onCompleted(playerId, value) {}

  fun rate(value: Double) = api.onRate(playerId, value) {}

  fun volume(value: Double) = api.onVolume(playerId, value) {}

  fun tracks(audio: List<NativeTrack>, subtitle: List<NativeTrack>) =
    api.onTracks(playerId, audio, subtitle) {}

  fun selectedTracks(audioId: String?, subtitleId: String?, subtitleOff: Boolean) =
    api.onSelectedTracks(playerId, audioId, subtitleId, subtitleOff) {}

  fun videoInfo(info: NativeVideoInfo) = api.onVideoInfo(playerId, info) {}

  fun error(error: NativeError) = api.onError(playerId, error) {}

  fun firstFrame() = api.onFirstFrame(playerId) {}
}
