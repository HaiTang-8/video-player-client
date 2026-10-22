package com.mediaserver.nativeplayer

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.mkv.MatroskaExtractor
import androidx.media3.extractor.text.SubtitleParser
import io.github.peerless2012.ass.media.AssHandler
import io.github.peerless2012.ass.media.extractor.AssMatroskaExtractor

/** MKV 改用 [AssMatroskaExtractor]：读取内嵌字体并把 ASS 交给 libass；字幕解析用 [subtitleParsers]，其余封装不变 */
@OptIn(UnstableApi::class)
class AssExtractorsFactory(
  private val delegate: ExtractorsFactory,
  private val subtitleParsers: SubtitleParser.Factory,
  private val ass: AssHandler,
) : ExtractorsFactory {
  override fun createExtractors(): Array<Extractor> = replace(delegate.createExtractors())

  override fun createExtractors(
    uri: Uri,
    responseHeaders: Map<String, List<String>>,
  ): Array<Extractor> = replace(delegate.createExtractors(uri, responseHeaders))

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

  private fun replace(extractors: Array<Extractor>): Array<Extractor> =
    extractors.map { if (it is MatroskaExtractor) AssMatroskaExtractor(subtitleParsers, ass) else it }.toTypedArray()
}
