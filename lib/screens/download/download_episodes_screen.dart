import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_app_bar.dart';
import '../../core/widgets/download_indicators.dart';
import '../../core/widgets/mobile_app_bar.dart';
import '../../core/window/window_controls.dart';
import '../../data/models/episode.dart';
import '../../data/models/season.dart';
import '../../providers/download_provider.dart';

class DownloadEpisodesScreen extends ConsumerStatefulWidget {
  final String tvShowName;
  final int seasonNumber;
  final Season season;
  final String? storageName;

  const DownloadEpisodesScreen({
    super.key,
    required this.tvShowName,
    required this.seasonNumber,
    required this.season,
    this.storageName,
  });

  @override
  ConsumerState<DownloadEpisodesScreen> createState() => _DownloadEpisodesScreenState();
}

class _DownloadEpisodesScreenState extends ConsumerState<DownloadEpisodesScreen> {
  double? _availableSpaceGB;

  @override
  void initState() {
    super.initState();
    _loadAvailableSpace();
  }

  Future<void> _loadAvailableSpace() async {
    try {
      if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        final bytes = await _getIOSAvailableSpace(dir.path);
        if (bytes != null && mounted) {
          setState(() {
            _availableSpaceGB = bytes / (1024 * 1024 * 1024);
          });
        }
      } else if (Platform.isMacOS || Platform.isLinux) {
        final stat = await Process.run('df', ['-k', '/']);
        if (stat.exitCode == 0) {
          final lines = (stat.stdout as String).split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length > 3) {
              final availableKB = int.tryParse(parts[3]) ?? 0;
              if (mounted) {
                setState(() {
                  _availableSpaceGB = availableKB / (1024 * 1024);
                });
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<int?> _getIOSAvailableSpace(String path) async {
    try {
      const channel = MethodChannel('media_player/storage');
      final result = await channel.invokeMethod<int>('getAvailableSpace');
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.season.episodes ?? [];
    final downloadState = ref.watch(downloadManagerProvider);
    final downloadableEpisodes = episodes.where((e) => e.hasFile).toList();
    final isDesktop = WindowControls.isDesktop;
    final title = '${widget.tvShowName} 第 ${widget.seasonNumber} 季';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: isDesktop
          ? DesktopAppBar(
              title: Text(title),
              onBack: () => context.pop(),
            )
          : MobileAppBar(
              title: Text(title, style: const TextStyle(fontSize: 17)),
              onBack: () => context.pop(),
            ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: downloadableEpisodes.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (context, index) {
                  final episode = downloadableEpisodes[index];
                  return _EpisodeDownloadItem(
                    episode: episode,
                    storageName: widget.storageName,
                    downloadState: downloadState,
                    onDownload: () => _downloadEpisode(episode),
                  );
                },
              ),
            ),
          ),
          _buildBottomBar(downloadableEpisodes, downloadState),
        ],
      ),
    );
  }

  Widget _buildBottomBar(List<Episode> episodes, DownloadManagerState downloadState) {
    final notDownloaded = episodes.where((e) =>
        !downloadState.isEpisodeDownloaded(e.id) &&
        !downloadState.isEpisodeDownloading(e.id)).toList();
    final hasActiveDownloads = downloadState.downloadingTasks.isNotEmpty;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: notDownloaded.isEmpty ? Colors.grey.shade300 : const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(8),
                  onPressed: notDownloaded.isEmpty ? null : () => _downloadAll(notDownloaded),
                  child: Text(
                    '下载全部',
                    style: TextStyle(
                      color: notDownloaded.isEmpty ? Colors.grey : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () => context.push('/download-manager'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hasActiveDownloads) ...[
                        const AnimatedDownloadIndicator(size: 18),
                        const SizedBox(width: 6),
                      ],
                      const Text(
                        '下载管理',
                        style: TextStyle(color: Colors.black87, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_availableSpaceGB != null)
            Text(
              '设备剩余 ${_availableSpaceGB!.toStringAsFixed(1)} GB 可用',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
        ],
      ),
    );
  }

  void _downloadEpisode(Episode episode) {
    ref.read(downloadManagerProvider.notifier).addDownload(
      episode: episode,
      tvShowName: widget.tvShowName,
      seasonNumber: widget.seasonNumber,
      storageName: widget.storageName,
    );
  }

  void _downloadAll(List<Episode> episodes) {
    ref.read(downloadManagerProvider.notifier).addDownloads(
      episodes: episodes,
      tvShowName: widget.tvShowName,
      seasonNumber: widget.seasonNumber,
      storageName: widget.storageName,
    );
  }
}

class _EpisodeDownloadItem extends StatelessWidget {
  final Episode episode;
  final String? storageName;
  final DownloadManagerState downloadState;
  final VoidCallback onDownload;

  const _EpisodeDownloadItem({
    required this.episode,
    this.storageName,
    required this.downloadState,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final task = downloadState.getTaskByEpisodeId(episode.id);
    final isDownloaded = task?.isCompleted ?? false;
    final isDownloading = task?.isDownloading ?? false;
    final isPending = task?.isPending ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${episode.episodeNumber}. ${episode.name ?? '第 ${episode.episodeNumber} 集'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  episode.filePath?.split('/').last ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (storageName != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          'DAV',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        storageName!,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      Text(
                        ' | ',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ],
                    Text(
                      episode.formattedFileSize,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    if (episode.runtime != null) ...[
                      Text(
                        ' | ',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
                      Text(
                        '${episode.runtime} 分钟',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
                if (isDownloading && task != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: task.progress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.formattedProgress,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildActionButton(isDownloaded, isDownloading, isPending, task?.progress ?? 0),
        ],
      ),
    );
  }

  Widget _buildActionButton(bool isDownloaded, bool isDownloading, bool isPending, double progress) {
    if (isDownloaded) {
      return Icon(
        CupertinoIcons.checkmark_circle_fill,
        size: 28,
        color: CupertinoColors.systemGreen,
      );
    }

    if (isDownloading) {
      return DownloadProgressIcon(progress: progress, size: 28);
    }

    if (isPending) {
      return const AnimatedDownloadIndicator(size: 28);
    }

    return GestureDetector(
      onTap: onDownload,
      child: Icon(
        CupertinoIcons.arrow_down_circle,
        size: 28,
        color: CupertinoColors.systemBlue,
      ),
    );
  }
}
