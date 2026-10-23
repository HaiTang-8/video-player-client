package com.mediaserver.nativeplayer

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.StaticLayout
import android.text.TextPaint
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.text.Cue
import androidx.media3.common.util.UnstableApi

/**
 * 默认位置的文本字幕：无描边无阴影，按行画半透明圆角底框（Media3 的背景只能逐行贴边且不能圆角）。
 * 带定位的文本和位图字幕仍由 SubtitleView 绘制
 */
@OptIn(UnstableApi::class)
class TextCueView(context: Context) : View(context) {
  private var cues: List<Cue> = emptyList()
  private var style: NativeSubtitleStyle? = null
  private var typeface: Typeface? = null
  private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
  private val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG)
  private val boxPath = Path()

  fun setCues(cues: List<Cue>) {
    this.cues = cues
    invalidate()
  }

  fun setStyle(style: NativeSubtitleStyle?, typeface: Typeface?) {
    this.style = style
    this.typeface = typeface
    invalidate()
  }

  override fun onDraw(canvas: Canvas) {
    if (cues.isEmpty() || width == 0 || height == 0) return
    val text = SpannableStringBuilder()
    for (cue in cues) {
      val cueText = cue.text ?: continue
      if (text.isNotEmpty()) text.append('\n')
      text.append(cueText)
    }
    if (text.isBlank()) return

    val em = height * BASE_TEXT_SIZE_FRACTION * (style?.scale ?: 1.0).toFloat()
    val padH = em * 0.4f
    val padV = em * 0.18f
    textPaint.textSize = em
    textPaint.color = style?.color?.toInt() ?: Color.WHITE
    textPaint.typeface = typeface
    val maxWidth = (width * 0.9f - padH * 2).toInt().coerceAtLeast(1)
    val layout =
      StaticLayout.Builder.obtain(text, 0, text.length, textPaint, maxWidth)
        .setAlignment(Layout.Alignment.ALIGN_CENTER)
        .setIncludePad(false)
        .build()
    val margin = (style?.bottomMargin ?: DEFAULT_BOTTOM_MARGIN).toFloat()

    canvas.save()
    canvas.translate((width - maxWidth) / 2f, height * (1 - margin) - layout.height)
    val opacity = (style?.backgroundOpacity ?: DEFAULT_BACKGROUND_OPACITY).coerceIn(0.0, 1.0)
    if (opacity > 0) {
      boxPath.reset()
      val radius = em * 0.25f
      for (line in 0 until layout.lineCount) {
        val left = layout.getLineLeft(line)
        val right = layout.getLineRight(line)
        if (right <= left) continue
        boxPath.addRoundRect(
          left - padH,
          layout.getLineTop(line) - padV,
          right + padH,
          layout.getLineBottom(line) + padV,
          radius,
          radius,
          Path.Direction.CW,
        )
      }
      boxPaint.color = Color.argb((opacity * 255).toInt(), 0, 0, 0)
      canvas.drawPath(boxPath, boxPaint)
    }
    layout.draw(canvas)
    canvas.restore()
  }

  companion object {
    /** 标准字号占视频高度的比例，与 mpv 叠加层一致 */
    const val BASE_TEXT_SIZE_FRACTION = 0.055f
    const val DEFAULT_BACKGROUND_OPACITY = 0.6
    const val DEFAULT_BOTTOM_MARGIN = 0.06

    /** 没有指定位置的文本 cue 由本视图绘制 */
    fun handles(cue: Cue) = cue.bitmap == null && cue.text != null && cue.line == Cue.DIMEN_UNSET
  }
}
