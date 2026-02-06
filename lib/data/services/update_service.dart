import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import 'log_service.dart';

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}

class ReleaseInfo {
  final String version;
  final String? releaseNotes;
  final String downloadUrl;
  final String fileName;
  final int? fileSize;
  final String? checksum;

  ReleaseInfo({
    required this.version,
    this.releaseNotes,
    required this.downloadUrl,
    required this.fileName,
    this.fileSize,
    this.checksum,
  });
}

class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  // 可信下载域名白名单
  static const _trustedDomains = ['github.com', 'githubusercontent.com'];

  String? _serverUrl;

  void _validateServerUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw ArgumentError('Invalid server URL: $url');
    }
  }

  bool _isTrustedDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    if (_trustedDomains.any((d) => uri.host == d || uri.host.endsWith('.$d'))) {
      return true;
    }

    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      final serverUri = Uri.tryParse(_serverUrl!);
      if (serverUri != null && uri.host == serverUri.host) {
        return true;
      }
    }

    return false;
  }

  Future<void> init(String? serverUrl) async {
    if (serverUrl != null && serverUrl.isNotEmpty) {
      _validateServerUrl(serverUrl);
    }
    _serverUrl = serverUrl;
    if (Platform.isMacOS && serverUrl != null && serverUrl.isNotEmpty) {
      final feedURL = '$serverUrl${AppConstants.updateAppcastPath}';
      await autoUpdater.setFeedURL(feedURL);
      await autoUpdater.setScheduledCheckInterval(3600);
      autoUpdater.checkForUpdates(inBackground: true);
    }
  }

  void updateServerUrl(String? serverUrl) {
    if (serverUrl != null && serverUrl.isNotEmpty) {
      _validateServerUrl(serverUrl);
    }
    _serverUrl = serverUrl;
    if (Platform.isMacOS && serverUrl != null && serverUrl.isNotEmpty) {
      final feedURL = '$serverUrl${AppConstants.updateAppcastPath}';
      autoUpdater.setFeedURL(feedURL);
    }
  }

  Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<ReleaseInfo?> checkForUpdate() async {
    if (_serverUrl == null || _serverUrl!.isEmpty) {
      LogService.instance.log('warn', 'UpdateService', 'No server URL configured');
      return null;
    }

    try {
      final url = Uri.parse('$_serverUrl${AppConstants.updateCheckPath}');
      final response = await http.get(url, headers: {
        'Accept': 'application/json',
      });

      if (response.statusCode != 200) {
        LogService.instance.log('error', 'UpdateService', 'API error: ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        LogService.instance.log('error', 'UpdateService', 'API returned error: ${json['error']}');
        return null;
      }

      final data = json['data'] as Map<String, dynamic>;
      final latestVersion = (data['version'] as String?) ??
          (data['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');

      if (latestVersion == null) return null;

      final currentVersion = await getCurrentVersion();
      if (!_isNewerVersion(latestVersion, currentVersion)) {
        return null;
      }

      final assets = data['assets'] as List<dynamic>? ?? [];
      final assetPattern = _getAssetPattern();

      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (assetPattern.hasMatch(name)) {
          final downloadPath = asset['download_url'] as String;
          final downloadUrl = downloadPath.startsWith('http')
              ? downloadPath
              : '$_serverUrl$downloadPath';

          return ReleaseInfo(
            version: latestVersion,
            releaseNotes: data['body'] as String?,
            downloadUrl: downloadUrl,
            fileName: name,
            fileSize: asset['size'] as int?,
            checksum: asset['checksum'] as String?,
          );
        }
      }

      return null;
    } catch (e) {
      LogService.instance.log('error', 'UpdateService', 'Check update error: $e');
      return null;
    }
  }

  RegExp _getAssetPattern() {
    if (Platform.isWindows) {
      return RegExp(r'guanying.*windows.*-setup\.exe$', caseSensitive: false);
    } else if (Platform.isAndroid) {
      return RegExp(r'guanying.*android.*arm64.*\.apk$', caseSensitive: false);
    } else if (Platform.isMacOS) {
      return RegExp(r'guanying.*macos.*\.dmg$', caseSensitive: false);
    }
    throw UnsupportedError('Unsupported platform for update');
  }

  bool _isNewerVersion(String latest, String current) {
    final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (var i = 0; i < maxLength; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  Future<String> downloadUpdate(
    ReleaseInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    // 安全验证：下载 URL 必须来自可信域名
    if (!_isTrustedDownloadUrl(info.downloadUrl)) {
      throw SecurityException('Download URL is not from trusted domain: ${info.downloadUrl}');
    }

    // 安全验证：必须有 checksum
    if (info.checksum == null || info.checksum!.isEmpty) {
      throw SecurityException('Checksum is required for security verification');
    }

    final tempDir = await getTemporaryDirectory();
    final safeFileName = p.basename(info.fileName).replaceAll(RegExp(r'[^\w\-.]'), '_');
    if (safeFileName.isEmpty || safeFileName.startsWith('.')) {
      throw ArgumentError('Invalid file name: ${info.fileName}');
    }
    final savePath = p.join(tempDir.path, 'update', safeFileName);
    final file = File(savePath);
    await file.parent.create(recursive: true);

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response = await client.send(request).timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw TimeoutException('Download timed out'),
      );

      final totalBytes = response.contentLength ?? info.fileSize ?? 0;
      var receivedBytes = 0;
      final sink = file.openWrite();

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0 && onProgress != null) {
            onProgress(receivedBytes / totalBytes);
          }
        }
      } finally {
        await sink.close();
      }

      // 强制 checksum 验证
      final fileBytes = await file.readAsBytes();
      final computedHash = sha256.convert(fileBytes).toString();
      if (computedHash.toLowerCase() != info.checksum!.toLowerCase()) {
        await file.delete();
        throw SecurityException('Checksum mismatch: expected ${info.checksum}, got $computedHash');
      }

      return savePath;
    } finally {
      client.close();
    }
  }

  Future<void> installUpdate(String filePath) async {
    if (Platform.isWindows) {
      await _installWindows(filePath);
    } else if (Platform.isAndroid) {
      await _installAndroid(filePath);
    } else if (Platform.isMacOS) {
      throw UnsupportedError('macOS uses Sparkle for updates, call triggerUpdate() instead');
    }
  }

  Future<void> triggerUpdate() async {
    if (Platform.isMacOS) {
      await autoUpdater.checkForUpdates();
    }
  }

  Future<void> _installWindows(String exePath) async {
    // 安全验证：Authenticode 签名验证
    final signatureValid = await _verifyWindowsSignature(exePath);
    if (!signatureValid) {
      throw SecurityException('Windows executable signature verification failed: $exePath');
    }

    await Process.start(
      exePath,
      ['/SILENT', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  Future<bool> _verifyWindowsSignature(String exePath) async {
    try {
      // 使用 PowerShell 验证 Authenticode 签名有效性
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-AuthenticodeSignature -LiteralPath "$exePath").Status -eq "Valid"'
      ]);

      final isValid = result.stdout.toString().trim().toLowerCase() == 'true';
      LogService.instance.log('info', 'UpdateService', 'Signature verification: ${isValid ? "passed" : "failed"}');
      return isValid;
    } catch (e) {
      LogService.instance.log('error', 'UpdateService', 'Signature verification error: $e');
      return false;
    }
  }

  Future<void> _installAndroid(String apkPath) async {
    final result = await OpenFilex.open(apkPath, type: 'application/vnd.android.package-archive');
    LogService.instance.log('info', 'UpdateService', 'Install result: ${result.message}');
  }
}
