package com.mediaserver.nativeplayer

import android.graphics.Bitmap
import android.graphics.Rect
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.text.Cue
import androidx.media3.common.util.Consumer
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.extractor.text.CuesWithTiming
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import androidx.media3.extractor.text.SubtitleParser
import java.util.zip.Inflater
import kotlin.math.min

/** PGS 交给 [PgsSubtitleParser]，其余格式用 Media3 默认的解析器 */
@OptIn(UnstableApi::class)
class PgsSubtitleParserFactory(
  private val delegate: SubtitleParser.Factory = DefaultSubtitleParserFactory(),
) : SubtitleParser.Factory {
  override fun supportsFormat(format: Format): Boolean = delegate.supportsFormat(format)

  override fun getCueReplacementBehavior(format: Format): Int =
    delegate.getCueReplacementBehavior(format)

  override fun create(format: Format): SubtitleParser =
    if (format.sampleMimeType == MimeTypes.APPLICATION_PGS) PgsSubtitleParser() else delegate.create(format)
}

/**
 * Media3 自带的 PgsParser 每个显示集只取第一个对象的位置和最后一个对象的图像。这里按 id 保存对象和调色板，
 * 每个组合对象各出一个图像 cue（含裁剪）；同一 epoch 内后续显示集可以复用之前的对象和调色板
 */
@OptIn(UnstableApi::class)
class PgsSubtitleParser : SubtitleParser {
  private class PgsObject(val width: Int, val height: Int, val data: ParsableByteArray)

  private class Composition(val objectId: Int, val x: Int, val y: Int, val crop: Rect?)

  private val buffer = ParsableByteArray()
  private val inflated = ParsableByteArray()
  private var inflater: Inflater? = null
  private val palettes = HashMap<Int, IntArray>()
  private val objects = HashMap<Int, PgsObject>()
  private var compositions = emptyList<Composition>()
  private var planeWidth = 0
  private var planeHeight = 0
  private var paletteId = 0

  override fun getCueReplacementBehavior(): Int = Format.CUE_REPLACEMENT_BEHAVIOR_REPLACE

  override fun reset() {
    palettes.clear()
    objects.clear()
    compositions = emptyList()
  }

  override fun parse(
    data: ByteArray,
    offset: Int,
    length: Int,
    outputOptions: SubtitleParser.OutputOptions,
    output: Consumer<CuesWithTiming>,
  ) {
    buffer.reset(data, offset + length)
    buffer.position = offset
    val zlib = inflater ?: Inflater().also { inflater = it }
    if (Util.maybeInflate(buffer, inflated, zlib)) buffer.reset(inflated.data, inflated.limit())
    val cues = ArrayList<Cue>()
    while (buffer.bytesLeft() >= 3) {
      val type = buffer.readUnsignedByte()
      val size = buffer.readUnsignedShort()
      val next = buffer.position + size
      if (next > buffer.limit()) break
      when (type) {
        SEGMENT_PALETTE -> readPalette(size)
        SEGMENT_OBJECT -> readObject(size)
        SEGMENT_COMPOSITION -> readComposition(size)
        SEGMENT_END -> {
          cues.clear()
          compositions.mapNotNullTo(cues, ::buildCue)
        }
      }
      buffer.position = next
    }
    output.accept(CuesWithTiming(cues, C.TIME_UNSET, C.TIME_UNSET))
  }

  private fun readComposition(size: Int) {
    if (size < 11) return
    planeWidth = buffer.readUnsignedShort()
    planeHeight = buffer.readUnsignedShort()
    buffer.skipBytes(3) // 帧率、组合编号
    val state = buffer.readUnsignedByte()
    buffer.skipBytes(1) // 仅更新调色板标志
    paletteId = buffer.readUnsignedByte()
    val count = buffer.readUnsignedByte()
    if (state and STATE_EPOCH_START != 0) {
      palettes.clear()
      objects.clear()
    }
    val end = buffer.position + size - 11
    val result = ArrayList<Composition>(count)
    repeat(count) {
      if (end - buffer.position < 8) return@repeat
      val objectId = buffer.readUnsignedShort()
      buffer.skipBytes(1) // 窗口 id
      val cropped = buffer.readUnsignedByte() and 0x40 != 0
      val x = buffer.readUnsignedShort()
      val y = buffer.readUnsignedShort()
      val crop =
        if (cropped && end - buffer.position >= 8) {
          val left = buffer.readUnsignedShort()
          val top = buffer.readUnsignedShort()
          Rect(left, top, left + buffer.readUnsignedShort(), top + buffer.readUnsignedShort())
        } else {
          null
        }
      result += Composition(objectId, x, y, crop)
    }
    compositions = result
  }

