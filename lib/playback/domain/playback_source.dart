class PlaybackSource {
  final String url;
  final Map<String, String> httpHeaders;
  final bool isLocalFile;

  const PlaybackSource.network(this.url, {this.httpHeaders = const {}})
    : isLocalFile = false;

  const PlaybackSource.localFile(this.url)
    : httpHeaders = const {},
      isLocalFile = true;
}

sealed class ExternalSubtitle {
  const ExternalSubtitle();

  const factory ExternalSubtitle.data(
    String text, {
    required String title,
    String? formatHint,
  }) = ExternalSubtitleData;
}

final class ExternalSubtitleData extends ExternalSubtitle {
  final String text;
  final String title;

  /// 字幕文件扩展名（如 srt、ass），供需要按格式解析的引擎使用
  final String? formatHint;

  const ExternalSubtitleData(this.text, {required this.title, this.formatHint});
}
