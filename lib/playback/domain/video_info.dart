import 'package:flutter/foundation.dart';

enum VideoDynamicRange {
  unknown('未知'),
  sdr('SDR'),
  hdr10('HDR10'),
  hlg('HLG'),
  dolbyVision('杜比视界');

  const VideoDynamicRange(this.label);

  final String label;
}

@immutable
class VideoInfo {
  final VideoDynamicRange dynamicRange;

  /// 杜比视界 profile，未知时为 null
  final int? dolbyVisionProfile;

  const VideoInfo({
    this.dynamicRange = VideoDynamicRange.unknown,
    this.dolbyVisionProfile,
  });

  @override
  bool operator ==(Object other) =>
      other is VideoInfo &&
      other.dynamicRange == dynamicRange &&
      other.dolbyVisionProfile == dolbyVisionProfile;

  @override
  int get hashCode => Object.hash(dynamicRange, dolbyVisionProfile);
}
