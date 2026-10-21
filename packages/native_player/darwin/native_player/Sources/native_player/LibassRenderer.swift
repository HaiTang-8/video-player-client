import CoreGraphics
import CoreText
import Foundation
import Libass

/// libass 的最小封装：一个渲染器 + 当前字幕轨。只在主线程使用。
/// 不使用系统字体来源（iOS 上系统中文字体文件位于私有目录，FreeType 读不到），
/// 只用传入的字体和 MKV 内嵌字体；请求的字体找不到时回退到默认字体
final class LibassRenderer {
  private let library: OpaquePointer
  private let renderer: OpaquePointer
  private var track: UnsafeMutablePointer<ASS_Track>?
  private var frameSize: (width: Int32, height: Int32) = (0, 0)
  private var addedFonts: Set<String> = []
  private let defaultFontPath: String?

  /// 默认字体的字体族名，用于非 ASS 字幕的默认样式
  let defaultFamily: String?

  init?(fontFiles: [URL]) {
    guard let library = ass_library_init() else { return nil }
    guard let renderer = ass_renderer_init(library) else {
      ass_library_done(library)
      return nil
    }
    self.library = library
    self.renderer = renderer
    defaultFontPath = fontFiles.first?.path
    defaultFamily = fontFiles.first.flatMap(Self.familyName)
    ass_set_message_cb(library, { _, _, _, _ in }, nil)
    ass_set_pixel_aspect(renderer, 1)
    for file in fontFiles {
      if let data = try? Data(contentsOf: file, options: .mappedIfSafe) {
        addFont(name: file.lastPathComponent, data: data, update: false)
      }
    }
    updateFonts()
  }

  deinit {
    if let track { ass_free_track(track) }
    ass_renderer_done(renderer)
    ass_library_done(library)
  }

  /// 内存字体（TTF / OTF），按文件名去重
  func addFont(name: String, data: Data, update: Bool = true) {
    guard !data.isEmpty, addedFonts.insert(name).inserted else { return }
    data.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
      ass_add_font(library, name, base, Int32(buffer.count))
    }
    if update { updateFonts() }
  }

  /// 换成新的字幕轨；ReadOrder 去重关闭（很多文件把它写死为 0），由调用方按内容去重
  func reset(header: String) {
    if let track { ass_free_track(track) }
    track = ass_new_track(library)
    guard let track else { return }
    ass_set_check_readorder(track, 0)
    let bytes = Array(header.utf8)
    bytes.withUnsafeBufferPointer { buffer in
      buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
        ass_process_codec_private(track, $0, Int32(buffer.count))
      }
    }
  }

  func add(event: String, startMs: Int64, durationMs: Int64) {
    guard let track else { return }
    let bytes = Array(event.utf8)
    bytes.withUnsafeBufferPointer { buffer in
      buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
        ass_process_chunk(track, $0, Int32(buffer.count), startMs, max(durationMs, 1))
      }
    }
  }

  /// 在 [timeMs] 时刻按像素尺寸渲染；changed 为 false 表示和上一次结果相同
  func render(timeMs: Int64, width: Int32, height: Int32) -> (
    images: UnsafeMutablePointer<ASS_Image>?, changed: Bool
  ) {
    guard let track, width > 0, height > 0 else { return (nil, false) }
    var resized = false
    if frameSize != (width, height) {
      frameSize = (width, height)
      ass_set_frame_size(renderer, width, height)
      ass_set_storage_size(renderer, width, height)
      resized = true
    }
    var change: Int32 = 0
    let images = ass_render_frame(renderer, track, timeMs, &change)
    return (images, resized || change != 0)
  }

  private func updateFonts() {
    ass_set_fonts(
      renderer, defaultFontPath, defaultFamily, Int32(ASS_FONTPROVIDER_NONE.rawValue), nil, 1)
  }

  private static func familyName(_ file: URL) -> String? {
    let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor]
    return descriptors?.first.flatMap {
      CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
    }
  }

  /// 把 libass 输出的单色 alpha 位图叠加到预乘 RGBA（行从上到下）缓冲区
  static func composite(
    _ first: UnsafeMutablePointer<ASS_Image>?, into pixels: UnsafeMutablePointer<UInt8>,
    width: Int, height: Int
  ) {
    var node = first
    while let image = node?.pointee {
      defer { node = image.next }
      guard image.w > 0, image.h > 0, let bitmap = image.bitmap else { continue }
      let color = image.color
      let red = Int((color >> 24) & 0xFF)
      let green = Int((color >> 16) & 0xFF)
      let blue = Int((color >> 8) & 0xFF)
      let opacity = 255 - Int(color & 0xFF)
      guard opacity > 0 else { continue }
      for row in 0..<Int(image.h) {
        let y = Int(image.dst_y) + row
        guard y >= 0, y < height else { continue }
        let source = bitmap + row * Int(image.stride)
        let target = pixels + y * width * 4
        for column in 0..<Int(image.w) {
          let x = Int(image.dst_x) + column
          guard x >= 0, x < width else { continue }
          let coverage = Int(source[column])
          guard coverage > 0 else { continue }
          let alpha = coverage * opacity / 255
          let inverse = 255 - alpha
          let pixel = target + x * 4
          pixel[0] = UInt8((red * alpha + Int(pixel[0]) * inverse) / 255)
          pixel[1] = UInt8((green * alpha + Int(pixel[1]) * inverse) / 255)
          pixel[2] = UInt8((blue * alpha + Int(pixel[2]) * inverse) / 255)
          pixel[3] = UInt8(alpha + Int(pixel[3]) * inverse / 255)
        }
      }
    }
  }
}
