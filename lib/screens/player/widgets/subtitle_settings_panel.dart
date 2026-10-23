import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;

import '../../../core/window/window_controls.dart';
import '../../../playback/domain/subtitle_style.dart';
import '../../../providers/subtitle_settings_provider.dart';

/// 播放器右侧滑出的字幕设置面板；样式修改实时生效并保存，偏移只作用于当前视频
class SubtitleSettingsPanel extends ConsumerWidget {
  const SubtitleSettingsPanel({
    super.key,
    required this.delay,
    required this.delaySupported,
    required this.onDelayChanged,
    this.delaySharedByShow = false,
  });

  final ValueListenable<Duration> delay;
  final bool delaySharedByShow;
  final bool Function() delaySupported;
  final ValueChanged<Duration> onDelayChanged;

  static const _panelColor = Color(0xFF1C1C1E);
  static const _cardColor = Color(0xFF2C2C2E);
  static const _delayStep = Duration(milliseconds: 100);
  static const _maxDelay = Duration(seconds: 60);

  static const _scales = [('小', 0.8), ('标准', 1.0), ('大', 1.2), ('极大', 1.45)];

  static const _colors = [
    0xFFFFFFFF,
    0xFF4A9EFF,
    0xFF5AD2F4,
    0xFFA8D4FF,
    0xFFFBE5A0,
    0xFFF0584A,
    0xFFF0559A,
    0xFFB0A4FF,
  ];

  static Future<void> show(
    BuildContext context, {
    required ValueListenable<Duration> delay,
    required bool Function() delaySupported,
    required ValueChanged<Duration> onDelayChanged,
    bool delaySharedByShow = false,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim, _) {
        final mq = MediaQuery.of(ctx);
        final width =
            WindowControls.isDesktop
                ? 360.0
                : (mq.size.width * 0.42).clamp(300.0, 400.0);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: _panelColor,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: width,
                height: double.infinity,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: mq.viewPadding.top,
                    bottom: mq.viewPadding.bottom,
                    right: mq.viewPadding.right,
                  ),
                  child: SubtitleSettingsPanel(
                    delay: delay,
                    delaySupported: delaySupported,
                    onDelayChanged: onDelayChanged,
                    delaySharedByShow: delaySharedByShow,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(subtitleSettingsProvider);
    final notifier = ref.read(subtitleSettingsProvider.notifier);
    return DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onReset: notifier.reset),
          const Divider(height: 1, thickness: 0.5, color: Colors.white12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                const _SectionLabel('字幕大小'),
                _Card(
                  child: Row(
                    children: [
                      for (final (label, scale) in _scales)
                        Expanded(
                          child: _ScaleOption(
                            label: label,
                            selected: style.scale == scale,
                            onTap:
                                () => notifier.update(
                                  style.copyWith(scale: scale),
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
                const _SectionLabel('字幕颜色'),
                _Card(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final color in _colors)
                        _ColorSwatch(
                          color: Color(color),
                          selected: style.color == color,
                          onTap:
                              () =>
                                  notifier.update(style.copyWith(color: color)),
                        ),
                    ],
                  ),
                ),
                const _SectionLabel('背景透明度'),
                _PercentSlider(
                  value: style.backgroundOpacity,
                  max: 1,
                  onChanged:
                      (v) => notifier.update(
                        style.copyWith(backgroundOpacity: v),
                        persist: false,
                      ),
                  onChangeEnd:
                      (v) =>
                          notifier.update(style.copyWith(backgroundOpacity: v)),
                ),
                const _SectionLabel('字幕位置'),
                _PercentSlider(
                  value: style.bottomMargin,
                  max: SubtitleStyle.maxBottomMargin,
                  onChanged:
                      (v) => notifier.update(
                        style.copyWith(bottomMargin: v),
                        persist: false,
                      ),
                  onChangeEnd:
                      (v) => notifier.update(style.copyWith(bottomMargin: v)),
                ),
                const SizedBox(height: 20),
                ValueListenableBuilder<Duration>(
                  valueListenable: delay,
                  builder:
                      (context, value, _) => _DelayRow(
                        value: value,
                        enabled: delaySupported(),
                        hint: delaySharedByShow ? '同一部剧各集通用' : '仅对当前影片生效',
                        onChanged: (v) {
                          if (v.abs() <= _maxDelay) onDelayChanged(v);
                        },
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Text(
            '字幕设置',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          const Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            showDuration: Duration(seconds: 5),
            message:
                '颜色、背景和位置只作用于普通文本字幕；特效字幕（ASS）保留原有颜色与位置，'
                '图片字幕（PGS）不受这些设置影响。偏移时间保存在本机，同一部剧的各集共用。',
            child: Icon(LucideIcons.info, size: 16, color: Colors.white60),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onReset,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(LucideIcons.rotateCw, size: 16),
            label: const Text('恢复默认', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: SubtitleSettingsPanel._cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _ScaleOption extends StatelessWidget {
  const _ScaleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _PercentSlider extends StatelessWidget {
  const _PercentSlider({
    required this.value,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayColor: Colors.white10,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value: value.clamp(0, max),
                max: max,
                divisions: (max * 100).round(),
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DelayRow extends StatelessWidget {
  const _DelayRow({
    required this.value,
    required this.enabled,
    required this.hint,
    required this.onChanged,
  });

  final Duration value;
  final bool enabled;
  final String hint;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    final seconds = value.inMilliseconds / 1000;
    final text = '${seconds > 0 ? '+' : ''}${seconds.toStringAsFixed(2)}s';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '偏移时间',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                enabled ? hint : '当前内核仅支持外挂字幕偏移',
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
        ),
        _StepButton(
          icon: LucideIcons.minus,
          onTap:
              enabled
                  ? () => onChanged(value - SubtitleSettingsPanel._delayStep)
                  : null,
        ),
        GestureDetector(
          onLongPress: enabled ? () => onChanged(Duration.zero) : null,
          child: SizedBox(
            width: 72,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: enabled ? Colors.white : Colors.white38,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        _StepButton(
          icon: LucideIcons.plus,
          onTap:
              enabled
                  ? () => onChanged(value + SubtitleSettingsPanel._delayStep)
                  : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.white10 : Colors.white24,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? Colors.white38 : Colors.white,
        ),
      ),
    );
  }
}
