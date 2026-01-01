import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'aria2_service.dart';

class Aria2Manager {
  static final Aria2Manager instance = Aria2Manager._();
  Aria2Manager._();

  Process? _process;
  Aria2Service? _service;
  String? _rpcSecret;
  int _rpcPort = 6800;

  bool get isRunning => _process != null;
  Aria2Service? get service => _service;

  static const _downloadUrls = {
    'windows': 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip',
    'macos_arm64': 'https://github.com/q741451/aria2c-macos-standalone-binary/releases/download/v1.0.0/aria2c-macos-arm64.tar.gz',
    'macos_x64': 'https://github.com/q741451/aria2c-macos-standalone-binary/releases/download/v1.0.0/aria2c-macos-x86_64.tar.gz',
  };

  Future<String> get _binDir async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/aria2';
  }

  Future<String> get _binaryPath async {
    final binDir = await _binDir;
    if (Platform.isWindows) return '$binDir/aria2c.exe';
    return '$binDir/aria2c';
  }

  /// 获取 bundle 中的 aria2c 路径 (macOS)
  String? get _bundledBinaryPath {
    if (!Platform.isMacOS) return null;
    final executable = Platform.resolvedExecutable;
    final appBundle = File(executable).parent.parent.path;
    final bundledPath = '$appBundle/Resources/aria2c';
    if (File(bundledPath).existsSync()) return bundledPath;
    return null;
  }

  Future<bool> isAvailable() async {
    if (!Platform.isWindows && !Platform.isMacOS) return false;
    // 优先检查 bundle
    if (_bundledBinaryPath != null) return true;
    final path = await _binaryPath;
    return File(path).existsSync();
  }

  Future<String> _getEffectiveBinaryPath() async {
    // 优先使用 bundle 中的
    final bundled = _bundledBinaryPath;
    if (bundled != null) return bundled;
    return _binaryPath;
  }

  Future<void> ensureBinary({void Function(double)? onProgress}) async {
    if (await isAvailable()) return;

    final binDir = await _binDir;
    await Directory(binDir).create(recursive: true);

    String url;
    if (Platform.isWindows) {
      url = _downloadUrls['windows']!;
    } else if (Platform.isMacOS) {
      final arch = await _getMacArch();
      url = arch == 'arm64' ? _downloadUrls['macos_arm64']! : _downloadUrls['macos_x64']!;
    } else {
      throw UnsupportedError('Unsupported platform');
    }

    final tempFile = '$binDir/aria2_temp${Platform.isWindows ? ".zip" : ".tar.gz"}';
    final dio = Dio();

    try {
      await dio.download(
        url,
        tempFile,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      await _extractBinary(tempFile, binDir);
      await File(tempFile).delete();
    } finally {
      dio.close();
    }
  }

  Future<String> _getMacArch() async {
    final result = await Process.run('uname', ['-m']);
    return result.stdout.toString().trim();
  }

  Future<void> _extractBinary(String archivePath, String destDir) async {
    final bytes = await File(archivePath).readAsBytes();
    final binaryPath = await _binaryPath;

    if (Platform.isWindows) {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.name.endsWith('aria2c.exe')) {
          await File(binaryPath).writeAsBytes(file.content as List<int>);
          break;
        }
      }
    } else {
      final gzData = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(gzData);
      for (final file in archive) {
        if (file.name.endsWith('aria2c') || file.name == 'aria2c') {
          await File(binaryPath).writeAsBytes(file.content as List<int>);
          await Process.run('chmod', ['+x', binaryPath]);
          // 移除 macOS quarantine 属性
          await Process.run('xattr', ['-d', 'com.apple.quarantine', binaryPath]);
          break;
        }
      }
    }
  }

  Future<void> start({int? port}) async {
    if (_process != null) return;

    final binary = await _getEffectiveBinaryPath();
    if (!File(binary).existsSync()) {
      throw StateError('aria2 binary not found. Call ensureBinary() first.');
    }

    _rpcPort = port ?? await _findAvailablePort();
    _rpcSecret = DateTime.now().millisecondsSinceEpoch.toString();

    final downloadDir = await _getDownloadDir();

    final args = [
      '--enable-rpc',
      '--rpc-listen-port=$_rpcPort',
      '--rpc-secret=$_rpcSecret',
      '--dir=$downloadDir',
      '--continue=true',
      '--max-concurrent-downloads=3',
      '--split=8',
      '--max-connection-per-server=8',
      '--min-split-size=1M',
      '--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57',
    ];

    _process = await Process.start(binary, args);
    _process!.stdout.transform(const SystemEncoding().decoder).listen((data) {
      debugPrint('[aria2] $data');
    });
    _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
      debugPrint('[aria2 err] $data');
    });
    _process!.exitCode.then((_) {
      _process = null;
      _service = null;
    });

    _service = Aria2Service(
      rpcUrl: 'http://127.0.0.1:$_rpcPort/jsonrpc',
      secret: _rpcSecret,
    );

    // 等待 RPC 服务就绪
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        final version = await _service!.getVersion();
        debugPrint('[Aria2Manager] Started aria2 $version on port $_rpcPort');
        return;
      } catch (_) {
        debugPrint('[Aria2Manager] Waiting for aria2 RPC... ($i)');
      }
    }
    await stop();
    throw StateError('aria2 RPC failed to start');
  }

  Future<int> _findAvailablePort() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    return port;
  }

  Future<String> _getDownloadDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  Future<void> stop() async {
    _service?.dispose();
    _service = null;
    _process?.kill();
    _process = null;
  }

  Future<bool> healthCheck() async {
    if (_service == null) return false;
    try {
      await _service!.getVersion();
      return true;
    } catch (_) {
      return false;
    }
  }
}
