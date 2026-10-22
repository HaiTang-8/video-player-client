package com.mediaserver.nativeplayer

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.container.NalUnitUtil
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ForwardingTrackOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SniffFailure
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.text.SubtitleParser
import java.io.ByteArrayOutputStream
import java.io.EOFException

/**
 * 有些 MKV 只在 HEVC 码流里带杜比视界 RPU（NAL 62），封装里没有 dvcC，Media3 会把它当普通 HEVC 解码。
 * 这里查看前几个视频样本，发现 RPU 时在加载线程回调 [onRpu]
 */
@OptIn(UnstableApi::class)
class DolbyVisionProbeExtractorsFactory(
  private val delegate: ExtractorsFactory,
  private val onRpu: () -> Unit,
  /** 非空时保存每个视频样本里的 RPU（NAL 62），参数为样本时间和完整 NAL */
  private val onSampleRpu: ((Long, ByteArray) -> Unit)? = null,
) : ExtractorsFactory {
  override fun createExtractors(): Array<Extractor> =
    delegate.createExtractors().map(::wrap).toTypedArray()

  override fun createExtractors(
    uri: Uri,
    responseHeaders: Map<String, List<String>>,
  ): Array<Extractor> = delegate.createExtractors(uri, responseHeaders).map(::wrap).toTypedArray()

  // DefaultMediaSourceFactory 通过这几个方法配置字幕解析，要转给内层工厂
  override fun experimentalSetTextTrackTranscodingEnabled(
    textTrackTranscodingEnabled: Boolean
  ): ExtractorsFactory {
    delegate.experimentalSetTextTrackTranscodingEnabled(textTrackTranscodingEnabled)
    return this
  }

  override fun setSubtitleParserFactory(subtitleParserFactory: SubtitleParser.Factory): ExtractorsFactory {
    delegate.setSubtitleParserFactory(subtitleParserFactory)
    return this
  }

  override fun experimentalSetCodecsToParseWithinGopSampleDependencies(
    codecsToParseWithinGopSampleDependencies: Int
  ): ExtractorsFactory {
    delegate.experimentalSetCodecsToParseWithinGopSampleDependencies(codecsToParseWithinGopSampleDependencies)
    return this
  }

  private fun wrap(extractor: Extractor): Extractor = ProbingExtractor(extractor, onRpu, onSampleRpu)

  companion object {
    /** 视频格式没有颜色信息时（MKV 没写 Colour 元素），从 HEVC 的 SPS 取传输特性 */
    fun colorTransfer(format: Format): Int {
      format.colorInfo?.colorTransfer?.takeIf { it != Format.NO_VALUE }?.let { return it }
      if (format.sampleMimeType != MimeTypes.VIDEO_H265) return Format.NO_VALUE
      val data = format.initializationData.firstOrNull() ?: return Format.NO_VALUE
      val prefixFlags = BooleanArray(3)
      var vps: NalUnitUtil.H265VpsData? = null
      var start = NalUnitUtil.findNalUnit(data, 0, data.size, prefixFlags)
      while (start < data.size) {
        val next = NalUnitUtil.findNalUnit(data, start + 3, data.size, prefixFlags)
        val parsed =
          runCatching {
            when (NalUnitUtil.getH265NalUnitType(data, start)) {
              NalUnitUtil.H265_NAL_UNIT_TYPE_VPS -> {
                vps = NalUnitUtil.parseH265VpsNalUnit(data, start + 3, next)
                null
              }
              NalUnitUtil.H265_NAL_UNIT_TYPE_SPS ->
                NalUnitUtil.parseH265SpsNalUnit(data, start + 3, next, vps).colorTransfer
              else -> null
            }
          }
        if (parsed.isFailure) return Format.NO_VALUE
        parsed.getOrNull()?.let { return it }
        start = next
      }
      return Format.NO_VALUE
    }
  }
}

@OptIn(UnstableApi::class)
private class ProbingExtractor(
  private val delegate: Extractor,
  private val onRpu: () -> Unit,
  private val onSampleRpu: ((Long, ByteArray) -> Unit)?,
) : Extractor {
  override fun sniff(input: ExtractorInput): Boolean = delegate.sniff(input)

  override fun getSniffFailureDetails(): List<SniffFailure> = delegate.sniffFailureDetails

  override fun init(output: ExtractorOutput) = delegate.init(ProbingOutput(output, onRpu, onSampleRpu))

  override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int =
    delegate.read(input, seekPosition)

  override fun seek(position: Long, timeUs: Long) = delegate.seek(position, timeUs)

  override fun release() = delegate.release()

  override fun getUnderlyingImplementation(): Extractor = delegate.underlyingImplementation
}

@OptIn(UnstableApi::class)
private class ProbingOutput(
  private val delegate: ExtractorOutput,
  private val onRpu: () -> Unit,
  private val onSampleRpu: ((Long, ByteArray) -> Unit)?,
) : ExtractorOutput by delegate {
  override fun track(id: Int, type: Int): TrackOutput {
    val output = delegate.track(id, type)
    return if (type == C.TRACK_TYPE_VIDEO) RpuProbeTrackOutput(output, onRpu, onSampleRpu) else output
  }
}

