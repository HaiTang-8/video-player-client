import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/desktop_title_bar.dart';
import '../../core/window/window_controls.dart';
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
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _setupPlayerListeners();
    _loadVideo();
    // 移动端默认进入全屏模式
    if (!WindowControls.isDesktop) {
      _enterFullscreen();
    }
  }

  void _setupPlayerListeners() {
    // 监听播放器错误
    _player.stream.error.listen((error) {
      if (!mounted || _isDisposing) return;
      if (error.isNotEmpty) {
        setState(() {
          _error = '播放错误: $error';
          _isLoading = false;
        });
      }
    });

    // 监听缓冲状态
    _player.stream.buffering.listen((buffering) {
      if (!mounted || _isDisposing) return;
      // 可选：显示缓冲状态
    });

    // 监听播放完成
    _player.stream.completed.listen((completed) {
      if (!mounted || _isDisposing) return;
      if (completed) {
        // 播放完成，可返回上一页或显示提示
      }
    });
  }

  @override
  void dispose() {
    _isDisposing = true;
    if (_isFullscreen) {
      _exitFullscreen();
    }
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
    if (mounted && !_isDisposing) {
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
      final fullUrl =
          streamUrl.startsWith('http') ? streamUrl : '$serverUrl$streamUrl';
          
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
        appBar:
            WindowControls.isDesktop
                ? DesktopTitleBar(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  // Desktop 端自绘标题栏：返回按钮使用“<”样式，标题不居中。
                  centerTitle: false,
                  leading: AppBackButton(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  title: const Text('播放失败'),
                )
                : AppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  toolbarHeight: 44,
                  centerTitle: false,
                  automaticallyImplyLeading: false,
                  leadingWidth: kAppBackButtonWidth,
                  titleSpacing: 1,
                  leading: AppBackButton(
                    onPressed: () => Navigator.of(context).pop(),
                    color: Colors.white,
                  ),
                  title: const Text(
                    '播放失败',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
                // 顶部返回按钮使用“<”样式，视觉上更接近“<”形态。
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }
}
