import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../core/widgets/dialog_utils.dart';
import '../../data/models/models.dart';

typedef QrLoginStarter = Future<QrLoginChallenge> Function();
typedef QrLoginPoller = Future<QrLoginStatus> Function(String sessionId);

class QrLoginException implements Exception {
  final String message;

  const QrLoginException(this.message);

  @override
  String toString() => message;
}

/// 显示扫码登录弹窗；确认登录后返回要填进表单的配置，取消时返回 null
Future<Map<String, String>?> showQrLoginDialog(
  BuildContext context, {
  required String title,
  required String appName,
  required QrLoginStarter start,
  required QrLoginPoller poll,
}) {
  return DialogUtils.showCustomDialog<Map<String, String>>(
    context: context,
    builder:
        (_) => QrLoginDialog(
          title: title,
          appName: appName,
          start: start,
          poll: poll,
        ),
  );
}

class QrLoginDialog extends StatefulWidget {
  final String title;

  /// 用来扫码的手机 App 名称，例如“夸克 App”
  final String appName;
  final QrLoginStarter start;
  final QrLoginPoller poll;
  final Duration pollInterval;

  const QrLoginDialog({
    super.key,
    required this.title,
    required this.appName,
    required this.start,
    required this.poll,
    this.pollInterval = const Duration(seconds: 2),
  });

  @override
  State<QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<QrLoginDialog> {
  static const _qrSize = 200.0;
  static const _maxPollFailures = 3;

  QrLoginChallenge? _challenge;
  QrLoginState _state = QrLoginState.pending;
  String? _error;
  int _generation = 0;
  int _failures = 0;
  bool _polling = false;
  Timer? _clock;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _clock?.cancel();
    _poller?.cancel();
  }

  Future<void> _start() async {
    final gen = ++_generation;
    _stopTimers();
    setState(() {
      _challenge = null;
      _state = QrLoginState.pending;
      _error = null;
      _failures = 0;
      _polling = false;
    });
    try {
      final challenge = await widget.start();
      if (!mounted || gen != _generation) return;
      setState(() => _challenge = challenge);
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => _onClock());
      _poller = Timer.periodic(widget.pollInterval, (_) => _poll(gen));
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = '获取二维码失败：$e');
    }
  }

  void _onClock() {
    final challenge = _challenge;
    if (challenge == null) return;
    if (!DateTime.now().isBefore(challenge.deadline)) {
      _expire();
    } else {
      setState(() {});
    }
  }

  void _expire() {
    _stopTimers();
    setState(() => _state = QrLoginState.expired);
  }

  Future<void> _poll(int gen) async {
    final challenge = _challenge;
    if (_polling || challenge == null) return;
    _polling = true;
    try {
      final status = await widget.poll(challenge.sessionId);
      if (!mounted || gen != _generation) return;
      _failures = 0;
      switch (status.state) {
        case QrLoginState.confirmed:
          _stopTimers();
          Navigator.of(context).pop(status.settings);
        case QrLoginState.expired:
          _expire();
        case QrLoginState.pending:
        case QrLoginState.scanned:
          if (status.state != _state) setState(() => _state = status.state);
      }
    } catch (e) {
      if (!mounted || gen != _generation) return;
      if (++_failures >= _maxPollFailures) {
        _stopTimers();
        setState(() => _error = '$e');
      }
    } finally {
      if (gen == _generation) _polling = false;
    }
  }

  Future<void> _copyLink() async {
    final url = _challenge?.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    DialogUtils.showToast(
      context: context,
      message: '链接已复制，请粘贴到${widget.appName} 中打开',
    );
  }

  bool get _needsRestart => _error != null || _state == QrLoginState.expired;

  @override
  Widget build(BuildContext context) {
    final canCopy = _challenge != null && !_needsRestart;
    return shadcn.AlertDialog(
      barrierColor: Colors.transparent,
      surfaceOpacity: 1,
      title: Text(widget.title),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildQrBox(context),
            const SizedBox(height: 12),
            _buildStatus(context),
            if (canCopy) ...[
              const SizedBox(height: 4),
              Text(
                '在本机登录时，可复制链接后粘贴到${widget.appName} 中打开',
                textAlign: TextAlign.center,
                style: shadcn.Theme.of(context).typography.xSmall.copyWith(
                  color: shadcn.Theme.of(context).colorScheme.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (canCopy)
          shadcn.OutlineButton(
            onPressed: _copyLink,
            leading: const Icon(shadcn.LucideIcons.copy, size: 14),
            child: const Text('复制链接'),
          ),
        shadcn.OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildQrBox(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final challenge = _challenge;
    Widget child;
    if (challenge == null && _error == null) {
      child = const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      child = Stack(
        fit: StackFit.expand,
        children: [
          if (challenge != null)
            // 二维码在深色模式下也保持白底，保证识别率
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: Image.memory(
                challenge.png,
                key: const ValueKey('qr-login-image'),
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            ),
          if (_needsRestart)
            ColoredBox(
              color: theme.colorScheme.background.withValues(alpha: 0.92),
              child: Center(
                child: shadcn.PrimaryButton(
                  onPressed: _start,
                  leading: const Icon(shadcn.LucideIcons.refreshCw, size: 14),
                  child: const Text('重新获取'),
                ),
              ),
            ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: _qrSize,
        height: _qrSize,
        decoration: BoxDecoration(
          color: theme.colorScheme.muted,
          border: Border.all(color: theme.colorScheme.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final style = theme.typography.small;
    if (_error != null) {
      return Text(
        _error!,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: theme.colorScheme.destructive),
      );
    }
    final challenge = _challenge;
    final String text;
    if (challenge == null) {
      text = '正在获取二维码…';
    } else {
      switch (_state) {
        case QrLoginState.expired:
          text = '二维码已过期';
        case QrLoginState.scanned:
          text = '已扫码，请在手机上确认登录';
        case QrLoginState.pending:
        case QrLoginState.confirmed:
          final left = challenge.deadline.difference(DateTime.now()).inSeconds;
          final clamped = left < 0 ? 0 : left;
          final mm = clamped ~/ 60;
          final ss = (clamped % 60).toString().padLeft(2, '0');
          text = '请使用${widget.appName} 扫码登录（$mm:$ss）';
      }
    }
    return Text(
      text,
      key: const ValueKey('qr-login-status'),
      textAlign: TextAlign.center,
      style: style.copyWith(color: theme.colorScheme.foreground),
    );
  }
}
