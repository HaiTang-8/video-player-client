import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/widgets/loading_widget.dart';
import '../../providers/providers.dart';

/// 视频播放器页面
class PlayerScreen extends ConsumerStatefulWidget {
  final String type; // 'movie' or 'episode'
  final int id;
  final int? tvShowId;
  final int? seasonId;

  const PlayerScreen({
    super.key,
    required this.type,
    required this.id,
    this.tvShowId,
    this.seasonId,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _isLoading = true;
  String? _error;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _loadVideo();
    // 进入全屏模式
    _enterFullscreen();
  }

  @override
  void dispose() {
    _exitFullscreen();
    _player.dispose();
    super.dispose();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() {
      _isFullscreen = true;
    });
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (mounted) {
      setState(() {
        _isFullscreen = false;
      });
    }
  }

  Future<void> _loadVideo() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String? streamUrl;

      if (widget.type == 'movie') {
        final response = await ref.read(movieStreamProvider(widget.id).future);
        streamUrl = response?.url;
      } else if (widget.type == 'episode' &&
          widget.tvShowId != null &&
          widget.seasonId != null) {
        final response = await ref.read(
          episodeStreamProvider((
            tvShowId: widget.tvShowId!,
            seasonId: widget.seasonId!,
            episodeId: widget.id,
          )).future,
        );
        streamUrl = response?.url;
      }

      if (!mounted) return;

      if (streamUrl == null || streamUrl.isEmpty) {
        setState(() {
          _error = '无法获取播放地址';
          _isLoading = false;
        });
        return;
      }

      // 获取服务器地址
      final serverUrl = ref.read(serverUrlProvider);
      final fullUrl = streamUrl.startsWith('http')
          ? streamUrl
          : '$serverUrl$streamUrl';

      await _player.open(Media(fullUrl));

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const LoadingWidget(message: '加载中...'),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadVideo,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 视频播放器
          Center(
            child: Video(
              controller: _controller,
              controls: AdaptiveVideoControls,
            ),
          ),

          // 返回按钮（仅在非全屏时显示）
          if (!_isFullscreen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }
}
