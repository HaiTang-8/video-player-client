import AVFoundation
import AetherEngine
import Combine
import Foundation

#if os(iOS)
import UIKit
#endif

extension PlayerBackendFactory {
  /// 视频播放倍速上限 2.0（AetherEngine `maxSupportedRate`），音量上限 100%
  static let aether = PlayerBackendFactory(
    capabilities: NativeCapabilities(
      dolbyVisionColor: true, maxVolume: 1, maxRate: 2, subtitleDelay: true),
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
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var hasSource = false
  private var backgrounded = false
  private var lastPositionMs: Int64 = 0
  /// 后台拆除和重建后引擎时钟会归零（软解路径暂停时一直为 0），恢复播放前沿用进入后台时的位置，
  /// 避免界面显示 0、进度被保存为 0；用户 seek 或打开新片源时放弃
  private var heldPositionMs: Int64?
  private var subtitleFiles: [URL] = []
  /// 打开期间的错误由 open 的回调返回，不再重复发事件
  private var opening = false
  /// 后台重建后引擎会再次报告首帧，每次 open 只上报一次
  private var firstFrameReported = false

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
    #if os(iOS)
    // App 没有后台音频，退到后台即停播
    engine.backgroundPlaybackEnabled = false
    bindLifecycle()
    #endif
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
    hasSource = false
    heldPositionMs = nil
    firstFrameReported = false
    Task { @MainActor in
      defer { self.opening = false }
      do {
        _ = try await self.engine.load(
          url: url,
          startPosition: source.startPositionMs.map { Double($0) / 1000 },
          options: options
        )
        self.hasSource = true
        completion(.success(()))
      } catch {
        let message = self.failureMessage(error.localizedDescription)
        completion(.failure(PigeonError(code: "open_failed", message: message, details: nil)))
      }
    }
  }

  func play() { engine.play() }

  func pause() { engine.pause() }

  func playOrPause() { engine.togglePlayPause() }

  func seek(toMs positionMs: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    heldPositionMs = nil
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

  func setSubtitleStyle(_ style: NativeSubtitleStyle) {
    subtitles.style = style
  }

  /// 字幕层按渲染时刻减去偏移取字幕；提前显示（负值）只对已经送达的 cue 有效
  func setSubtitleDelay(ms: Int64) {
    subtitles.delay = Double(ms) / 1000
  }

  func diagnostics() -> NativeDiagnostics {
    var info: [String: String] = [:]
    if let codec = engine.sourceVideoCodecName { info["视频编码"] = codec }
    if engine.sourceVideoWidth > 0 {
      info["分辨率"] = "\(engine.sourceVideoWidth)x\(engine.sourceVideoHeight)"
    }
    if let fps = engine.sourceVideoFrameRate { info["帧率"] = String(format: "%.2f fps", fps) }
    if engine.sourceVideoBitrate > 0 { info["视频码率"] = "\(engine.sourceVideoBitrate / 1000) kbps" }
    if let decoder = engine.activeAudioDecoder { info["音频解码"] = decoder }
    if engine.dolbyVisionConversion == .profile7ToProfile81 { info["杜比视界转换"] = "Profile 7 → 8.1" }
    info["字幕"] = subtitles.summary
    if let route = Self.label(engine.videoRoute) { info["播放路径"] = route }
    let hasVideo = engine.videoRoute != .none && engine.videoRoute != .audio
    // videoFormat 是屏幕实际呈现的格式：屏幕不支持时 HDR / 杜比视界片源会是 .sdr
    return NativeDiagnostics(
      videoDecoder: engine.activeVideoDecoder,
      outputDynamicRange: hasVideo ? Self.dynamicRange(engine.videoFormat) : nil,
      details: info)
  }

  func dispose() {
    subscriptions.removeAll()
    for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
    lifecycleObservers.removeAll()
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
      .sink { [weak self] time in
        MainActor.assumeIsolated { self?.reportPosition(Self.milliseconds(time)) }
      }
      .store(in: &subscriptions)
    engine.clock.$bufferedPosition
      .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
      .map { Self.milliseconds($0) }
      .removeDuplicates()
      .sink { [events] in events.bufferedPosition(ms: $0) }
      .store(in: &subscriptions)
    engine.$hasFirstFrameReadyForDisplay
      .removeDuplicates()
      .filter { $0 }
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, !self.firstFrameReported else { return }
          self.firstFrameReported = true
          self.events.firstFrame()
        }
      }
      .store(in: &subscriptions)
    engine.$duration
      .removeDuplicates()
      .sink { [events] in events.duration(ms: Self.milliseconds($0)) }
      .store(in: &subscriptions)
    engine.$state
      .sink { [weak self] state in MainActor.assumeIsolated { self?.handle(state) } }
      .store(in: &subscriptions)
    let buffering = engine.$isBuffering
      .combineLatest(engine.$state.map { $0 == .loading || $0 == .seeking })
      .map { $0 || $1 }
    // 先于 buffering 订阅，开始缓冲时 Dart 先收到本次的进度
    buffering
      .combineLatest(engine.$residentRanges, engine.clock.$currentTime)
      .filter { $0.0 }
      .map { Self.bufferingProgress(target: $0.2, resident: $0.1) }
      .removeDuplicates()
      .sink { [events] in events.bufferingProgress($0) }
      .store(in: &subscriptions)
    buffering
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
    // 动态范围按片源报告；实际送显格式（macOS 上杜比视界可能标为 HDR10）见 diagnostics
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
      .sink { [weak self] time in
        MainActor.assumeIsolated {
          guard let self, self.heldPositionMs == nil else { return }
          self.subtitles.update(time: time)
        }
      }
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

