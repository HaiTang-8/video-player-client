import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'aria2_service.dart';
import 'log_service.dart';

class Aria2Manager {
  static final Aria2Manager instance = Aria2Manager._();
  Aria2Manager._();

  Process? _process;
  Aria2Service? _service;
  String? _rpcSecret;
  int _rpcPort = 6800;
  DateTime? _startTime;

  bool get isRunning => _process != null;
  Aria2Service? get service => _service;
  int get rpcPort => _rpcPort;
  DateTime? get startTime => _startTime;

  static const _downloadUrls = {
    'windows': 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip',
    'macos_arm64': 'https://github.com/q741451/aria2c-macos-standalone-binary/releases/download/v1.0.0/aria2c-macos-arm64.tar.gz',
    'macos_x64': 'https://github.com/q741451/aria2c-macos-standalone-binary/releases/download/v1.0.0/aria2c-macos-x86_64.tar.gz',
  };

  Future<String> get _binDir async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/aria2';
  }

  Future<File> get _pidFile async {
    final dir = await _binDir;
    return File('$dir/aria2.pid');
  }

  Future<void> _cleanupStaleProcess() async {
    final pidFile = await _pidFile;
    if (!pidFile.existsSync()) return;
    try {
      final pid = int.tryParse(await pidFile.readAsString());
      if (pid != null) {
        Process.killPid(pid);
      }
    } catch (_) {}
    try {
      await pidFile.delete();
    } catch (_) {}
  }

  Future<String> get _binaryPath async {
    final binDir = await _binDir;
    if (Platform.isWindows) return '$binDir/aria2c.exe';
    return '$binDir/aria2c';
  }

  String? get _bundledBinaryPath {
    final executable = Platform.resolvedExecutable;
    if (Platform.isMacOS) {
      final appBundle = File(executable).parent.parent.path;
      final bundledPath = '$appBundle/Resources/aria2c';
      if (File(bundledPath).existsSync()) return bundledPath;
    } else if (Platform.isWindows) {
      final bundledPath = '${File(executable).parent.path}/aria2c.exe';
      if (File(bundledPath).existsSync()) return bundledPath;
    }
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

    // 清理可能残留的旧进程
    await _cleanupStaleProcess();

    // pid 文件位于 _binDir 下；如果使用 bundle 内置二进制文件，ensureBinary() 可能不会创建该目录。
    final binDir = await _binDir;
    await Directory(binDir).create(recursive: true);

    final binary = await _getEffectiveBinaryPath();
    if (!File(binary).existsSync()) {
      throw StateError('aria2 binary not found. Call ensureBinary() first.');
    }

    _rpcPort = port ?? await _findAvailablePort();
    _rpcSecret = DateTime.now().millisecondsSinceEpoch.toString();

    final downloadDir = await _getDownloadDir();

    final aria2Args = [
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

    // 记录启动阶段的输出，便于定位启动失败原因（尤其是 Windows）。
    final recentOutput = <String>[];
    void addOutput(String data, {required bool isError}) {
      for (final rawLine in data.split(RegExp(r'[\r\n]+'))) {
        final line = rawLine.trimRight();
        if (line.isEmpty) continue;
        final prefix = isError ? '[stderr] ' : '';
        recentOutput.add('$prefix$line');
        if (recentOutput.length > 30) {
          recentOutput.removeAt(0);
        }
      }
    }

    final pidFile = await _pidFile;

    Process process;
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        // 使用 wrapper 脚本实现同生共死，并把 aria2 PID 写入 pid 文件，便于 stop/cleanup。
        final parentPid = pid;
        final pidPath = pidFile.path.replaceAll('"', r'\"');
        final script = '''
"$binary" ${aria2Args.map((a) => '"$a"').join(' ')} &
ARIA2_PID=\$!
echo \$ARIA2_PID > "$pidPath"
trap "kill \$ARIA2_PID 2>/dev/null; exit" TERM INT
while kill -0 $parentPid 2>/dev/null && kill -0 \$ARIA2_PID 2>/dev/null; do
  sleep 1
done
kill \$ARIA2_PID 2>/dev/null
''';
        process = await Process.start('/bin/sh', ['-c', script]);
      } else if (Platform.isWindows) {
        // Windows: 使用 PowerShell 监控父进程，并把 aria2 PID 写入 pid 文件，便于 stop/cleanup。
        final parentPid = pid;
        String escPsSingle(String s) => s.replaceAll("'", "''");

        final normalizedBinary = binary.replaceAll('/', '\\');
        final normalizedPidPath = pidFile.path.replaceAll('/', '\\');
        final psBinary = escPsSingle(normalizedBinary);
        final psPidPath = escPsSingle(normalizedPidPath);
        final psArgs = aria2Args.map((a) => "'${escPsSingle(a)}'").join(', ');
        final script = '''
\$ErrorActionPreference = 'Stop'
try {
  \$args = @($psArgs)
  # Start-Process 不会自动为包含空格的参数加引号；这里手动为每个参数加双引号，
  # 避免像 user-agent / dir 等参数被拆分，导致 aria2 把多余 token 当成 URI。
  \$q = [char]34
  \$argLine = (\$args | ForEach-Object { \$q + \$_ + \$q }) -join ' '
  \$aria2 = Start-Process -FilePath '$psBinary' -ArgumentList \$argLine -PassThru -NoNewWindow
  Set-Content -Path '$psPidPath' -Value \$aria2.Id -NoNewline
  while ((Get-Process -Id $parentPid -ErrorAction SilentlyContinue) -and (Get-Process -Id \$aria2.Id -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 1
  }
  Stop-Process -Id \$aria2.Id -Force -ErrorAction SilentlyContinue
} catch {
  Write-Error \$_
  exit 1
}
''';
        final systemRoot = Platform.environment['SystemRoot'];
        final powershellExe = systemRoot != null && systemRoot.isNotEmpty
            ? '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
            : 'powershell';
        process = await Process.start(powershellExe, [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ]);
      } else {
        process = await Process.start(binary, aria2Args);
        await pidFile.writeAsString(process.pid.toString());
      }
    } catch (e) {
      // 启动阶段失败：确保状态干净，向上抛错。
      _process = null;
      _service = null;
      _startTime = null;
      rethrow;
    }

    _process = process;

    process.stdout.transform(const SystemEncoding().decoder).listen((data) {
      addOutput(data, isError: false);
      LogService.instance.debug('aria2', data.trim());
    });
    process.stderr.transform(const SystemEncoding().decoder).listen((data) {
      addOutput(data, isError: true);
      LogService.instance.warn('aria2', data.trim());
    });

    final exitCompleter = Completer<int>();
    unawaited(process.exitCode.then((code) async {
      if (!exitCompleter.isCompleted) exitCompleter.complete(code);
      if (_process == process) {
        _process = null;
        _service?.dispose();
        _service = null;
        _startTime = null;
      }
    }, onError: (Object e, StackTrace st) {
      if (!exitCompleter.isCompleted) exitCompleter.completeError(e, st);
    }));

    final service = Aria2Service(
      rpcUrl: 'http://127.0.0.1:$_rpcPort/jsonrpc',
      secret: _rpcSecret,
    );
    _service = service;

    // 等待 RPC 服务就绪
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (exitCompleter.isCompleted) {
        final exitCode = await exitCompleter.future;
        final logs = recentOutput.isEmpty ? '' : '\nRecent output:\n${recentOutput.join('\n')}';
        await stop();
        throw StateError('aria2 exited early (exitCode=$exitCode).$logs');
      }
      try {
        final version = await service.getVersion();
        LogService.instance.info('Aria2Manager', 'Started aria2 $version on port $_rpcPort');
        _startTime = DateTime.now();
        return;
      } catch (_) {
        LogService.instance.debug('Aria2Manager', 'Waiting for aria2 RPC... ($i)');
      }
    }
    final logs = recentOutput.isEmpty ? '' : '\nRecent output:\n${recentOutput.join('\n')}';
    await stop();
    throw StateError('aria2 RPC failed to start.$logs');
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
    final service = _service;
    _service = null;
    _startTime = null;

    int? aria2Pid;
    final pidFile = await _pidFile;
    try {
      if (await pidFile.exists()) {
        aria2Pid = int.tryParse(await pidFile.readAsString());
      }
    } catch (_) {}

    // 尝试优雅关闭 aria2（避免 wrapper 被 kill 后残留子进程）。
    if (service != null) {
      try {
        await service.shutdown();
      } catch (_) {}
      service.dispose();
    }

    // 兜底：读取 pid 文件尝试杀掉 aria2（pid 文件记录的是 aria2 PID）。
    try {
      if (aria2Pid != null) {
        try {
          Process.killPid(aria2Pid);
        } catch (_) {}
      }
      if (await pidFile.exists()) await pidFile.delete();
    } catch (_) {}

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
