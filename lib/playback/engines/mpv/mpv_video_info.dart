import '../../domain/playback_domain.dart';

abstract final class MpvVideoInfo {
  /// [gamma] 为 mpv 的 video-params/gamma；杜比视界的判断优先于 gamma
  static VideoInfo resolve({
    String? gamma,
    bool dolbyVision = false,
    int? dolbyVisionProfile,
  }) {
    if (dolbyVision || dolbyVisionProfile != null) {
      return VideoInfo(
        dynamicRange: VideoDynamicRange.dolbyVision,
        dolbyVisionProfile: dolbyVisionProfile,
      );
    }
    return VideoInfo(
      dynamicRange: switch (gamma) {
        null || '' => VideoDynamicRange.unknown,
        'pq' => VideoDynamicRange.hdr10,
        'hlg' => VideoDynamicRange.hlg,
        _ => VideoDynamicRange.sdr,
      },
    );
  }

  /// Profile 5 的 IPT-PQ-c2 没有对应的 VUI 取值，解码器给出的色彩参数都是 auto
  static bool looksLikeProfile5({
    required String decoderColormatrix,
    required String decoderGamma,
  }) => decoderColormatrix == 'auto' && decoderGamma == 'auto';
}
