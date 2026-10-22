package com.mediaserver.nativeplayer.dovi

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES30
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.Locale
import java.util.concurrent.CountDownLatch

/**
 * 杜比视界 P5 → HDR10：解码器输出到自建 SurfaceTexture，GL 线程读原始 YUV、按当前帧的 RPU 重建颜色，
 * 画到 SurfaceView 的 BT.2020 PQ 窗口表面（附带 HDR10 静态元数据）。需要先确认 [DoviSupport.available]
 */
class DoviGlRenderer {
  private val thread = HandlerThread("DoviGl").apply { start() }
  private val handler = Handler(thread.looper)
  private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
  private var config: EGLConfig? = null
  private var context: EGLContext = EGL14.EGL_NO_CONTEXT
  private var pbuffer: EGLSurface = EGL14.EGL_NO_SURFACE
  private var window: EGLSurface = EGL14.EGL_NO_SURFACE
  private var windowSurface: Surface? = null
  private var windowRetries = 0
  private var texture = 0
  private var program = 0
  private lateinit var surfaceTexture: SurfaceTexture
  private val transform = FloatArray(16)
  private val uniforms = DoviUniforms()
  private var store: DoviFrameStore? = null
  private var params: FloatArray? = null
  /** 母版最大 / 最小亮度、MaxCLL、MaxFALL（nits，0 表示未知） */
  private var hdrMetadata = FloatArray(4)
  private var surfaceView: SurfaceView? = null
  private val verbose = DoviSupport.verbose
  private val dumpAtUs = DoviSupport.dumpAtUs
  private var dumpPending = false
  private val stats = Stats()

  /** 交给播放器的视频输出 */
  lateinit var inputSurface: Surface
    private set

  /** 当前使用的 HDR10 静态元数据，供媒体信息面板显示 */
  @Volatile var hdrMetadataDescription: String? = null
    private set

  private val holderCallback =
    object : SurfaceHolder.Callback {
      override fun surfaceCreated(holder: SurfaceHolder) {
        runBlocking { createWindow(holder.surface) }
      }

      override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        handler.post { draw() }
      }

