import AetherEngine
import Libass
import QuartzCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 叠在视频上方的字幕层：文字字幕统一交给 libass，PGS 等位图字幕按画布坐标贴图
@MainActor
final class SubtitleOverlayView: PlatformView {
  private let contentLayer = CALayer()
  private let renderer: LibassRenderer?
  private var trackKey: String?
  private var isASSTrack = false
  private var trackLabel = "关闭"
  private var lastCues: [SubtitleCue] = []
  private var fedKeys: Set<String> = []
  private var bitmapCues: [(id: Int, start: Double, end: Double, image: SubtitleImage)] = []
  private var shownBitmapIDs: [Int] = []
  private var timer: Timer?
  private var needsRender = true
  private var pixels: [UInt8] = []
  private var videoSize: CGSize = .zero
  private var anchorTime: Double = 0
  private var anchorStamp: CFTimeInterval = 0

  var playing = false { didSet { reanchor() } }
  var rate: Double = 1 { didSet { reanchor() } }
  var fill = false { didSet { setNeedsRender() } }

  /// 正值表示字幕延后显示（秒）
  var delay: Double = 0 { didSet { setNeedsRender() } }

  /// 字号对所有字幕生效；颜色、底框、位置只作用于非 ASS 的文本字幕
  var style: NativeSubtitleStyle? {
    didSet {
      renderer?.setFontScale(style?.scale ?? 1)
      if trackKey != nil && !isASSTrack { resetTrack(header: nil) }
      setNeedsRender()
    }
  }

  /// 媒体信息面板中的“字幕”一行
  var summary: String { trackLabel }

