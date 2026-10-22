package com.mediaserver.nativeplayer.dovi

import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * 解封装线程按样本时间保存每帧 RPU 的解析结果；播放线程记录“送显时间 → 显示时间”，
 * GL 线程用 SurfaceTexture 的时间戳（即送显时间）找到对应帧的参数
 */
class DoviFrameStore {
  private val bySampleUs = ConcurrentHashMap<Long, FloatArray>()
  private val releaseToPresentationUs = ConcurrentHashMap<Long, Long>()
  @Volatile private var errors = 0
  @Volatile var parsed = 0
    private set
  @Volatile var released = 0
    private set
  @Volatile private var lastPresentedUs = 0L

  val hasRpu: Boolean
    get() = parsed > 0

  fun onSampleRpu(timeUs: Long, nal: ByteArray) {
    val params = DoviNative.parse(nal)
    if (params == null) {
      if (errors++ < 5) Log.w(DoviSpike.TAG, "RPU parse failed at ${timeUs}us: ${DoviNative.lastError()}")
      return
    }
    if (parsed++ == 0) Log.i(DoviSpike.TAG, "first RPU at ${timeUs}us profile=${params[1].toInt()}")
    bySampleUs[timeUs] = params
    if (bySampleUs.size > MAX_FRAMES) prune()
  }

  fun onFrameReleased(presentationUs: Long, releaseNs: Long) {
    released++
    releaseToPresentationUs[releaseNs] = presentationUs
    if (releaseToPresentationUs.size > 64) {
      releaseToPresentationUs.keys.sorted().take(32).forEach(releaseToPresentationUs::remove)
    }
  }

  /** 返回该帧的显示时间和参数；参数找不到时为 null */
  fun lookup(releaseNs: Long): Pair<Long?, FloatArray?> {
    val presentationUs = releaseToPresentationUs.remove(releaseNs) ?: return null to null
    lastPresentedUs = presentationUs
    return presentationUs to bySampleUs[presentationUs]
  }

  /** 解封装会提前读几十秒，只能按播放位置清理，不能按解封装位置 */
  private fun prune() {
    val before = lastPresentedUs - KEEP_BEHIND_US
    bySampleUs.keys.filter { it < before }.forEach(bySampleUs::remove)
  }

  private companion object {
    /** 60 fps 下约 100 秒，覆盖 Media3 默认的 50 秒预读 */
    const val MAX_FRAMES = 6000
    const val KEEP_BEHIND_US = 2_000_000L
  }
}
