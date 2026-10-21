package com.mediaserver.nativeplayer

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.view.Display
import androidx.media3.common.MimeTypes

/** 设备的杜比视界解码能力和屏幕 HDR 能力 */
object DeviceCapabilities {
  private class DolbyVisionDecoder(val name: String, val profiles: Set<Int>)

  /** 与 ExoPlayer 选解码器的范围一致：全部解码器中去掉只用于 DRM 的安全解码器 */
  private val dolbyVisionDecoders: List<DolbyVisionDecoder> by lazy {
    MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
      .filter { info ->
        !info.isEncoder &&
          info.supportedTypes.any { it.equals(MimeTypes.VIDEO_DOLBY_VISION, ignoreCase = true) } &&
          !info.getCapabilitiesForType(MimeTypes.VIDEO_DOLBY_VISION)
            .isFeatureRequired(MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback)
      }
      .map { info ->
        val levels = info.getCapabilitiesForType(MimeTypes.VIDEO_DOLBY_VISION).profileLevels
        // CodecProfileLevel.DolbyVisionProfile* 是按 profile 编号递增的位标志
        DolbyVisionDecoder(info.name, levels.map { Integer.numberOfTrailingZeros(it.profile) }.toSet())
      }
  }

  val hasDolbyVisionDecoder: Boolean
    get() = dolbyVisionDecoders.isNotEmpty()

  /** 媒体信息面板中的“杜比视界解码器”一行 */
  val dolbyVisionDescription: String
    get() =
      dolbyVisionDecoders.joinToString("；") { decoder ->
        "${decoder.name}（${decoder.profiles.sorted().joinToString(", ") { "P$it" }}）"
      }.ifEmpty { "无" }

  /** 媒体信息面板中的“屏幕 HDR”一行 */
  fun displayHdrDescription(context: Context): String {
    val display =
      context.getSystemService(DisplayManager::class.java)?.getDisplay(Display.DEFAULT_DISPLAY)
        ?: return "未知"
    val types =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        display.mode.supportedHdrTypes
      } else {
        @Suppress("DEPRECATION")
        display.hdrCapabilities?.supportedHdrTypes ?: intArrayOf()
      }
    return types.sorted().joinToString(", ") { type ->
      when (type) {
        Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "杜比视界"
        Display.HdrCapabilities.HDR_TYPE_HDR10 -> "HDR10"
        Display.HdrCapabilities.HDR_TYPE_HLG -> "HLG"
        Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "HDR10+"
        else -> "类型 $type"
      }
    }.ifEmpty { "不支持" }
  }
}
