import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

class PasswordTextField extends shadcn.StatelessWidget {
  final TextEditingController? controller;
  final shadcn.Widget? placeholder;
  final int? maxLength;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  const PasswordTextField({
    super.key,
    this.controller,
    this.placeholder,
    this.maxLength,
    this.autofocus = false,
    this.onChanged,
  });

  @override
  shadcn.Widget build(shadcn.BuildContext context) {
    return shadcn.TextField(
      controller: controller,
      placeholder: placeholder,
      autofocus: autofocus,
      obscureText: true,
      onChanged: onChanged,
      inputFormatters: maxLength != null
          ? [LengthLimitingTextInputFormatter(maxLength)]
          : null,
      features: [
        shadcn.InputFeature.passwordToggle(),
      ],
    );
  }
}
