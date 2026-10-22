import Foundation

/// 某个播放器实例的事件出口；Dart 侧回执无需处理
final class PlayerEventSink {
  private let playerId: Int64
  private let api: NativePlayerEventsApiProtocol

  init(playerId: Int64, api: NativePlayerEventsApiProtocol) {
    self.playerId = playerId
    self.api = api
  }

  func position(ms: Int64) { api.onPosition(playerId: playerId, positionMs: ms) { _ in } }
  func duration(ms: Int64) { api.onDuration(playerId: playerId, durationMs: ms) { _ in } }
  func playing(_ value: Bool) { api.onPlaying(playerId: playerId, playing: value) { _ in } }
  func buffering(_ value: Bool) { api.onBuffering(playerId: playerId, buffering: value) { _ in } }
  func completed(_ value: Bool) { api.onCompleted(playerId: playerId, completed: value) { _ in } }
  func firstFrame() { api.onFirstFrame(playerId: playerId) { _ in } }
  func rate(_ value: Double) { api.onRate(playerId: playerId, rate: value) { _ in } }
  func volume(_ value: Double) { api.onVolume(playerId: playerId, volume: value) { _ in } }

  func tracks(audio: [NativeTrack], subtitle: [NativeTrack]) {
    api.onTracks(playerId: playerId, audio: audio, subtitle: subtitle) { _ in }
  }

  func selectedTracks(audioId: String?, subtitleId: String?, subtitleOff: Bool) {
    api.onSelectedTracks(
      playerId: playerId, audioTrackId: audioId, subtitleTrackId: subtitleId,
      subtitleOff: subtitleOff
    ) { _ in }
  }

  func videoInfo(_ info: NativeVideoInfo) { api.onVideoInfo(playerId: playerId, info: info) { _ in } }
  func error(_ error: NativeError) { api.onError(playerId: playerId, error: error) { _ in } }
}
