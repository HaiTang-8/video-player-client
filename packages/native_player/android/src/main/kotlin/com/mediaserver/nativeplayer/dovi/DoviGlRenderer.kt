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
import java.util.concurrent.CountDownLatch

/**
 * 自绘视频管线：解码器输出到自己的 SurfaceTexture，GL 线程读原始 YUV 后画到 SurfaceView，
 * 窗口表面声明为 BT.2020 PQ 并附带 HDR10 静态元数据。
 */
class DoviGlRenderer(private val store: DoviFrameStore) {
  private val thread = HandlerThread("DoviGl").apply { start() }
  private val handler = Handler(thread.looper)
  private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
  private var config: EGLConfig? = null
  private var context: EGLContext = EGL14.EGL_NO_CONTEXT
  private var pbuffer: EGLSurface = EGL14.EGL_NO_SURFACE
  private var window: EGLSurface = EGL14.EGL_NO_SURFACE
  private var texture = 0
  private var program = 0
  private var doviProgram = 0
  private var params: FloatArray? = null
  private val uniforms = DoviUniforms()
  private var loggedFrames = 0
  private var dumped = false
  private var surfaceTexture: SurfaceTexture? = null
  private val transform = FloatArray(16)
  private var surfaceView: SurfaceView? = null
  private var frames = 0
  private var drawNanos = 0L
  private var missingRpu = 0
  private var releasedAtStats = 0
  private var gpuSamples = 0
  private var gpuNanos = 0L
  private var statsSince = SystemClock.elapsedRealtime()

