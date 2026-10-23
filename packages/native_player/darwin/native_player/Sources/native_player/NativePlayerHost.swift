import Foundation

/// Pigeon 宿主接口的实现：按 playerId 管理播放器实例并转发调用
@MainActor
final class NativePlayerHost: @preconcurrency NativePlayerHostApi {
  private let factory: PlayerBackendFactory
  private let events: NativePlayerEventsApiProtocol
  private let assetResolver: (String) -> URL?
  private var subtitleFonts: [URL] = []
  private var nextId: Int64 = 1
  private var players: [Int64: PlayerBackend] = [:]

  init(
    factory: PlayerBackendFactory, events: NativePlayerEventsApiProtocol,
    assetResolver: @escaping (String) -> URL?
  ) {
    self.factory = factory
    self.events = events
    self.assetResolver = assetResolver
  }

  func backend(for playerId: Int64) -> PlayerBackend? { players[playerId] }

  func capabilities() throws -> NativeCapabilities { factory.capabilities }

  func configureSubtitleFonts(assetKeys: [String]) throws {
    subtitleFonts = assetKeys.compactMap(assetResolver)
  }

  func create() throws -> Int64 {
    let id = nextId
    nextId += 1
    do {
      players[id] = try factory.make(PlayerEventSink(playerId: id, api: events), subtitleFonts)
    } catch {
      throw PigeonError(code: "create_failed", message: "创建播放器失败: \(error)", details: nil)
    }
    return id
  }

  func open(
    playerId: Int64, source: NativeSource, autoPlay: Bool,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let player = players[playerId] else { return completion(.failure(Self.unknown(playerId))) }
    player.open(source, autoPlay: autoPlay, completion: completion)
  }

  func play(playerId: Int64) throws { try player(playerId).play() }
  func pause(playerId: Int64) throws { try player(playerId).pause() }
  func playOrPause(playerId: Int64) throws { try player(playerId).playOrPause() }

  func seek(playerId: Int64, positionMs: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let player = players[playerId] else { return completion(.failure(Self.unknown(playerId))) }
    player.seek(toMs: positionMs, completion: completion)
  }

  func setRate(playerId: Int64, rate: Double) throws { try player(playerId).setRate(rate) }
  func setVolume(playerId: Int64, volume: Double) throws { try player(playerId).setVolume(volume) }

  func selectAudioTrack(playerId: Int64, trackId: String) throws {
    try player(playerId).selectAudioTrack(id: trackId)
  }

  func selectSubtitleTrack(playerId: Int64, trackId: String?) throws {
    try player(playerId).selectSubtitleTrack(id: trackId)
  }

  func addExternalSubtitle(
    playerId: Int64, text: String, title: String, formatHint: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let player = players[playerId] else { return completion(.failure(Self.unknown(playerId))) }
    player.addExternalSubtitle(text: text, title: title, formatHint: formatHint, completion: completion)
  }

  func setVideoFit(playerId: Int64, fit: NativeVideoFit) throws { try player(playerId).setVideoFit(fit) }

  func setSubtitleStyle(playerId: Int64, style: NativeSubtitleStyle) throws {
    try player(playerId).setSubtitleStyle(style)
  }

  func setSubtitleDelay(playerId: Int64, delayMs: Int64) throws {
    try player(playerId).setSubtitleDelay(ms: delayMs)
  }

  func diagnostics(playerId: Int64) throws -> NativeDiagnostics { try player(playerId).diagnostics() }

  func dispose(playerId: Int64) throws {
    players.removeValue(forKey: playerId)?.dispose()
  }

  private func player(_ playerId: Int64) throws -> PlayerBackend {
    guard let player = players[playerId] else { throw Self.unknown(playerId) }
    return player
  }

  private static func unknown(_ playerId: Int64) -> PigeonError {
    PigeonError(code: "unknown_player", message: "播放器实例不存在: \(playerId)", details: nil)
  }
}
