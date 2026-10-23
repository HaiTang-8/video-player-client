import Foundation

/// 一个原生播放器实例。由具体内核（AetherEngine 等）实现；Pigeon 回调都在主线程，所以整体限定在主线程
@MainActor
protocol PlayerBackend: AnyObject {
  /// 承载画面的视图，由 PlatformView 挂载
  var renderView: PlatformView { get }

  func open(_ source: NativeSource, autoPlay: Bool, completion: @escaping (Result<Void, Error>) -> Void)
  func play()
  func pause()
  func playOrPause()
  func seek(toMs positionMs: Int64, completion: @escaping (Result<Void, Error>) -> Void)
  func setRate(_ rate: Double)
  func setVolume(_ volume: Double)
  func selectAudioTrack(id: String)
  func selectSubtitleTrack(id: String?)
  func addExternalSubtitle(
    text: String, title: String, formatHint: String?,
    completion: @escaping (Result<Void, Error>) -> Void)
  func setVideoFit(_ fit: NativeVideoFit)
  func setSubtitleStyle(_ style: NativeSubtitleStyle)
  func setSubtitleDelay(ms: Int64)
  func diagnostics() -> NativeDiagnostics
  func dispose()
}

/// 内核的能力声明和实例构造
struct PlayerBackendFactory {
  let capabilities: NativeCapabilities
  /// 第二个参数是字幕字体文件，第一个为默认字体
  let make: @MainActor (PlayerEventSink, [URL]) throws -> PlayerBackend

  /// 当前平台尚未接入内核时使用：可以创建实例，但打开媒体会失败
  static let unsupported = PlayerBackendFactory(
    capabilities: NativeCapabilities(
      dolbyVisionColor: false, maxVolume: 1, maxRate: 1, subtitleDelay: false),
    make: { _, _ in UnsupportedPlayerBackend() }
  )
}

@MainActor
final class UnsupportedPlayerBackend: PlayerBackend {
  let renderView: PlatformView = .blackBackground()

  func open(_ source: NativeSource, autoPlay: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(PigeonError(code: "unsupported", message: "当前平台尚未接入原生播放内核", details: nil)))
  }

  func play() {}
  func pause() {}
  func playOrPause() {}

  func seek(toMs positionMs: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.success(()))
  }

  func setRate(_ rate: Double) {}
  func setVolume(_ volume: Double) {}
  func selectAudioTrack(id: String) {}
  func selectSubtitleTrack(id: String?) {}

  func addExternalSubtitle(
    text: String, title: String, formatHint: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func setVideoFit(_ fit: NativeVideoFit) {}
  func setSubtitleStyle(_ style: NativeSubtitleStyle) {}
  func setSubtitleDelay(ms: Int64) {}
  func diagnostics() -> NativeDiagnostics { NativeDiagnostics(details: [:]) }
  func dispose() {}
}
