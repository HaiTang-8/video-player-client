import 'package:media_player/data/models/storage.dart';
import 'package:media_player/data/models/stream_info.dart';
import 'package:media_player/data/models/subtitle_info.dart';
import 'package:media_player/playback/session/playback_gateways.dart';
import 'package:media_player/playback/session/playback_item.dart';

class FakeSourceGateway implements PlaybackSourceGateway {
  @override
  String? serverUrl = 'http://media.local:8080';

  @override
  String? accessToken = 'token';

  String? downloadedFile;
  StreamInfo? streamInfo;
  Storage? storage;
  List<SubtitleInfo> subtitles = const [];
  final List<PlaybackItem> streamRequests = [];

  @override
  Future<String?> findDownloadedFile(PlaybackItem item) async => downloadedFile;

  @override
  Future<StreamInfo?> fetchStreamInfo(PlaybackItem item) async {
    streamRequests.add(item);
    return streamInfo;
  }

  @override
  Future<Storage?> findStorage(int storageId) async => storage;

  @override
  Future<List<SubtitleInfo>> listSubtitles({
    required int storageId,
    required String filePath,
  }) async => subtitles;
}

class FakeProgressGateway implements WatchProgressGateway {
  @override
  bool isAvailable = true;

  final List<String> uploads = [];
  final List<String> publishes = [];

  @override
  Future<void> upload(
    PlaybackItem item,
    Duration position,
    Duration duration,
  ) async => uploads.add('${position.inSeconds}/${duration.inSeconds}');

  @override
  void publish(PlaybackItem item, Duration position, Duration duration) =>
      publishes.add('${position.inSeconds}/${duration.inSeconds}');
}

SubtitleInfo subtitleInfo(String name, int score, {String? language}) =>
    SubtitleInfo(
      name: name,
      path: '/subs/$name',
      url: '/api/v1/subtitles/$name',
      language: language,
      score: score,
    );
