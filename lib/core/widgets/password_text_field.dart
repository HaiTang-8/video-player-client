import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// 密码输入框。
///
/// 不使用 shadcn 的 `InputFeature.passwordToggle`：shadcn TextField 内部 EditableText
/// 固定 `Clip.none`，长密码会画到切换按钮下方。这里自行组装外框，文字区单独裁剪。
class PasswordTextField extends shadcn.StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final shadcn.Widget? placeholder;
  final int? maxLength;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TapRegionCallback? onTapOutside;
  final Iterable<String>? autofillHints;

  const PasswordTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.maxLength,
    this.autofocus = false,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
    this.onTapOutside,
    this.autofillHints,
  });

  @override
  shadcn.State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends shadcn.State<PasswordTextField> {
  FocusNode? _ownedFocusNode;
  bool _obscure = true;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(PasswordTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode)?.removeListener(_onFocusChanged);
      _focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  shadcn.Widget build(shadcn.BuildContext context) {
    final theme = shadcn.Theme.of(context);
    final colors = theme.colorScheme;
    final gap = theme.density.baseGap * theme.scaling;
    final contentPadding = theme.density.baseContentPadding * theme.scaling;
    final radius = BorderRadius.circular(theme.radiusMd);

    return shadcn.FocusOutline(
      focused: _focusNode.hasFocus,
      borderRadius: radius,
      child: TextFieldTapRegion(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _focusNode.requestFocus,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: colors.input.scaleAlpha(0.3),
              border: Border.all(
                color: colors.border,
                strokeAlign: BorderSide.strokeAlignCenter,
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: contentPadding * 0.75),
                Expanded(
                  child: ClipRect(
                    child: shadcn.TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      placeholder: widget.placeholder,
                      autofocus: widget.autofocus,
                      obscureText: _obscure,
                      decoration: const BoxDecoration(),
                      padding: EdgeInsets.symmetric(vertical: gap),
                      // HarmonyOS_Sans 的 “•” 是全角字形，掩码圆点间距过大；改用 Geist 的半角圆点
                      style: const TextStyle(
                        fontFamily: 'packages/shadcn_flutter/GeistSans',
                        fontFamilyFallback: ['HarmonyOS_Sans'],
                      ),
                      onChanged: widget.onChanged,
                      textInputAction: widget.textInputAction,
                      onSubmitted: widget.onSubmitted,
                      onTapOutside: widget.onTapOutside,
                      autofillHints: widget.autofillHints,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters:
                          widget.maxLength != null
                              ? [
                                LengthLimitingTextInputFormatter(
                                  widget.maxLength,
                                ),
                              ]
                              : null,
                    ),
                  ),
                ),
                SizedBox(width: gap * 0.5),
                IconTheme.merge(
                  data: theme.iconTheme.small.copyWith(
                    color: colors.mutedForeground,
                  ),
                  child: ExcludeFocus(
                    child: shadcn.IconButton.text(
                      icon: Icon(
                        _obscure
                            ? shadcn.LucideIcons.eye
                            : shadcn.LucideIcons.eyeOff,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                      density: shadcn.ButtonDensity.compact,
                    ),
                  ),
                ),
                SizedBox(width: contentPadding * 0.75 - gap * 0.5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
