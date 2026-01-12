import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';

class ReleaseInfo {
  final String version;
  final String? releaseNotes;
  final String downloadUrl;
  final String fileName;
  final int? fileSize;

  ReleaseInfo({
    required this.version,
    this.releaseNotes,
    required this.downloadUrl,
    required this.fileName,
    this.fileSize,
  });
}

class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/latest',
      );
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github+json',
      });

      if (response.statusCode != 200) {
        debugPrint('[UpdateService] GitHub API error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String?;
      if (tagName == null) return null;

      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      final currentVersion = await getCurrentVersion();

      if (!_isNewerVersion(latestVersion, currentVersion)) {
        return null;
      }

      final assets = data['assets'] as List<dynamic>? ?? [];
      final assetPattern = _getAssetPattern();

      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (assetPattern.hasMatch(name)) {
          return ReleaseInfo(
            version: latestVersion,
            releaseNotes: data['body'] as String?,
            downloadUrl: asset['browser_download_url'] as String,
            fileName: name,
            fileSize: asset['size'] as int?,
          );
        }
      }

      return null;
    } catch (e) {
      debugPrint('[UpdateService] Check update error: $e');
      return null;
    }
  }

  RegExp _getAssetPattern() {
    if (Platform.isWindows) {
      return RegExp(r'guanying.*windows.*-setup\.exe$', caseSensitive: false);
    } else if (Platform.isAndroid) {
      return RegExp(r'guanying.*android.*arm64.*\.apk$', caseSensitive: false);
    }
    throw UnsupportedError('Unsupported platform for update');
  }

  bool _isNewerVersion(String latest, String current) {
    final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
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
    final tempDir = await getTemporaryDirectory();
    final savePath = p.join(tempDir.path, 'update', info.fileName);
    final file = File(savePath);
    await file.parent.create(recursive: true);

    final request = http.Request('GET', Uri.parse(info.downloadUrl));
    final response = await http.Client().send(request);

    final totalBytes = response.contentLength ?? info.fileSize ?? 0;
    var receivedBytes = 0;
    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0 && onProgress != null) {
        onProgress(receivedBytes / totalBytes);
      }
    }
    await sink.close();

    return savePath;
  }

  Future<void> installUpdate(String filePath) async {
    if (Platform.isWindows) {
      await _installWindows(filePath);
    } else if (Platform.isAndroid) {
      await _installAndroid(filePath);
    }
  }

  Future<void> _installWindows(String exePath) async {
    await Process.start(
      exePath,
      ['/SILENT', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  Future<void> _installAndroid(String apkPath) async {
    final result = await OpenFilex.open(apkPath, type: 'application/vnd.android.package-archive');
    debugPrint('[UpdateService] Install result: ${result.message}');
  }
}
