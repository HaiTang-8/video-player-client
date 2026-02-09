/// 应用常量
class AppConstants {
  AppConstants._();

  static const String appName = '观影';

  // GitHub 更新配置
  static const String githubOwner = 'HaiTang-8';
  static const String githubRepo = 'video-player-client';

  // 更新代理 API 路径
  static const String updateCheckPath = '/api/v1/update/check';
  static const String updateDownloadPath = '/api/v1/update/download';
  static const String updateAppcastPath = '/api/v1/update/appcast.xml';

  // 本地存储 Key
  static const String serverUrlKey = 'server_url'; // 兼容旧版
  static const String serverListKey = 'server_list';
  static const String currentServerIdKey = 'current_server_id';
  static const String themeKey = 'theme_mode';
  static const String localeKey = 'locale';
  static const String seekDurationKey = 'playback_seek_duration';
  static const String playbackSpeedKey = 'playback_speed';
  static const String watchHistoryMergeEnabledKey = 'watch_history_merge_enabled';

  // aria2 配置
  static const String aria2EnabledKey = 'aria2_enabled';
  static const String aria2RpcUrlKey = 'aria2_rpc_url';
  static const String aria2RpcSecretKey = 'aria2_rpc_secret';

  // 多线程下载配置
  static const String downloadThreadCountKey = 'download_thread_count';
  static const String downloadMultiThreadEnabledKey = 'download_multi_thread_enabled';
  static const String downloadEngineKey = 'download_engine';

  // 认证 token（按 serverId 隔离）
  static String authTokensKey(String serverId) => 'auth_tokens_$serverId';
  static String authUserKey(String serverId) => 'auth_user_$serverId';

  // 桌面端平滑滚动
  static const String smoothScrollEnabledKey = 'smooth_scroll_enabled';

  // 分页
  static const int defaultPageSize = 20;

  // 图片尺寸
  static const String posterSizeSmall = 'w185';
  static const String posterSizeMedium = 'w342';
  static const String posterSizeLarge = 'w500';
  static const String posterSizeOriginal = 'original';

  static const String backdropSizeSmall = 'w300';
  static const String backdropSizeMedium = 'w780';
  static const String backdropSizeLarge = 'w1280';
  static const String backdropSizeOriginal = 'original';
}