  /// [fontFiles] 第一个作为默认字体
  init(fontFiles: [URL]) {
    renderer = LibassRenderer(fontFiles: fontFiles)
    super.init(frame: .zero)
    #if os(iOS)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    layer.addSublayer(contentLayer)
    #elseif os(macOS)
    wantsLayer = true
    layer?.addSublayer(contentLayer)
    #endif
    contentLayer.contentsGravity = .resize
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  #if os(iOS)
  override func layoutSubviews() {
    super.layoutSubviews()
    setNeedsRender()
  }
  #elseif os(macOS)
  override func layout() {
    super.layout()
    setNeedsRender()
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  #endif

  /// 选中的字幕轨变化，或外挂 ASS 的文件头到达时调用；同一轨同一文件头不重复重建
  func configure(track: TrackInfo?, sidecarHeader: String?, fonts: [FontAttachment]) {
    guard let track else {
      trackKey = nil
      trackLabel = "关闭"
      stopTimer()
      clear()
      return
    }
    let codec = track.codec.lowercased()
    isASSTrack = codec == "ass" || codec == "ssa"
    let header = isASSTrack
      ? (track.assHeader ?? sidecarHeader).map(SubtitleCueConverter.sanitizeHeader) : nil
    let key = "\(track.id)|\(header ?? "")"
    guard key != trackKey else { return }
    trackKey = key
    trackLabel = Self.label(codec: codec, renderer: renderer != nil)
    for font in fonts where Self.isFont(font) {
      renderer?.addFont(name: font.filename, data: font.data)
    }
    resetTrack(header: header)
    startTimer()
  }

  private func resetTrack(header: String?) {
    renderer?.reset(
      header: header
        ?? SubtitleCueConverter.defaultHeader(fontName: renderer?.defaultFamily, style: style))
    fedKeys.removeAll()
    feed(lastCues)
  }

  func update(cues: [SubtitleCue]) {
    lastCues = cues
    if trackKey != nil { feed(cues) }
  }

  /// AetherEngine 的 sourceTime 约 10Hz 更新，两次之间按播放速度插值
  func update(time: Double) {
    anchorTime = time
    anchorStamp = CACurrentMediaTime()
  }

  func setVideoSize(_ size: CGSize) {
    guard size != videoSize else { return }
    videoSize = size
    setNeedsRender()
  }

  func stop() {
    stopTimer()
    trackKey = nil
    clear()
  }

  private func feed(_ cues: [SubtitleCue]) {
    var bitmaps: [(id: Int, start: Double, end: Double, image: SubtitleImage)] = []
    for cue in cues {
      switch cue.body {
      case .text(let text):
        let raw = isASSTrack ? SubtitleCueConverter.rawASSEvents(text) : []
        let events = raw.isEmpty
          ? [SubtitleCueConverter.event(text: text, placement: cue.placement)] : raw
        add(events, start: cue.startTime, end: cue.endTime)
      case .richText(let runs):
        add(
          [SubtitleCueConverter.event(runs: runs, placement: cue.placement)],
          start: cue.startTime, end: cue.endTime)
      case .image(let image):
        bitmaps.append((cue.id, cue.startTime, Self.end(cue.startTime, cue.endTime), image))
      }
    }
    bitmapCues = bitmaps
    setNeedsRender()
  }

  private func add(_ events: [String], start: Double, end: Double) {
    let end = Self.end(start, end)
    for event in events where fedKeys.insert("\(start)|\(end)|\(event)").inserted {
      renderer?.add(
        event: event, startMs: Self.milliseconds(start),
        durationMs: Self.milliseconds(end - start))
    }
  }

  private func reanchor() {
    anchorTime = currentTime()
    anchorStamp = CACurrentMediaTime()
  }

  private func currentTime() -> Double {
    guard playing else { return anchorTime }
    return anchorTime + min(CACurrentMediaTime() - anchorStamp, 1) * rate
  }

  private func setNeedsRender() { needsRender = true }

  private func startTimer() {
    guard timer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func clear() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    contentLayer.contents = nil
    CATransaction.commit()
    bitmapCues = []
    shownBitmapIDs = []
  }

  private func tick() {
    let geometry = layoutGeometry()
    let scale = displayScale
    let width = Int32((geometry.visible.width * scale).rounded())
    let height = Int32((geometry.visible.height * scale).rounded())
    guard width > 0, height > 0 else { return }

    let now = currentTime() - delay
    let result = renderer?.render(timeMs: Self.milliseconds(now), width: width, height: height)
    let visibleBitmaps = bitmapCues.filter { $0.start <= now && now < $0.end }
    let bitmapIDs = visibleBitmaps.map(\.id)
    guard needsRender || result?.changed == true || bitmapIDs != shownBitmapIDs else { return }
    needsRender = false
    shownBitmapIDs = bitmapIDs

    let image = (result?.images != nil || !visibleBitmaps.isEmpty)
      ? compose(
        libass: result?.images, bitmaps: visibleBitmaps.map(\.image), geometry: geometry,
        width: Int(width), height: Int(height), scale: scale)
      : nil
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    contentLayer.frame = geometry.visible
    contentLayer.contentsScale = scale
    contentLayer.contents = image
    CATransaction.commit()
  }

  private func compose(
    libass: UnsafeMutablePointer<ASS_Image>?, bitmaps: [SubtitleImage],
    geometry: (video: CGRect, visible: CGRect), width: Int, height: Int, scale: CGFloat
  ) -> CGImage? {
    let count = width * height * 4
    if pixels.count != count { pixels = [UInt8](repeating: 0, count: count) }
    return pixels.withUnsafeMutableBufferPointer { buffer -> CGImage? in
      guard let base = buffer.baseAddress else { return nil }
      base.update(repeating: 0, count: count)
      guard
        let context = CGContext(
          data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue)
      else { return nil }
      drawBoxes(under: libass, in: context, height: height)
      LibassRenderer.composite(libass, into: base, width: width, height: height)
      for bitmap in bitmaps {
        let rect = Self.bitmapRect(bitmap, video: geometry.video, videoSize: videoSize)
          .offsetBy(dx: -geometry.visible.minX, dy: -geometry.visible.minY)
        let pixelRect = CGRect(
          x: rect.minX * scale, y: CGFloat(height) - rect.maxY * scale,
          width: rect.width * scale, height: rect.height * scale)
        context.draw(bitmap.cgImage, in: pixelRect)
      }
      return context.makeImage()
    }
  }

  /// 非 ASS 文本字幕的圆角底框：libass 输出的文字区域按行合并，画在文字下面
  private func drawBoxes(
    under first: UnsafeMutablePointer<ASS_Image>?, in context: CGContext, height: Int
  ) {
    let opacity = style?.backgroundOpacity ?? SubtitleCueConverter.defaultBackgroundOpacity
    guard !isASSTrack, opacity > 0 else { return }
    var rects: [CGRect] = []
    var node = first
    while let image = node?.pointee {
      defer { node = image.next }
      guard image.w > 0, image.h > 0 else { continue }
      rects.append(
        CGRect(
          x: Int(image.dst_x), y: height - Int(image.dst_y) - Int(image.h),
          width: Int(image.w), height: Int(image.h)))
    }
    var lines: [CGRect] = []
    for rect in rects.sorted(by: { $0.minY < $1.minY }) {
      if let last = lines.last, rect.minY < last.maxY {
        lines[lines.count - 1] = last.union(rect)
      } else {
        lines.append(rect)
      }
    }
    guard !lines.isEmpty else { return }
    let em = SubtitleCueConverter.fontSize * (style?.scale ?? 1) * CGFloat(height) / 1080
    let radius = em * 0.25
    let path = CGMutablePath()
    for line in lines {
      // 按墨迹排版，笔画矮的行（如“一一”、小写字母）补到统一行高，各行底框高度一致
      let grow = max(em * 0.8 - line.height, 0) / 2
      path.addRoundedRect(
        in: line.insetBy(dx: -em * 0.4, dy: -em * 0.18 - grow), cornerWidth: radius,
        cornerHeight: radius)
    }
    context.setFillColor(CGColor(gray: 0, alpha: min(opacity, 1)))
    context.addPath(path)
    context.fillPath()
  }

  /// 视频在视图中的显示区域（保持比例或铺满），以及与视图相交的可见部分
  private func layoutGeometry() -> (video: CGRect, visible: CGRect) {
    let bounds = self.bounds
    guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else {
      return (bounds, bounds)
    }
    let ratio = fill
      ? max(bounds.width / videoSize.width, bounds.height / videoSize.height)
      : min(bounds.width / videoSize.width, bounds.height / videoSize.height)
    let size = CGSize(width: videoSize.width * ratio, height: videoSize.height * ratio)
    let video = CGRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
      width: size.width, height: size.height)
    return (video, video.intersection(bounds))
  }

  /// 位图字幕坐标按画布归一化：画布按宽度对齐、垂直居中映射到视频区域
  private static func bitmapRect(_ image: SubtitleImage, video: CGRect, videoSize: CGSize) -> CGRect {
    let canvas = image.canvasSize == .zero ? videoSize : image.canvasSize
    guard canvas.width > 0 else { return .zero }
    let canvasHeight = video.width * canvas.height / canvas.width
    let canvasRect = CGRect(
      x: video.minX, y: video.midY - canvasHeight / 2, width: video.width, height: canvasHeight)
    return CGRect(
      x: canvasRect.minX + image.position.minX * canvasRect.width,
      y: canvasRect.minY + image.position.minY * canvasRect.height,
      width: image.position.width * canvasRect.width,
      height: image.position.height * canvasRect.height)
  }

  private var displayScale: CGFloat {
    #if os(iOS)
    return max(traitCollection.displayScale, 1)
    #elseif os(macOS)
    return window?.backingScaleFactor ?? 2
    #endif
  }

  private static func label(codec: String, renderer: Bool) -> String {
    let name: String
    switch codec {
    case "ass", "ssa": name = "ASS"
    case "subrip", "srt": name = "SRT"
    case "webvtt": name = "WebVTT"
    case "mov_text": name = "mov_text"
    case "hdmv_pgs_subtitle", "pgssub": return "PGS（位图）"
    case "dvd_subtitle", "dvdsub": return "VobSub（位图）"
    case "dvb_subtitle": return "DVB（位图）"
    default: name = codec
    }
    return renderer ? "\(name)（libass）" : "\(name)（渲染器不可用）"
  }

  private static func isFont(_ font: FontAttachment) -> Bool {
    let mime = font.mimeType.lowercased()
    if mime.contains("font") || mime.contains("truetype") || mime.contains("opentype") { return true }
    let ext = (font.filename as NSString).pathExtension.lowercased()
    return ["ttf", "otf", "ttc", "otc"].contains(ext)
  }

  /// 没有结束时间（直播图文电视等）的 cue 按 10 秒处理
  private static func end(_ start: Double, _ end: Double) -> Double {
    end.isFinite && end > start ? end : start + 10
  }

  private static func milliseconds(_ seconds: Double) -> Int64 {
    seconds.isFinite ? Int64((seconds * 1000).rounded()) : 0
  }
}
