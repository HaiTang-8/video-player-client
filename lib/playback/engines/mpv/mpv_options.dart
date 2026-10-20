/// 按场景组合 mpv 属性，保持设置顺序
class MpvOptions {
  final Map<String, String> _properties = {};

  /// HTTP 流自动重连（暂停后恢复播放时需要）与网络超时
  MpvOptions networkResilience() {
    _properties
      ..['stream-lavf-o'] =
          'reconnect=1,reconnect_streamed=1,reconnect_at_eof=1,'
          'reconnect_on_network_error=1,reconnect_on_http_error=5xx,'
          'reconnect_delay_max=5'
      ..['network-timeout'] = '30';
    return this;
  }

  MpvOptions streamCache() {
    _properties
      ..['cache'] = 'yes'
      ..['demuxer-max-back-bytes'] = '64MiB'
      ..['cache-secs'] = '30'
      ..['cache-pause'] = 'yes'
      ..['cache-pause-wait'] = '3';
    return this;
  }

  MpvOptions set(String name, String value) {
    _properties[name] = value;
    return this;
  }

  Map<String, String> build() => Map.unmodifiable(_properties);
}
