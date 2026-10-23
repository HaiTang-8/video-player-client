package com.mediaserver.nativeplayer

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.text.Cue
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** 播放画面：SurfaceView 直接送显（HDR 需要），字幕叠在视频区域内；跟随页面创建和销毁，播放器跟随 playerId */
@OptIn(UnstableApi::class)
class NativeVideoView(
  context: Context,
  private val host: NativePlayerHost,
  private val playerId: Long,
  fit: NativeVideoFit,
) : PlatformView {
  private val root = FrameLayout(context).apply { setBackgroundColor(Color.BLACK) }
  private val frame = AspectRatioFrameLayout(context)
  val surfaceView = SurfaceView(context)
  val subtitleView = SubtitleView(context)
  private val textCueView = TextCueView(context)

  init {
    frame.addView(surfaceView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    frame.addView(subtitleView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    frame.addView(textCueView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    root.addView(frame, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT, Gravity.CENTER))
    host.backend(playerId)?.let {
      it.setVideoFit(fit)
      it.attach(this)
    }
  }

  fun setFit(fit: NativeVideoFit) {
    frame.resizeMode =
      if (fit == NativeVideoFit.COVER) {
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM
      } else {
        AspectRatioFrameLayout.RESIZE_MODE_FIT
      }
  }

  fun setCues(cues: List<Cue>) {
    val (text, others) = cues.partition(TextCueView::handles)
    textCueView.setCues(text)
    subtitleView.setCues(others)
  }

  /** [style] 为空时用与 Dart 一致的默认样式 */
  fun setSubtitleStyle(style: NativeSubtitleStyle?, typeface: Typeface?) {
    textCueView.setStyle(style, typeface)
    val opacity = style?.backgroundOpacity ?: TextCueView.DEFAULT_BACKGROUND_OPACITY
    subtitleView.setStyle(
      CaptionStyleCompat(
        style?.color?.toInt() ?: Color.WHITE,
        Color.argb((opacity.coerceIn(0.0, 1.0) * 255).toInt(), 0, 0, 0),
        Color.TRANSPARENT,
        CaptionStyleCompat.EDGE_TYPE_NONE,
        Color.TRANSPARENT,
        typeface,
      )
    )
    subtitleView.setFractionalTextSize(
      TextCueView.BASE_TEXT_SIZE_FRACTION * (style?.scale ?: 1.0).toFloat()
    )
    subtitleView.setBottomPaddingFraction(
      (style?.bottomMargin ?: TextCueView.DEFAULT_BOTTOM_MARGIN).toFloat()
    )
  }

  fun setAspectRatio(ratio: Float) = frame.setAspectRatio(ratio)

  fun setKeepScreenOn(value: Boolean) {
    root.keepScreenOn = value
  }

  override fun getView(): View = root

  override fun dispose() {
    host.backend(playerId)?.detach(this)
  }
}

class NativeVideoViewFactory(private val host: NativePlayerHost) :
  PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val params = args as? Map<*, *>
    val playerId = (params?.get("playerId") as? Number)?.toLong() ?: -1
    val fit = NativeVideoFit.ofRaw((params?.get("fit") as? Number)?.toInt() ?: 0) ?: NativeVideoFit.CONTAIN
    return NativeVideoView(context, host, playerId, fit)
  }

  companion object {
    const val VIEW_TYPE = "native_player/video"
  }
}
