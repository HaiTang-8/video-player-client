import 'package:media_kit/media_kit.dart';

/// 从 mpv 属性读取媒体信息面板中的视频、音频部分
abstract final class MpvDiagnostics {
  static Future<Map<String, String>> read(NativePlayer platform) async {
    final info = <String, String>{};

    final videoCodec = await platform.getProperty('video-codec');
    final videoWidth = await platform.getProperty('video-params/w');
    final videoHeight = await platform.getProperty('video-params/h');
    final fps = await platform.getProperty('container-fps');
    final videoBitrate = await platform.getProperty('video-bitrate');
    final hwdec = await platform.getProperty('hwdec-current');
    final outputFps = await platform.getProperty('estimated-vf-fps');
    final decoderDrops = await platform.getProperty('decoder-frame-drop-count');
    final outputDrops = await platform.getProperty('frame-drop-count');

    if (videoCodec.isNotEmpty) info['视频编码'] = videoCodec;
    if (videoWidth.isNotEmpty && videoHeight.isNotEmpty) {
      info['分辨率'] = '${videoWidth}x$videoHeight';
    }
    if (fps.isNotEmpty) {
      final fpsVal = double.tryParse(fps);
      info['帧率'] = fpsVal != null ? '${fpsVal.toStringAsFixed(2)} fps' : fps;
    }
    if (videoBitrate.isNotEmpty) {
      final br = int.tryParse(videoBitrate);
      if (br != null && br > 0) {
        info['视频码率'] = '${(br / 1000).toStringAsFixed(0)} kbps';
      }
    }
    if (hwdec.isNotEmpty && hwdec != 'no') info['硬解'] = hwdec;
    final outputFpsVal = double.tryParse(outputFps);
    if (outputFpsVal != null) {
      info['输出帧率'] = '${outputFpsVal.toStringAsFixed(2)} fps';
    }
    info['丢帧(解码/输出)'] =
        '${decoderDrops.isEmpty ? '0' : decoderDrops} / '
        '${outputDrops.isEmpty ? '0' : outputDrops}';

    final audioCodec = await platform.getProperty('audio-codec-name');
    final channels = await platform.getProperty('audio-params/channel-count');
    final sampleRate = await platform.getProperty('audio-params/samplerate');
    final audioBitrate = await platform.getProperty('audio-bitrate');

    if (audioCodec.isNotEmpty) info['音频编码'] = audioCodec;
    if (channels.isNotEmpty) {
      final ch = int.tryParse(channels);
      info['声道'] = ch == 2 ? '立体声' : (ch == 1 ? '单声道' : '$ch 声道');
    }
    if (sampleRate.isNotEmpty) {
      final sr = int.tryParse(sampleRate);
      info['采样率'] =
          sr != null ? '${(sr / 1000).toStringAsFixed(1)} kHz' : sampleRate;
    }
    if (audioBitrate.isNotEmpty) {
      final br = int.tryParse(audioBitrate);
      if (br != null && br > 0) {
        info['音频码率'] = '${(br / 1000).toStringAsFixed(0)} kbps';
      }
    }
    return info;
  }

  static Future<double?> cacheSpeed(NativePlayer platform) async =>
      double.tryParse(await platform.getProperty('cache-speed'));
}
