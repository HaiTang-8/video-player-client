package com.mediaserver.nativeplayer.dovi

import android.annotation.SuppressLint
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES30
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil

/**
 * 本机能否用 GPU 把杜比视界 P5 重建为 HDR10：需要 BT.2020 PQ 窗口表面、10 位窗口格式、
 * `GL_EXT_YUV_target`（读原始 YUV）和 libdovi。另提供两个调试属性：
 * `debug.nativeplayer.dovi.log=1` 每 5 秒输出帧统计，`debug.nativeplayer.dovi.dump=<显示时间微秒>` 读回该帧的 PQ 网格，
 * `debug.nativeplayer.dovi.mmr=1` 用等价的 MMR 代替多项式
 */
object DoviSupport {
  const val TAG = "DoviReshape"
  const val EGL_OPENGL_ES3_BIT = 0x40
  const val EGL_GL_COLORSPACE_BT2020_PQ = "EGL_EXT_gl_colorspace_bt2020_pq"
  const val EGL_HDR10_METADATA = "EGL_EXT_surface_SMPTE2086_metadata"

  val available: Boolean by lazy { probe() }

  /** 支持时窗口表面附带 HDR10 静态元数据 */
  var hdrMetadataSupported = false
    private set

  val verbose: Boolean
    get() = property("debug.nativeplayer.dovi.log") == "1"

  val dumpAtUs: Long?
    get() = property("debug.nativeplayer.dovi.dump").toLongOrNull()

  /** 把多项式改成等价的 3 阶 MMR 再上传，用来在真机上验证着色器的 MMR 分支 */
  val polynomialAsMmr: Boolean
    get() = property("debug.nativeplayer.dovi.mmr") == "1"

  /** 10 位 RGBA 窗口配置；没有时返回 null */
  fun chooseConfig(display: android.opengl.EGLDisplay): EGLConfig? {
    val attributes =
      intArrayOf(
        EGL14.EGL_RED_SIZE, 10,
        EGL14.EGL_GREEN_SIZE, 10,
        EGL14.EGL_BLUE_SIZE, 10,
        EGL14.EGL_ALPHA_SIZE, 2,
        EGL14.EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT or EGL14.EGL_PBUFFER_BIT,
        EGL14.EGL_NONE,
      )
    val configs = arrayOfNulls<EGLConfig>(1)
    val count = IntArray(1)
    return if (EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) && count[0] > 0) {
      configs[0]
    } else {
      null
    }
  }

  /** 没有杜比视界解码器但能重建时，封装声明了杜比视界的片源也交给普通 HEVC 解码器 */
  @OptIn(UnstableApi::class)
  val hevcForDolbyVision = MediaCodecSelector { mimeType, secure, tunneling ->
    val target = if (mimeType == MimeTypes.VIDEO_DOLBY_VISION) MimeTypes.VIDEO_H265 else mimeType
    MediaCodecUtil.getDecoderInfos(target, secure, tunneling)
  }

  /** 默认 display 在进程内共享，探测时只释放自己创建的对象，不调用 eglTerminate */
  private fun probe(): Boolean {
    val result =
      runCatching {
          System.loadLibrary("dovi_jni")
          val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
          val version = IntArray(2)
          check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize" }
          val eglExtensions = EGL14.eglQueryString(display, EGL14.EGL_EXTENSIONS).orEmpty()
          check(EGL_GL_COLORSPACE_BT2020_PQ in eglExtensions) { "no $EGL_GL_COLORSPACE_BT2020_PQ" }
          hdrMetadataSupported = EGL_HDR10_METADATA in eglExtensions
          val config = checkNotNull(chooseConfig(display)) { "no RGBA1010102 config" }
          val context =
            EGL14.eglCreateContext(
              display,
              config,
              EGL14.EGL_NO_CONTEXT,
              intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
              0,
            )
          val surface =
            EGL14.eglCreatePbufferSurface(display, config, intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
          try {
            check(EGL14.eglMakeCurrent(display, surface, surface, context)) { "eglMakeCurrent" }
            val glExtensions = GLES30.glGetString(GLES30.GL_EXTENSIONS).orEmpty()
            check("GL_EXT_YUV_target" in glExtensions) { "no GL_EXT_YUV_target" }
            check("GL_OES_EGL_image_external_essl3" in glExtensions) { "no GL_OES_EGL_image_external_essl3" }
          } finally {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, surface)
            EGL14.eglDestroyContext(display, context)
          }
        }
        .onFailure { Log.i(TAG, "GPU reshaping unavailable: ${it.message}") }
    return result.isSuccess
  }

  @SuppressLint("PrivateApi")
  private fun property(key: String): String =
    runCatching {
        Class.forName("android.os.SystemProperties")
          .getMethod("get", String::class.java)
          .invoke(null, key) as String
      }
      .getOrDefault("")
}
