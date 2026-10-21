import AVFoundation
import AetherEngine
import Combine
import Foundation

extension PlayerBackendFactory {
  /// 视频播放倍速上限 2.0（AetherEngine `maxSupportedRate`），音量上限 100%
  static let aether = PlayerBackendFactory(
    capabilities: NativeCapabilities(dolbyVisionColor: true, maxVolume: 1, maxRate: 2),
    make: { events, fonts in try AetherPlayerBackend(events: events, subtitleFonts: fonts) }
  )
}

/// 基于 AetherEngine 的播放器：FFmpeg 解封装后转给 AVPlayer，由系统还原杜比视界 / HDR
@MainActor
final class AetherPlayerBackend: PlayerBackend {
  private let engine: AetherEngine
  private let container: PassthroughView = .blackBackground()
  private let playerView: AetherPlayerView
  private let subtitles: SubtitleOverlayView
  private let events: PlayerEventSink
  private var subscriptions: Set<AnyCancellable> = []
  private var subtitleFiles: [URL] = []
  /// 打开期间的错误由 open 的回调返回，不再重复发事件
  private var opening = false

  var renderView: PlatformView { container }

  init(events: PlayerEventSink, subtitleFonts: [URL]) throws {
    self.events = events
    subtitles = SubtitleOverlayView(fontFiles: subtitleFonts)
    engine = try AetherEngine()
    playerView = AetherPlayerView(frame: .zero)
    engine.bind(view: playerView)
    container.embedFilling(playerView)
    container.embedFilling(subtitles)
    bindEngine()
  }

  func open(_ source: NativeSource, autoPlay: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let url = source.isLocalFile ? URL(fileURLWithPath: source.url) : URL(string: source.url) else {
      completion(.failure(PigeonError(code: "invalid_url", message: "无效的播放地址: \(source.url)", details: nil)))
      return
    }
    var options = LoadOptions()
    options.httpHeaders = source.httpHeaders
    options.autoplay = autoPlay
    // ASS 由 libass 渲染，需要原始事件行
    options.preserveASSMarkup = true
    opening = true
    Task { @MainActor in
      defer { self.opening = false }
      do {
        _ = try await self.engine.load(url: url, options: options)
        completion(.success(()))
      } catch {
        let message = self.engine.errorInfo?.message ?? error.localizedDescription
        completion(.failure(PigeonError(code: "open_failed", message: message, details: nil)))
      }
    }
  }

  func play() { engine.play() }

  func pause() { engine.pause() }

  func playOrPause() { engine.togglePlayPause() }

  func seek(toMs positionMs: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    Task { @MainActor in
      await self.engine.seek(to: Double(positionMs) / 1000)
      completion(.success(()))
    }
  }

  func setRate(_ rate: Double) {
    engine.setRate(Float(rate))
    let applied = min(rate, Double(engine.maxSupportedRate))
    subtitles.rate = applied
    events.rate(applied)
  }

  func setVolume(_ volume: Double) {
    engine.volume = Float(min(max(volume, 0), 1))
    events.volume(Double(engine.volume))
  }

  func selectAudioTrack(id: String) {
    guard let index = Int(id) else { return }
    engine.selectAudioTrack(index: index)
  }

  func selectSubtitleTrack(id: String?) {
    guard let id, let index = Int(id) else {
      engine.clearSubtitle()
      return
    }
    engine.selectSubtitleTrack(index: index)
  }

