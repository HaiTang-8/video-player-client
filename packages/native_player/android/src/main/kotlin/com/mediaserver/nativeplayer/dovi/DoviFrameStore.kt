package com.mediaserver.nativeplayer.dovi

import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * 一个片源的逐帧 RPU：解封装线程按样本时间保存解析结果；播放线程记录“送显时间 → 显示时间”，
 * GL 线程用 SurfaceTexture 的时间戳（即送显时间）找到对应帧的参数。
 *
 * @param onProfile5 第一次解析出 P5 时调用（解封装线程），需要切到 GPU 重建
 * @param onUnusable 一直无法解析时调用（解封装线程），参数为原因
 */
class DoviFrameStore(private val onProfile5: () -> Unit, private val onUnusable: (String) -> Unit) {
  private val bySampleUs = ConcurrentHashMap<Long, FloatArray>()
  private val releaseToPresentationUs = ConcurrentHashMap<Long, Long>()
  private val released = AtomicInteger()
  private var parsed = 0
  private var consecutiveErrors = 0
  @Volatile private var lastPresentedUs: Long? = null

  /** 返回是否继续捕获：不是 P5（如 P8 的基础层本身就是 HDR10）或一直解析失败时停止 */
  fun onSampleRpu(timeUs: Long, nal: ByteArray): Boolean {
    val params = DoviNative.parse(nal)
    if (params == null) {
      if (parsed == 0 && ++consecutiveErrors >= MAX_ERRORS) {
        onUnusable("无法解析杜比视界元数据（${DoviNative.lastError()}）")
        return false
      }
      return true
    }
    consecutiveErrors = 0
    val profile = params[1].toInt()
    if (profile != 5) return false
    if (parsed++ == 0) {
      Log.i(DoviSupport.TAG, "Dolby Vision profile 5 detected at ${timeUs}us")
      onProfile5()
    }
    bySampleUs[timeUs] = params
    if (bySampleUs.size > MAX_FRAMES) prune()
    return true
  }

  fun onFrameReleased(presentationUs: Long, releaseNs: Long) {
    released.incrementAndGet()
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

  /** 跳转后到新位置的第一帧显示前不清理，避免删掉刚读到的帧 */
  fun onSeek() {
    lastPresentedUs = null
  }

  /** 调试统计用：返回上次调用以来送显的帧数 */
  fun takeReleased(): Int = released.getAndSet(0)

  /** 解封装会提前读几十秒，只能按播放位置清理，不能按解封装位置 */
  private fun prune() {
    val before = (lastPresentedUs ?: return) - KEEP_BEHIND_US
    bySampleUs.keys.filter { it < before }.forEach(bySampleUs::remove)
  }

  private companion object {
    /** 60 fps 下约 100 秒，覆盖 Media3 默认的 50 秒预读 */
    const val MAX_FRAMES = 6000
    const val KEEP_BEHIND_US = 2_000_000L
    const val MAX_ERRORS = 30
  }
}
