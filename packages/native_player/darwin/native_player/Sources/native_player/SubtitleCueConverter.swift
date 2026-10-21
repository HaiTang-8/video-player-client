import AetherEngine
import CoreGraphics
import Foundation

/// 把 AetherEngine 的字幕 cue 转成 libass 能处理的事件行（Matroska 格式：
/// `ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text`，时间单独传入）
enum SubtitleCueConverter {
  /// 非 ASS 字幕使用的样式，接近 mpv 默认观感：白字黑边、居中靠下
  static func defaultHeader(fontName: String?) -> String {
    defaultHeaderTemplate.replacingOccurrences(of: "{font}", with: fontName ?? "sans-serif")
  }

  private static let defaultHeaderTemplate = """
    [Script Info]
    ScriptType: v4.00+
    PlayResX: 1920
    PlayResY: 1080
    ScaledBorderAndShadow: yes
    WrapStyle: 0

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
    Style: Default,{font},72,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,3.5,1.2,2,60,60,54,1

    """

  private static let defaultPlayRes = CGSize(width: 1920, height: 1080)

  /// MKV 的 CodecPrivate 常以 NUL 结尾，libass 按 C 字符串解析会丢掉其后的内容
  static func sanitizeHeader(_ header: String) -> String {
    header.replacingOccurrences(of: "\0", with: "")
  }

  /// ASS 轨的原始事件行；一个 cue 可能包含多行。形状不对的行（不是 9 个字段或 ReadOrder 不是数字）丢弃
  static func rawASSEvents(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
      let fields = line.split(separator: ",", maxSplits: 8, omittingEmptySubsequences: false)
      guard fields.count == 9, Int(fields[0].trimmingCharacters(in: .whitespaces)) != nil else {
        return nil
      }
      return String(line)
    }
  }

  static func event(text: String, placement: SubtitleTextPlacement?) -> String {
    event(body: escape(text), placement: placement)
  }

  static func event(runs: [SubtitleTextRun], placement: SubtitleTextPlacement?) -> String {
    let body = runs.map { run -> String in
      var tags = "\\r"
      if let color = run.color {
        tags += String(format: "\\c&H%02X%02X%02X&", color.b, color.g, color.r)
      }
      if run.isBold { tags += "\\b1" }
      if run.isItalic { tags += "\\i1" }
      if run.isUnderlined { tags += "\\u1" }
      if run.isStruckThrough { tags += "\\s1" }
      if let font = run.fontName, !font.isEmpty { tags += "\\fn\(font)" }
      return "{\(tags)}" + escape(run.text)
    }.joined()
    return event(body: body, placement: placement)
  }

  private static func event(body: String, placement: SubtitleTextPlacement?) -> String {
    var prefix = ""
    if let alignment = placement?.alignment, (1...9).contains(alignment) {
      prefix += "\\an\(alignment)"
    }
    if let position = placement?.position {
      let x = Int((position.x * defaultPlayRes.width).rounded())
      let y = Int((position.y * defaultPlayRes.height).rounded())
      prefix += "\\pos(\(x),\(y))"
    }
    let text = prefix.isEmpty ? body : "{\(prefix)}" + body
    return "0,0,Default,,0,0,0,,\(text)"
  }

  /// 换行转成 ASS 的 \N；花括号会被 libass 当作样式标签，换成全角字符
  private static func escape(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\n", with: "\\N")
      .replacingOccurrences(of: "{", with: "｛")
      .replacingOccurrences(of: "}", with: "｝")
  }
}
