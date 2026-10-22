package com.mediaserver.nativeplayer.dovi

import android.annotation.SuppressLint
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil

/** Spike 开关：`adb shell setprop debug.nativeplayer.dovi 1` 后新建的播放器改走自绘 HDR 管线 */
object DoviSpike {
  const val TAG = "DoviSpike"

  val enabled: Boolean
    get() = property("debug.nativeplayer.dovi") == "1"

  /** 窗口建立后的第一帧读回并输出 PQ 网格 */
  val dump: Boolean
    get() = property("debug.nativeplayer.dovi.dump") == "1"

  @SuppressLint("PrivateApi")
  private fun property(key: String): String =
    runCatching {
        Class.forName("android.os.SystemProperties")
          .getMethod("get", String::class.java)
          .invoke(null, key) as String
      }
      .getOrDefault("")

  /** 封装声明了杜比视界（dvhe）的片源也交给普通 HEVC 解码器，基础层由着色器重建颜色 */
  @OptIn(UnstableApi::class)
  val hevcForDolbyVision = MediaCodecSelector { mimeType, secure, tunneling ->
    val target = if (mimeType == MimeTypes.VIDEO_DOLBY_VISION) MimeTypes.VIDEO_H265 else mimeType
    MediaCodecUtil.getDecoderInfos(target, secure, tunneling)
  }
}