  #if os(iOS)
  private func bindLifecycle() {
    let center = NotificationCenter.default
    lifecycleObservers = [
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.backgrounded = true
          self.heldPositionMs = self.lastPositionMs
        }
      },
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.resumeFromBackground() }
      },
    ]
  }

  /// 后台时 AetherEngine 会拆掉视频管线（播放中立即拆，暂停时宽限 15 秒），回到前台由宿主重建；
  /// 重建后保持暂停，位置和音轨、字幕选择由引擎恢复
  private func resumeFromBackground() {
    guard backgrounded else { return }
    backgrounded = false
    guard hasSource, engine.state == .paused, !engine.isSessionReady else { return }
    opening = true
    Task { @MainActor in
      defer { self.opening = false }
      do {
        try await self.engine.reloadAtCurrentPosition { $0.autoplay = false }
      } catch {
        let message = self.failureMessage(error.localizedDescription)
        self.events.error(Self.error(message: message, info: self.engine.errorInfo))
      }
    }
  }
  #endif

  private func reportPosition(_ positionMs: Int64) {
    if heldPositionMs != nil {
      guard !backgrounded, positionMs > 0, engine.state == .playing else { return }
      heldPositionMs = nil
    }
    lastPositionMs = positionMs
    events.position(ms: positionMs)
  }

  private func handle(_ state: PlaybackState) {
    subtitles.playing = state == .playing
    events.playing(state == .playing)
    events.completed(state == .ended)
    guard case .error(let message) = state, !opening else { return }
    events.error(Self.error(message: failureMessage(message), info: engine.errorInfo))
  }

  private static func milliseconds(_ seconds: Double) -> Int64 {
    seconds.isFinite ? Int64((seconds * 1000).rounded()) : 0
  }

  /// AetherEngine 的分段时长：缓存到目标点之后一段，AVPlayer 才能起播
  private static let bufferingGoalSeconds = 4.0
  /// 起点比目标点早超过这个距离的缓存段不是本次生成的（AetherEngine 允许的最长关键帧间隔）
  private static let maxKeyframeLeadSeconds = 30.0

  /// 跳转后缓存从目标点之前的关键帧开始按段生成，进度 = 已生成的部分 ÷ 关键帧到「目标点 + 一段」
  private static func bufferingProgress(target: Double, resident: [ClosedRange<Double>]) -> Double {
    guard let range = resident.filter({ $0.lowerBound <= target })
      .max(by: { $0.lowerBound < $1.lowerBound })
    else { return 0 }
    let anchor = target - range.lowerBound <= maxKeyframeLeadSeconds ? range.lowerBound : target
    guard range.upperBound > anchor else { return 0 }
    let progress = (range.upperBound - anchor) / (target + bufferingGoalSeconds - anchor)
    return (min(progress, 1) * 100).rounded() / 100
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

  private static func label(_ route: VideoRoute) -> String? {
    switch route {
    case .none: nil
    case .remoteBypass: "AVPlayer 直接播放"
    case .loopback: "转封装为 HLS 交给 AVPlayer"
    case .software: "FFmpeg 软解"
    case .audio: "仅音频"
    }
  }

  /// 引擎的错误说明；杜比视界片源解码失败（模拟器、不支持杜比视界的旧 Mac）时换成中文提示
  private func failureMessage(_ fallback: String) -> String {
    let info = engine.errorInfo
    let message = info?.message ?? fallback
    guard let info,
      info.kind == .dolbyVisionRequiresHardware
        || engine.sourceVideoFormat == .dolbyVision && Self.isDecodeFailure(info)
    else { return message }
    let profile = engine.sourceDVProfile.map { " Profile \($0) " } ?? ""
    return "此设备无法解码杜比视界\(profile)视频，请在支持杜比视界的 iPhone、iPad 或 Mac 上播放"
  }

  private static func isDecodeFailure(_ info: PlaybackErrorInfo) -> Bool {
    let decodeCodes = [AVError.Code.decoderNotFound.rawValue, AVError.Code.decodeFailed.rawValue]
    return info.kind == .nativeItemFailed && info.underlyingDomain == AVFoundationErrorDomain
      && info.underlyingCode.map(decodeCodes.contains) == true
  }

  private static func error(message: String, info: PlaybackErrorInfo?) -> NativeError {
    let kind = info?.kind
    let status = info?.underlyingCode.map(Int64.init)
    switch kind {
    case .sourceRefused?, .sourceRateLimited?:
      return NativeError(kind: .http, message: message, httpStatus: status, recoverable: false, fallbackSuggested: false)
    case .sourceOpenFailed?, .sourceCertificateRejected?, .vodSourceFailed?:
      return NativeError(kind: .network, message: message, httpStatus: nil, recoverable: false, fallbackSuggested: false)
    case .audioSessionFailed?, .audioBridgeProducedNoOutput?:
      return NativeError(kind: .audioOutput, message: message, httpStatus: nil, recoverable: true, fallbackSuggested: false)
    case .softwarePipelineFailed?, .nativeItemFailed?, .dolbyVisionRequiresHardware?:
      return NativeError(kind: .decoder, message: message, httpStatus: nil, recoverable: false, fallbackSuggested: false)
    default:
      return NativeError(kind: .unknown, message: message, httpStatus: nil, recoverable: false, fallbackSuggested: false)
    }
  }
}