  /** 交给播放器的视频输出 */
  lateinit var inputSurface: Surface
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
      surfaceTexture?.release()
      inputSurface.release()
      GLES30.glDeleteProgram(program)
      GLES30.glDeleteProgram(doviProgram)
      GLES30.glDeleteTextures(1, intArrayOf(texture), 0)
      EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
      EGL14.eglDestroySurface(display, pbuffer)
      EGL14.eglDestroyContext(display, context)
      EGL14.eglTerminate(display)
    }
    thread.quitSafely()
  }

  private fun setUp() {
    display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    val version = IntArray(2)
    check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize" }
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
    check(EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) && count[0] > 0) {
      "no RGBA1010102 config"
    }
    config = configs[0]
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
    Log.i(DoviSpike.TAG, "EGL ${version[0]}.${version[1]}, ${GLES30.glGetString(GLES30.GL_RENDERER)}")

    program = buildProgram(VERTEX_SHADER, HDR10_PASSTHROUGH_SHADER)
    doviProgram = buildProgram(VERTEX_SHADER, DoviUniforms.RESHAPE_SHADER)
    val textures = IntArray(1)
    GLES30.glGenTextures(1, textures, 0)
    texture = textures[0]
    GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
    GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
    GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
    GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
    GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
    val st = SurfaceTexture(texture)
    st.setOnFrameAvailableListener({ onFrame() }, handler)
    surfaceTexture = st
    inputSurface = Surface(st)
  }

  private fun createWindow(surface: Surface) {
    destroyWindow()
    window =
      EGL14.eglCreateWindowSurface(
        display,
        config,
        surface,
        intArrayOf(EGL_GL_COLORSPACE_KHR, EGL_GL_COLORSPACE_BT2020_PQ_EXT, EGL14.EGL_NONE),
        0,
      )
    if (window == EGL14.EGL_NO_SURFACE) {
      Log.e(DoviSpike.TAG, "eglCreateWindowSurface(BT2020_PQ) failed: 0x${Integer.toHexString(EGL14.eglGetError())}")
      return
    }
    setHdrMetadata()
    Log.i(DoviSpike.TAG, "window created, colorspace=BT2020_PQ")
    draw()
  }

  /** 先用固定的 HDR10 静态元数据：BT.2020 / D65、1000 nits */
  private fun setHdrMetadata() {
    val metadata =
      listOf(
        EGL_SMPTE2086_DISPLAY_PRIMARY_RX_EXT to 0.708f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_RY_EXT to 0.292f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_GX_EXT to 0.170f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_GY_EXT to 0.797f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_BX_EXT to 0.131f,
        EGL_SMPTE2086_DISPLAY_PRIMARY_BY_EXT to 0.046f,
        EGL_SMPTE2086_WHITE_POINT_X_EXT to 0.3127f,
        EGL_SMPTE2086_WHITE_POINT_Y_EXT to 0.3290f,
        EGL_SMPTE2086_MAX_LUMINANCE_EXT to 1000f,
        EGL_SMPTE2086_MIN_LUMINANCE_EXT to 0.005f,
        EGL_CTA861_3_MAX_CONTENT_LIGHT_LEVEL_EXT to 1000f,
        EGL_CTA861_3_MAX_FRAME_AVERAGE_LEVEL_EXT to 400f,
      )
    for ((key, value) in metadata) {
      if (!EGL14.eglSurfaceAttrib(display, window, key, (value * EGL_METADATA_SCALING_EXT).toInt())) {
        Log.w(DoviSpike.TAG, "eglSurfaceAttrib 0x${Integer.toHexString(key)} failed")
      }
    }
  }

  private fun destroyWindow() {
    if (window == EGL14.EGL_NO_SURFACE) return
    EGL14.eglMakeCurrent(display, pbuffer, pbuffer, context)
    EGL14.eglDestroySurface(display, window)
    window = EGL14.EGL_NO_SURFACE
  }

  private fun onFrame() {
    val st = surfaceTexture ?: return
    if (window == EGL14.EGL_NO_SURFACE) EGL14.eglMakeCurrent(display, pbuffer, pbuffer, context)
    st.updateTexImage()
    st.getTransformMatrix(transform)
    val (presentationUs, frameParams) = store.lookup(st.timestamp)
    if (store.hasRpu && frameParams == null) missingRpu++
    if (frameParams != null && frameParams !== params) {
      params = frameParams
      uniforms.pack(frameParams)
    }
    if (loggedFrames < 8 && store.hasRpu) {
      loggedFrames++
      Log.i(DoviSpike.TAG, "frame release=${st.timestamp} pts=$presentationUs rpu=${frameParams != null}")
    }
    draw()
  }

  private fun draw() {
    if (window == EGL14.EGL_NO_SURFACE) return
    val start = System.nanoTime()
    EGL14.eglMakeCurrent(display, window, window, context)
    val size = IntArray(2)
    EGL14.eglQuerySurface(display, window, EGL14.EGL_WIDTH, size, 0)
    EGL14.eglQuerySurface(display, window, EGL14.EGL_HEIGHT, size, 1)
    GLES30.glViewport(0, 0, size[0], size[1])
    val active = if (store.hasRpu && params != null) doviProgram else program
    GLES30.glUseProgram(active)
    GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
    GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
    GLES30.glUniform1i(GLES30.glGetUniformLocation(active, "uTex"), 0)
    GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(active, "uTransform"), 1, false, transform, 0)
    if (active == doviProgram) uniforms.upload(active)
    val position = GLES30.glGetAttribLocation(active, "aPosition")
    GLES30.glEnableVertexAttribArray(position)
    GLES30.glVertexAttribPointer(position, 2, GLES30.GL_FLOAT, false, 0, QUAD)
    GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    if (frames % 48 == 0) {
      val gpuStart = System.nanoTime()
      GLES30.glFinish()
      gpuNanos += System.nanoTime() - gpuStart
      gpuSamples++
    }
    if (DoviSpike.dump && !dumped) {
      dumped = true
      dumpGrid(size[0], size[1])
    }
    EGL14.eglSwapBuffers(display, window)
    drawNanos += System.nanoTime() - start
    frames++
    val now = SystemClock.elapsedRealtime()
    if (now - statsSince >= 5000) {
      val released = store.released - releasedAtStats
      Log.i(
        DoviSpike.TAG,
        "fps=${"%.1f".format(frames * 1000f / (now - statsSince))} drawn=$frames released=$released " +
          "missingRpu=$missingRpu cpuDraw=${"%.2f".format(drawNanos / 1e6 / frames)}ms " +
          "gpuFinish=${if (gpuSamples > 0) "%.2f".format(gpuNanos / 1e6 / gpuSamples) else "-"}ms",
      )
      frames = 0
      drawNanos = 0
      missingRpu = 0
      gpuNanos = 0
      gpuSamples = 0
      releasedAtStats = store.released
      statsSince = now
    }
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
      Log.i(DoviSpike.TAG, line.toString())
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

  private companion object {
    const val GRID_COLS = 48
    const val GRID_ROWS = 27
    const val EGL_OPENGL_ES3_BIT = 0x40
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

    /** HDR10 直通：BT.2020 有限范围 YCbCr → PQ 编码的 R'G'B'，窗口表面本身就是 PQ，不做传输函数转换 */
    const val HDR10_PASSTHROUGH_SHADER =
      """#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
#extension GL_EXT_YUV_target : require
precision highp float;
uniform __samplerExternal2DY2YEXT uTex;
in vec2 vTex;
out vec4 outColor;
void main() {
  vec3 yuv = texture(uTex, vTex).xyz - vec3(0.0625, 0.5, 0.5);
  mat3 m = mat3(1.1689, 1.1689, 1.1689, 0.0, -0.1881, 2.1502, 1.6853, -0.6530, 0.0);
  outColor = vec4(clamp(m * yuv, 0.0, 1.0), 1.0);
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
