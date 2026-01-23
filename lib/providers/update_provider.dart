import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/update_service.dart';

enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  installing,
  error,
  upToDate,
}

class UpdateState {
  final UpdateStatus status;
  final ReleaseInfo? releaseInfo;
  final double downloadProgress;
  final String? errorMessage;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.releaseInfo,
    this.downloadProgress = 0,
    this.errorMessage,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    ReleaseInfo? releaseInfo,
    double? downloadProgress,
    String? errorMessage,
  }) {
    return UpdateState(
      status: status ?? this.status,
      releaseInfo: releaseInfo ?? this.releaseInfo,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage,
    );
  }
}

class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  bool get supportsUpdate => Platform.isWindows || Platform.isAndroid || Platform.isMacOS;

  Future<void> checkForUpdate() async {
    if (!supportsUpdate) return;

    state = state.copyWith(status: UpdateStatus.checking);

    try {
      final info = await UpdateService.instance.checkForUpdate();
      if (info != null) {
        state = state.copyWith(status: UpdateStatus.available, releaseInfo: info);
      } else {
        state = state.copyWith(status: UpdateStatus.upToDate);
      }
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.error, errorMessage: e.toString());
    }
  }

  Future<void> downloadAndInstall() async {
    final info = state.releaseInfo;
    if (info == null) return;

    state = state.copyWith(status: UpdateStatus.downloading, downloadProgress: 0);

    try {
      final filePath = await UpdateService.instance.downloadUpdate(
        info,
        onProgress: (progress) {
          state = state.copyWith(downloadProgress: progress);
        },
      );

      state = state.copyWith(status: UpdateStatus.installing);
      await UpdateService.instance.installUpdate(filePath);
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.error, errorMessage: e.toString());
    }
  }

  void reset() {
    state = const UpdateState();
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
