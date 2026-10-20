import 'package:flutter/foundation.dart';

/// 引擎选择所需的运行环境信息，测试中可直接构造
class PlatformEnvironment {
  final TargetPlatform platform;

  const PlatformEnvironment({required this.platform});

  factory PlatformEnvironment.current() =>
      PlatformEnvironment(platform: defaultTargetPlatform);
}
