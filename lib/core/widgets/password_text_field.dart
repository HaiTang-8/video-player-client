import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

class PasswordTextField extends shadcn.StatelessWidget {
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
  shadcn.Widget build(shadcn.BuildContext context) {
    return shadcn.TextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder,
      autofocus: autofocus,
      obscureText: true,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters:
          maxLength != null
              ? [LengthLimitingTextInputFormatter(maxLength)]
              : null,
      features: [shadcn.InputFeature.passwordToggle()],
    );
  }
}