  func addExternalSubtitle(
    text: String, title: String, formatHint: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "native_player_subtitles", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("\(UUID().uuidString).\(formatHint ?? "srt")")
      try text.write(to: file, atomically: true, encoding: .utf8)
      subtitleFiles.append(file)
      let track = engine.addExternalSubtitleTrack(
        ExternalSubtitleTrack(url: file, name: title, formatHint: formatHint))
      engine.selectSubtitleTrack(index: track.id)
      completion(.success(()))
    } catch {
      completion(.failure(PigeonError(code: "subtitle_failed", message: "\(error)", details: nil)))
    }
  }

  func setVideoFit(_ fit: NativeVideoFit) {
    engine.videoGravity = fit == .cover ? .resizeAspectFill : .resizeAspect
    subtitles.fill = fit == .cover
  }

  func diagnostics() -> [String: String] {
    var info: [String: String] = [:]
    if let codec = engine.sourceVideoCodecName { info["视频编码"] = codec }
    if engine.sourceVideoWidth > 0 {
      info["分辨率"] = "\(engine.sourceVideoWidth)x\(engine.sourceVideoHeight)"
    }
    if let fps = engine.sourceVideoFrameRate { info["帧率"] = String(format: "%.2f fps", fps) }
    if engine.sourceVideoBitrate > 0 { info["视频码率"] = "\(engine.sourceVideoBitrate / 1000) kbps" }
    if let decoder = engine.activeVideoDecoder { info["视频解码"] = decoder }
    if let decoder = engine.activeAudioDecoder { info["音频解码"] = decoder }
    info["输出格式"] = Self.label(engine.videoFormat)
    if engine.dolbyVisionConversion == .profile7ToProfile81 { info["杜比视界转换"] = "Profile 7 → 8.1" }
    info["字幕"] = subtitles.summary
    info["播放路径"] = engine.videoRoute.rawValue
    return info
  }

  func dispose() {
    subscriptions.removeAll()
    subtitles.stop()
    engine.stop()
    engine.unbind(view: playerView)
    for file in subtitleFiles { try? FileManager.default.removeItem(at: file) }
    subtitleFiles.removeAll()
  }

  private func bindEngine() {
    // AetherEngine 在主线程发布状态，这里的回调都在主线程
    engine.clock.$currentTime
      .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
      .sink { [events] in events.position(ms: Self.milliseconds($0)) }
      .store(in: &subscriptions)
    engine.$duration
      .removeDuplicates()
      .sink { [events] in events.duration(ms: Self.milliseconds($0)) }
      .store(in: &subscriptions)
    engine.$state
      .sink { [weak self] state in MainActor.assumeIsolated { self?.handle(state) } }
      .store(in: &subscriptions)
    engine.$isBuffering
      .combineLatest(engine.$state.map { $0 == .loading })
      .map { $0 || $1 }
      .removeDuplicates()
      .sink { [events] in events.buffering($0) }
      .store(in: &subscriptions)
    engine.$audioTracks
      .combineLatest(engine.$subtitleTracks)
      .sink { [events] audio, subtitle in
        events.tracks(audio: audio.map(Self.track), subtitle: subtitle.map(Self.track))
      }
      .store(in: &subscriptions)
    engine.$activeAudioTrackIndex
      .combineLatest(engine.$activeSubtitleTrackIndex)
      .sink { [events] audio, subtitle in
        events.selectedTracks(
          audioId: audio.map(String.init), subtitleId: subtitle.map(String.init),
          subtitleOff: subtitle == nil)
      }
      .store(in: &subscriptions)
    // 动态范围按片源报告；实际输出格式（macOS 上杜比视界可能标为 HDR10）放在媒体信息里
    engine.$sourceVideoFormat
      .combineLatest(engine.$sourceDVProfile)
      .sink { [events] format, profile in
        events.videoInfo(
          NativeVideoInfo(
            dynamicRange: Self.dynamicRange(format),
            dolbyVisionProfile: format == .dolbyVision ? profile.map(Int64.init) : nil))
      }
      .store(in: &subscriptions)
    bindSubtitles()
  }

  private func bindSubtitles() {
    engine.$subtitleCues
      .sink { [weak self] cues in MainActor.assumeIsolated { self?.subtitles.update(cues: cues) } }
      .store(in: &subscriptions)
    engine.clock.$sourceTime
      .sink { [weak self] time in MainActor.assumeIsolated { self?.subtitles.update(time: time) } }
      .store(in: &subscriptions)
    engine.$activeSubtitleTrackIndex
      .combineLatest(engine.$subtitleTracks, engine.$sidecarASSHeader)
      .sink { [weak self] index, tracks, header in
        MainActor.assumeIsolated {
          guard let self else { return }
          let track = index.flatMap { index in tracks.first { $0.id == index } }
          self.subtitles.configure(
            track: track, sidecarHeader: header, fonts: self.engine.fontAttachments)
        }
      }
      .store(in: &subscriptions)
    engine.$sourceVideoWidth
      .combineLatest(engine.$sourceVideoHeight)
      .sink { [weak self] width, height in
        MainActor.assumeIsolated {
          guard let self else { return }
          let aspect = self.engine.sourceVideoPixelAspectRatio
          self.subtitles.setVideoSize(
            CGSize(width: Double(width) * (aspect > 0 ? aspect : 1), height: Double(height)))
        }
      }
      .store(in: &subscriptions)
  }

  private func handle(_ state: PlaybackState) {
    subtitles.playing = state == .playing
    events.playing(state == .playing)
    events.completed(state == .ended)
    guard case .error(let message) = state, !opening else { return }
    events.error(Self.error(message: message, info: engine.errorInfo))
  }

  private static func milliseconds(_ seconds: Double) -> Int64 {
    seconds.isFinite ? Int64((seconds * 1000).rounded()) : 0
  }

  private static func track(_ info: TrackInfo) -> NativeTrack {
    NativeTrack(id: String(info.id), title: info.name.isEmpty ? nil : info.name, language: info.language)
  }

  private static func dynamicRange(_ format: VideoFormat) -> NativeDynamicRange {
    switch format {
    case .sdr: .sdr
    case .hdr10: .hdr10
    case .hdr10Plus: .hdr10Plus
    case .hlg: .hlg
    case .dolbyVision: .dolbyVision
    }
  }

  private static func label(_ format: VideoFormat) -> String {
    switch format {
    case .sdr: "SDR"
    case .hdr10: "HDR10"
    case .hdr10Plus: "HDR10+"
    case .hlg: "HLG"
    case .dolbyVision: "杜比视界"
    }
  }

  private static func error(message: String, info: PlaybackErrorInfo?) -> NativeError {
    let kind = info?.kind
    let status = info?.underlyingCode.map(Int64.init)
    switch kind {
    case .sourceRefused?, .sourceRateLimited?:
      return NativeError(kind: .http, message: message, httpStatus: status, recoverable: false)
    case .sourceOpenFailed?, .sourceCertificateRejected?, .vodSourceFailed?:
      return NativeError(kind: .network, message: message, httpStatus: nil, recoverable: false)
    case .audioSessionFailed?, .audioBridgeProducedNoOutput?:
      return NativeError(kind: .audioOutput, message: message, httpStatus: nil, recoverable: true)
    case .softwarePipelineFailed?, .nativeItemFailed?, .dolbyVisionRequiresHardware?:
      return NativeError(kind: .decoder, message: message, httpStatus: nil, recoverable: false)
    default:
      return NativeError(kind: .unknown, message: message, httpStatus: nil, recoverable: false)
    }
  }
}