  private fun readPalette(size: Int) {
    if (size < 2 || (size - 2) % 5 != 0) return
    val colors = palettes.getOrPut(buffer.readUnsignedByte()) { IntArray(256) }
    buffer.skipBytes(1) // 版本
    repeat((size - 2) / 5) {
      val index = buffer.readUnsignedByte()
      val y = buffer.readUnsignedByte()
      val cr = buffer.readUnsignedByte()
      val cb = buffer.readUnsignedByte()
      val a = buffer.readUnsignedByte()
      val r = (y + 1.40200 * (cr - 128)).toInt().coerceIn(0, 255)
      val g = (y - 0.34414 * (cb - 128) - 0.71414 * (cr - 128)).toInt().coerceIn(0, 255)
      val b = (y + 1.77200 * (cb - 128)).toInt().coerceIn(0, 255)
      colors[index] = (a shl 24) or (r shl 16) or (g shl 8) or b
    }
  }

  private fun readObject(size: Int) {
    if (size < 4) return
    val id = buffer.readUnsignedShort()
    buffer.skipBytes(1) // 版本
    val first = buffer.readUnsignedByte() and 0x80 != 0
    var remaining = size - 4
    if (first) {
      if (remaining < 7) return
      val dataLength = buffer.readUnsignedInt24()
      if (dataLength < 4) return
      val width = buffer.readUnsignedShort()
      val height = buffer.readUnsignedShort()
      objects[id] = PgsObject(width, height, ParsableByteArray(dataLength - 4))
      remaining -= 7
    }
    val target = objects[id]?.data ?: return
    val count = min(remaining, target.bytesLeft())
    if (count <= 0) return
    buffer.readBytes(target.data, target.position, count)
    target.position += count
  }

  private fun buildCue(composition: Composition): Cue? {
    val obj = objects[composition.objectId] ?: return null
    val colors = palettes[paletteId] ?: return null
    if (planeWidth == 0 || planeHeight == 0 || obj.width == 0 || obj.height == 0) return null
    if (obj.data.limit() == 0 || obj.data.bytesLeft() != 0) return null
    var bitmap =
      Bitmap.createBitmap(decode(obj, colors), obj.width, obj.height, Bitmap.Config.ARGB_8888)
    composition.crop?.let { crop ->
      if (!crop.intersect(0, 0, obj.width, obj.height) || crop.isEmpty) return null
      bitmap = Bitmap.createBitmap(bitmap, crop.left, crop.top, crop.width(), crop.height())
    }
    return Cue.Builder()
      .setBitmap(bitmap)
      .setPosition(composition.x.toFloat() / planeWidth)
      .setPositionAnchor(Cue.ANCHOR_TYPE_START)
      .setLine(composition.y.toFloat() / planeHeight, Cue.LINE_TYPE_FRACTION)
      .setLineAnchor(Cue.ANCHOR_TYPE_START)
      .setSize(bitmap.width.toFloat() / planeWidth)
      .setBitmapHeight(bitmap.height.toFloat() / planeHeight)
      .build()
  }

  /** 游程编码：非 0 字节是单个像素；0 后跟标志字节，0 表示行尾，否则为长度（0x40 时 14 位）和颜色（0x80 时另读一个字节） */
  private fun decode(obj: PgsObject, colors: IntArray): IntArray {
    val data = obj.data
    data.position = 0
    val pixels = IntArray(obj.width * obj.height)
    var i = 0
    while (i < pixels.size && data.bytesLeft() > 0) {
      val index = data.readUnsignedByte()
      if (index != 0) {
        pixels[i++] = colors[index]
        continue
      }
      if (data.bytesLeft() == 0) break
      val flags = data.readUnsignedByte()
      if (flags == 0) continue
      val extra = (if (flags and 0x40 != 0) 1 else 0) + (if (flags and 0x80 != 0) 1 else 0)
      if (data.bytesLeft() < extra) break
      var run = flags and 0x3F
      if (flags and 0x40 != 0) run = (run shl 8) or data.readUnsignedByte()
      val color = if (flags and 0x80 != 0) colors[data.readUnsignedByte()] else colors[0]
      val end = min(i + run, pixels.size)
      pixels.fill(color, i, end)
      i = end
    }
    data.position = data.limit()
    return pixels
  }

  private companion object {
    const val SEGMENT_PALETTE = 0x14
    const val SEGMENT_OBJECT = 0x15
    const val SEGMENT_COMPOSITION = 0x16
    const val SEGMENT_END = 0x80
    const val STATE_EPOCH_START = 0x80
  }
}
