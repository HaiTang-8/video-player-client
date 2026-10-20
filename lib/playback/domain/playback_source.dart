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

  const factory ExternalSubtitle.data(String text, {required String title}) =
      ExternalSubtitleData;
}

final class ExternalSubtitleData extends ExternalSubtitle {
  final String text;
  final String title;

  const ExternalSubtitleData(this.text, {required this.title});
}