      override fun surfaceDestroyed(holder: SurfaceHolder) {
        runBlocking { destroyWindow() }
      }
    }

  init {
    runBlocking { setUp() }
  }

  /** 切换到新片源的 RPU 缓存；旧参数作废，避免把上一个视频的元数据用到新视频上 */
  fun bind(store: DoviFrameStore) = runBlocking {
    this.store = store
    params = null
    hdrMetadata = FloatArray(4)
    hdrMetadataDescription = null
  }

  fun attach(view: SurfaceView) {
    detach()
    surfaceView = view
    view.holder.addCallback(holderCallback)
    val surface = view.holder.surface
    if (surface != null && surface.isValid) runBlocking { createWindow(surface) }
  }

  fun detach() {
    val view = surfaceView ?: return
    view.holder.removeCallback(holderCallback)
    surfaceView = null
    runBlocking { destroyWindow() }
  }

  fun release() {
    detach()
    runBlocking {
      surfaceTexture.release()
      inputSurface.release()
      GLES30.glDeleteProgram(program)
      GLES30.glDeleteTextures(1, intArrayOf(texture), 0)
      EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
      EGL14.eglDestroySurface(display, pbuffer)
      EGL14.eglDestroyContext(display, context)
    }
    thread.quitSafely()
  }

  private fun setUp() {
    display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    val version = IntArray(2)
    check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize" }
    config = checkNotNull(DoviSupport.chooseConfig(display)) { "no RGBA1010102 config" }
    context =
      EGL14.eglCreateContext(
        display,
        config,
        EGL14.EGL_NO_CONTEXT,
        intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
        0,
      )
    pbuffer =
      EGL14.eglCreatePbufferSurface(display, config, intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
    check(EGL14.eglMakeCurrent(display, pbuffer, pbuffer, context)) { "eglMakeCurrent" }
    program = buildProgram(VERTEX_SHADER, DoviUniforms.RESHAPE_SHADER)
    val textures = IntArray(1)
    GLES30.glGenTextures(1, textures, 0)
    texture = textures[0]
    GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
    GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
    GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
    GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
    GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
    surfaceTexture = SurfaceTexture(texture).apply { setOnFrameAvailableListener({ onFrame() }, handler) }
    inputSurface = Surface(surfaceTexture)
  }

  /** 刚从解码器直出切过来时，解码器可能还没断开这个 Surface，创建失败就稍后重试 */
  private fun createWindow(surface: Surface) {
    destroyWindow()
    windowSurface = surface
    window =
      EGL14.eglCreateWindowSurface(
        display,
        config,
        surface,
        intArrayOf(EGL_GL_COLORSPACE_KHR, EGL_GL_COLORSPACE_BT2020_PQ_EXT, EGL14.EGL_NONE),
        0,
      )
    if (window == EGL14.EGL_NO_SURFACE) {
      val error = EGL14.eglGetError()
      if (windowRetries++ < MAX_WINDOW_RETRIES) {
        handler.postDelayed({ if (windowSurface === surface && surface.isValid) createWindow(surface) }, WINDOW_RETRY_MS)
      } else {
        Log.e(DoviSupport.TAG, "eglCreateWindowSurface failed: 0x${Integer.toHexString(error)}")
      }
      return
    }
    windowRetries = 0
    applyHdrMetadata()
    draw()
  }

  private fun destroyWindow() {
    windowSurface = null
    if (window == EGL14.EGL_NO_SURFACE) return
    EGL14.eglMakeCurrent(display, pbuffer, pbuffer, context)
    EGL14.eglDestroySurface(display, window)
    window = EGL14.EGL_NO_SURFACE
  }

  private fun onFrame() {
    if (window == EGL14.EGL_NO_SURFACE) EGL14.eglMakeCurrent(display, pbuffer, pbuffer, context)
    surfaceTexture.updateTexImage()
    surfaceTexture.getTransformMatrix(transform)
    val store = store ?: return
    val (presentationUs, frameParams) = store.lookup(surfaceTexture.timestamp)
    if (frameParams == null) stats.missingRpu++
    // 当前帧没有可用的 RPU（例如沿用上一帧映射）时继续用上一帧的参数
    if (frameParams != null && frameParams !== params) {
      params = frameParams
      uniforms.pack(frameParams)
      val metadata = hdrMetadata(frameParams)
      if (!metadata.contentEquals(hdrMetadata)) {
        hdrMetadata = metadata
        hdrMetadataDescription = describe(metadata)
        applyHdrMetadata()
      }
    }
    if (presentationUs != null && presentationUs == dumpAtUs) dumpPending = true
    draw()
  }

  private fun applyHdrMetadata() {
    if (window == EGL14.EGL_NO_SURFACE || !DoviSupport.hdrMetadataSupported || hdrMetadata[0] <= 0f) return
    val (maxLuminance, minLuminance, maxCll, maxFall) = hdrMetadata.toList()
    // 母版显示器按杜比视界常见的 P3-D65
    val values =
      listOf(
        EGL_SMPTE2086_DISPLAY_PRIMARY_RX_EXT to 0.680f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_RY_EXT to 0.320f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_GX_EXT to 0.265f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_GY_EXT to 0.690f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_BX_EXT to 0.150f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_BY_EXT to 0.060f,
        EGL_SMPTE2086_WHITE_POINT_X_EXT to 0.3127f,
        EGL_SMPTE2086_WHITE_POINT_Y_EXT to 0.3290f,
        EGL_SMPTE2086_MAX_LUMINANCE_EXT to maxLuminance,
        EGL_SMPTE2086_MIN_LUMINANCE_EXT to minLuminance,
        EGL_CTA861_3_MAX_CONTENT_LIGHT_LEVEL_EXT to maxCll,
        EGL_CTA861_3_MAX_FRAME_AVERAGE_LEVEL_EXT to maxFall,
      )
    for ((key, value) in values) {
      EGL14.eglSurfaceAttrib(display, window, key, (value * EGL_METADATA_SCALING_EXT).toInt())
    }
  }

  private fun draw() {
    if (window == EGL14.EGL_NO_SURFACE || params == null) return
    val start = System.nanoTime()
    EGL14.eglMakeCurrent(display, window, window, context)
    val size = IntArray(2)
    EGL14.eglQuerySurface(display, window, EGL14.EGL_WIDTH, size, 0)
    EGL14.eglQuerySurface(display, window, EGL14.EGL_HEIGHT, size, 1)
    GLES30.glViewport(0, 0, size[0], size[1])
    GLES30.glUseProgram(program)
    GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
    GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
    GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uTex"), 0)
    GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(program, "uTransform"), 1, false, transform, 0)
    uniforms.upload(program)
    val position = GLES30.glGetAttribLocation(program, "aPosition")
    GLES30.glEnableVertexAttribArray(position)
    GLES30.glVertexAttribPointer(position, 2, GLES30.GL_FLOAT, false, 0, QUAD)
    GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    if (dumpPending) {
      dumpPending = false
      dumpGrid(size[0], size[1])
    }
    EGL14.eglSwapBuffers(display, window)
    if (verbose) stats.onDraw(System.nanoTime() - start)
  }

  /** 读回刚画好的 PQ 值，按 48×27 网格（从左上角起）输出到日志，供与参考实现对比 */
  private fun dumpGrid(width: Int, height: Int) {
    val buffer = ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder())
    GLES30.glReadPixels(0, 0, width, height, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_INT_2_10_10_10_REV, buffer)
    val pixels = buffer.asIntBuffer()
    for (row in 0 until GRID_ROWS) {
      val y = height - 1 - ((row + 0.5f) * height / GRID_ROWS).toInt()
      val line = StringBuilder("grid $row:")
      for (col in 0 until GRID_COLS) {
        val x = ((col + 0.5f) * width / GRID_COLS).toInt()
        val p = pixels[y * width + x]
        line.append(' ').append(p and 0x3FF).append(',').append((p shr 10) and 0x3FF).append(',').append((p shr 20) and 0x3FF)
      }
      Log.i(DoviSupport.TAG, line.toString())
    }
  }

  private fun runBlocking(action: () -> Unit) {
    if (Thread.currentThread() == thread) return action()
    val latch = CountDownLatch(1)
    var error: Throwable? = null
    handler.post {
      try {
        action()
      } catch (e: Throwable) {
        error = e
      } finally {
        latch.countDown()
      }
    }
    latch.await()
    error?.let { throw it }
  }

  /** 调试统计：每 5 秒输出绘制帧数、缺少 RPU 的帧数、CPU 绘制耗时和（每 48 帧抽样的）GPU 耗时 */
  private inner class Stats {
    var missingRpu = 0
    private var frames = 0
    private var drawNanos = 0L
    private var gpuNanos = 0L
    private var gpuSamples = 0
    private var since = SystemClock.elapsedRealtime()

    fun onDraw(nanos: Long) {
      drawNanos += nanos
      if (frames++ % 48 == 0) {
        val start = System.nanoTime()
        GLES30.glFinish()
        gpuNanos += System.nanoTime() - start
        gpuSamples++
      }
      val now = SystemClock.elapsedRealtime()
      if (now - since < 5000) return
      Log.i(
        DoviSupport.TAG,
        String.format(
          Locale.US,
          "fps=%.1f drawn=%d released=%d missingRpu=%d cpuDraw=%.2fms gpuFinish=%.2fms",
          frames * 1000f / (now - since),
          frames,
          store?.takeReleased() ?: 0,
          missingRpu,
          drawNanos / 1e6 / frames,
          gpuNanos / 1e6 / gpuSamples,
        ),
      )
      frames = 0
      drawNanos = 0
      gpuNanos = 0
      gpuSamples = 0
      missingRpu = 0
      since = now
    }
  }

  private companion object {
    const val MAX_WINDOW_RETRIES = 20
    const val WINDOW_RETRY_MS = 50L
    const val GRID_COLS = 48
    const val GRID_ROWS = 27
    const val EGL_GL_COLORSPACE_KHR = 0x309D
    const val EGL_GL_COLORSPACE_BT2020_PQ_EXT = 0x3340
    const val EGL_SMPTE2086_DISPLAY_PRIMARY_RX_EXT = 0x3341
    const val EGL_SMPTE2086_DISPLAY_PRIMARY_RY_EXT = 0x3342
    const val EGL_SMPTE2086_DISPLAY_PRIMARY_GX_EXT = 0x3343
    const val EGL_SMPTE2086_DISPLAY_PRIMARY_GY_EXT = 0x3344
    const val EGL_SMPTE2086_DISPLAY_PRIMARY_BX_EXT = 0x3345
    const val EGL_SMPTE2086_DISPLAY_PRIMARY_BY_EXT = 0x3346
    const val EGL_SMPTE2086_WHITE_POINT_X_EXT = 0x3347
    const val EGL_SMPTE2086_WHITE_POINT_Y_EXT = 0x3348
    const val EGL_SMPTE2086_MAX_LUMINANCE_EXT = 0x3349
    const val EGL_SMPTE2086_MIN_LUMINANCE_EXT = 0x334A
    const val EGL_CTA861_3_MAX_CONTENT_LIGHT_LEVEL_EXT = 0x3360
    const val EGL_CTA861_3_MAX_FRAME_AVERAGE_LEVEL_EXT = 0x3361
    const val EGL_METADATA_SCALING_EXT = 50000

    const val PQ_M1 = 2610.0 / 16384.0
    const val PQ_M2 = 2523.0 / 4096.0 * 128.0
    const val PQ_C1 = 3424.0 / 4096.0
    const val PQ_C2 = 2413.0 / 4096.0 * 32.0
    const val PQ_C3 = 2392.0 / 4096.0 * 32.0

    /** 有 L6 就用 L6；没有时母版亮度取 source_min/max_pq，MaxCLL / MaxFALL 记为未知 */
    fun hdrMetadata(params: FloatArray): FloatArray =
      if (params[25] > 0f) {
        floatArrayOf(params[25], params[26], params[27], params[28])
      } else {
        floatArrayOf(pqToNits(params[24]), pqToNits(params[23]), 0f, 0f)
      }

    fun describe(metadata: FloatArray): String {
      val (maxLuminance, minLuminance, maxCll, maxFall) = metadata.toList()
      val mastering = String.format(Locale.US, "母版 %.0f / %.4f nits", maxLuminance, minLuminance)
      return if (maxCll > 0f) {
        String.format(Locale.US, "%s，MaxCLL %.0f，MaxFALL %.0f", mastering, maxCll, maxFall)
      } else {
        mastering
      }
    }

    fun pqToNits(value: Float): Float {
      val p = Math.pow(value.toDouble(), 1.0 / PQ_M2)
      return (10000.0 * Math.pow(maxOf(p - PQ_C1, 0.0) / (PQ_C2 - PQ_C3 * p), 1.0 / PQ_M1)).toFloat()
    }

    val QUAD: FloatBuffer =
      ByteBuffer.allocateDirect(8 * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply {
          put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
          position(0)
        }

    const val VERTEX_SHADER =
      """#version 300 es
in vec2 aPosition;
uniform mat4 uTransform;
out vec2 vTex;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
  vTex = (uTransform * vec4((aPosition + 1.0) * 0.5, 0.0, 1.0)).xy;
}
"""

    fun buildProgram(vertex: String, fragment: String): Int {
      fun compile(type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)
        val status = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
        check(status[0] != 0) { "shader compile failed: ${GLES30.glGetShaderInfoLog(shader)}" }
        return shader
      }
      val program = GLES30.glCreateProgram()
      GLES30.glAttachShader(program, compile(GLES30.GL_VERTEX_SHADER, vertex))
      GLES30.glAttachShader(program, compile(GLES30.GL_FRAGMENT_SHADER, fragment))
      GLES30.glLinkProgram(program)
      val status = IntArray(1)
      GLES30.glGetProgramiv(program, GLES30.GL_LINK_STATUS, status, 0)
      check(status[0] != 0) { "program link failed: ${GLES30.glGetProgramInfoLog(program)}" }
      return program
    }
  }
}