@OptIn(UnstableApi::class)
private class RpuProbeTrackOutput(
  delegate: TrackOutput,
  private val onRpu: () -> Unit,
  private val onSampleRpu: ((Long, ByteArray) -> Unit)?,
) : ForwardingTrackOutput(delegate) {
  private var probing = false
  private var capturing = false
  private val pending = ByteArrayOutputStream()
  /** 封装声明了附加数据（如 dvcC 的 BlockAdditionMapping）时，样本还带非主体数据，计入 sampleMetadata 的 size */
  private var otherPartBytes = 0
  private var samples = 0
  private var zeros = 0
  private var expectHeader = false

  override fun format(format: Format) {
    probing = format.sampleMimeType == MimeTypes.VIDEO_H265 && samples < MAX_SAMPLES
    capturing =
      onSampleRpu != null &&
        (format.sampleMimeType == MimeTypes.VIDEO_H265 || format.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION)
    super.format(format)
  }

  override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean): Int =
    sampleData(input, length, allowEndOfInput, TrackOutput.SAMPLE_DATA_PART_MAIN)

  override fun sampleData(
    input: DataReader,
    length: Int,
    allowEndOfInput: Boolean,
    sampleDataPart: Int,
  ): Int {
    if (!probing && !capturing) return super.sampleData(input, length, allowEndOfInput, sampleDataPart)
    val buffer = ByteArray(length)
    val read = input.read(buffer, 0, length)
    if (read == C.RESULT_END_OF_INPUT) {
      if (allowEndOfInput) return C.RESULT_END_OF_INPUT
      throw EOFException()
    }
    if (probing) scan(buffer, 0, read)
    if (capturing) {
      if (sampleDataPart == TrackOutput.SAMPLE_DATA_PART_MAIN) pending.write(buffer, 0, read) else otherPartBytes += read
    }
    super.sampleData(ParsableByteArray(buffer, read), read, sampleDataPart)
    return read
  }

  override fun sampleData(data: ParsableByteArray, length: Int) =
    sampleData(data, length, TrackOutput.SAMPLE_DATA_PART_MAIN)

  override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
    if (probing) scan(data.data, data.position, length)
    if (capturing) {
      if (sampleDataPart == TrackOutput.SAMPLE_DATA_PART_MAIN) {
        pending.write(data.data, data.position, length)
      } else {
        otherPartBytes += length
      }
    }
    super.sampleData(data, length, sampleDataPart)
  }

  override fun sampleMetadata(
    timeUs: Long,
    flags: Int,
    size: Int,
    offset: Int,
    cryptoData: TrackOutput.CryptoData?,
  ) {
    super.sampleMetadata(timeUs, flags, size, offset, cryptoData)
    if (probing && ++samples >= MAX_SAMPLES) probing = false
    if (capturing) capture(timeUs, size, offset)
  }

  /** 样本数据是 Annex-B 格式；offset 字节属于下一个样本，留到下次 */
  private fun capture(timeUs: Long, size: Int, offset: Int) {
    val bytes = pending.toByteArray()
    pending.reset()
    val mainSize = size - otherPartBytes
    otherPartBytes = 0
    val end = bytes.size - offset
    val start = end - mainSize
    if (offset > 0) pending.write(bytes, end, offset)
    if (start < 0) return
    var i = start
    while (i + 3 < end) {
      if (bytes[i].toInt() == 0 && bytes[i + 1].toInt() == 0 && bytes[i + 2].toInt() == 1) {
        val header = i + 3
        if ((bytes[header].toInt() shr 1) and 0x3F == RPU_NAL_TYPE) {
          var next = header + 2
          while (next + 2 < end && !(bytes[next].toInt() == 0 && bytes[next + 1].toInt() == 0 && bytes[next + 2].toInt() == 1)) {
            next++
          }
          if (next + 2 >= end) next = end
          onSampleRpu?.invoke(timeUs, bytes.copyOfRange(header, next))
          return
        }
        i = header
      } else {
        i++
      }
    }
  }

  /** 找 00 00 01 起始码后的 NAL 头；起始码可能跨两次写入 */
  private fun scan(data: ByteArray, offset: Int, length: Int) {
    for (i in offset until offset + length) {
      val byte = data[i].toInt() and 0xFF
      if (expectHeader) {
        expectHeader = false
        if ((byte shr 1) and 0x3F == RPU_NAL_TYPE) {
          probing = false
          onRpu()
          return
        }
      }
      if (byte == 0) {
        zeros++
      } else {
        expectHeader = byte == 1 && zeros >= 2
        zeros = 0
      }
    }
  }

  private companion object {
    const val RPU_NAL_TYPE = 62
    const val MAX_SAMPLES = 10
  }
}
