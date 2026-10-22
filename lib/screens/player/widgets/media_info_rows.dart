import '../../../playback/domain/playback_domain.dart';

/// 内核专属项的展示顺序（原生侧的字典不一定保序），不在列表中的项按原顺序排在最后
const _detailOrder = [
  '杜比视界处理',
  '杜比视界转换',
  'HDR10 元数据',
  '视频编码',
  '分辨率',
  '帧率',
  '视频码率',
  '输出帧率',
  '丢帧(解码/输出)',
  '音频编码',
  '音频解码',
  '声道',
  '采样率',
  '音频码率',
  '播放路径',
  '字幕',
  '杜比视界解码器',
  '屏幕 HDR',
];

/// 媒体信息面板的行：各内核统一的通用项在前，内核专属项在后，键为展示名
Map<String, String> buildMediaInfoRows({
  required PlaybackEngineKind engine,
  required String engineReason,
  required VideoInfo videoInfo,
  required MediaDiagnostics diagnostics,
}) {
  final decoder = diagnostics.videoDecoder;
  final output = diagnostics.outputDynamicRange;
  final source = videoInfo.dynamicRange;
  final profile = videoInfo.dolbyVisionProfile;
  final details = diagnostics.details;
  return {
    '播放内核': engine.label,
    if (engineReason.isNotEmpty) '选择原因': engineReason,
    if (decoder != null) '视频解码': decoder,
    if (source != VideoDynamicRange.unknown)
      '动态范围':
          profile == null ? source.label : '${source.label} Profile $profile',
    if (output != null) 'HDR 送显': _hdrOutputText(output, source),
    for (final key in _detailOrder)
      if (details[key] case final value?) key: value,
    ...details,
  };
}

String _hdrOutputText(VideoDynamicRange output, VideoDynamicRange source) {
  if (output != VideoDynamicRange.sdr && output != VideoDynamicRange.unknown) {
    return '是（${output.label}）';
  }
  return source == VideoDynamicRange.sdr || source == VideoDynamicRange.unknown
      ? '否'
      : '否（已映射为 SDR）';
}
