import '../../data/models/storage.dart';
import '../../data/models/stream_info.dart';
import '../../data/models/subtitle_info.dart';
import 'playback_item.dart';

/// 会话层读取播放源所需的数据访问
abstract interface class PlaybackSourceGateway {
  String? get serverUrl;
  String? get accessToken;

  /// 已下载且文件存在时返回本地路径
  Future<String?> findDownloadedFile(PlaybackItem item);
  Future<StreamInfo?> fetchStreamInfo(PlaybackItem item);
  Future<Storage?> findStorage(int storageId);
  Future<List<SubtitleInfo>> listSubtitles({
    required int storageId,
    required String filePath,
  });
}

/// 字幕偏移的本地保存：剧集按整部剧共用，电影按单部保存
abstract interface class SubtitleDelayStore {
  Duration read(PlaybackItem item);

  /// [delay] 为零时删除记录
  Future<void> write(PlaybackItem item, Duration delay);
}

/// 观看进度的上报（服务端）与发布（本地状态）
abstract interface class WatchProgressGateway {
  bool get isAvailable;
  Future<void> upload(PlaybackItem item, Duration position, Duration duration);
  void publish(PlaybackItem item, Duration position, Duration duration);
}
