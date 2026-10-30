import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../core/widgets/form_page.dart';
import '../../core/widgets/password_text_field.dart';
import '../../data/models/models.dart';

/// 按驱动声明维护表单取值
class DriverFieldsController extends ChangeNotifier {
  final DriverMeta meta;
  final Map<String, String> _extra;
  final Map<String, TextEditingController> _text = {};
  final Map<String, String?> _selected = {};

  /// [initial] 是同类型存储源已保存的配置；未声明的键原样保留
  DriverFieldsController(this.meta, [Map<String, String>? initial])
    : _extra = {...?initial} {
    for (final field in meta.fields) {
      final saved = _extra.remove(field.key);
      final value = saved ?? field.defaultValue;
      if (field.kind == FieldKind.select) {
        final valid = field.options.map((o) => o.value);
        _selected[field.key] =
            valid.contains(value)
                ? value
                : (valid.contains(field.defaultValue)
                    ? field.defaultValue
                    : null);
      } else {
        _text[field.key] = TextEditingController(text: value);
      }
    }
  }

  TextEditingController textController(String key) => _text[key]!;

  String? selectedValue(String key) => _selected[key];

  void select(String key, String value) {
    if (_selected[key] == value) return;
    _selected[key] = value;
    notifyListeners();
  }

  /// 合并外部给出的配置（例如扫码登录得到的 Cookie）
  void apply(Map<String, String> patch) {
    final declared = {for (final f in meta.fields) f.key: f};
    for (final e in patch.entries) {
      final field = declared[e.key];
      if (field == null) {
        _extra[e.key] = e.value;
      } else if (field.kind == FieldKind.select) {
        if (field.options.any((o) => o.value == e.value)) {
          _selected[e.key] = e.value;
        }
      } else {
        _text[e.key]!.text = e.value;
      }
    }
    notifyListeners();
  }

  String _rawValue(FieldSpec field) {
    if (field.kind == FieldKind.select) return _selected[field.key] ?? '';
    final text = _text[field.key]!.text;
    return field.kind == FieldKind.password ? text : text.trim();
  }

  /// 提交用的配置：只包含非空值
  Map<String, String> values() {
    final result = {..._extra};
    for (final field in meta.fields) {
      final value = _rawValue(field);
      if (value.isNotEmpty) result[field.key] = value;
    }
    return result;
  }

  /// 返回第一条错误提示，全部通过时返回 null
  String? validate() {
    for (final field in meta.fields) {
      final value = _rawValue(field);
      if (value.isEmpty) {
        if (field.required) {
          return field.kind == FieldKind.select
              ? '请选择${field.label}'
              : '请填写${field.label}';
        }
        continue;
      }
      if (field.kind == FieldKind.number && int.tryParse(value) == null) {
        return '${field.label}必须是整数';
      }
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// 按驱动声明的 [FieldSpec] 渲染的表单项
class DriverFieldsForm extends StatelessWidget {
  final DriverFieldsController controller;

  const DriverFieldsForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final fields = controller.meta.fields;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              FormFieldBlock(
                key: ValueKey('driver-field-${fields[i].key}'),
                label: fields[i].label,
                helper: fields[i].help,
                child: _buildInput(context, fields[i]),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildInput(BuildContext context, FieldSpec field) {
    final placeholder = field.placeholder ?? field.defaultValue;
    final hint = placeholder.isEmpty ? null : Text(placeholder);
    switch (field.kind) {
      case FieldKind.password:
        return PasswordTextField(
          controller: controller.textController(field.key),
          placeholder: hint,
        );
      case FieldKind.textarea:
        return shadcn.TextField(
          controller: controller.textController(field.key),
          placeholder: hint,
          minLines: 3,
          maxLines: 5,
          style: const TextStyle(fontSize: 13),
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
        );
      case FieldKind.url:
        return shadcn.TextField(
          controller: controller.textController(field.key),
          placeholder: hint,
          keyboardType: TextInputType.url,
          autocorrect: false,
        );
      case FieldKind.number:
        return shadcn.TextField(
          controller: controller.textController(field.key),
          placeholder: hint,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        );
      case FieldKind.select:
        return _buildSelect(context, field);
      case FieldKind.text:
        return shadcn.TextField(
          controller: controller.textController(field.key),
          placeholder: hint,
          autocorrect: false,
        );
    }
  }

  Widget _buildSelect(BuildContext context, FieldSpec field) {
    final value = controller.selectedValue(field.key);
    if (field.options.length > 3) {
      return SizedBox(
        width: double.infinity,
        child: shadcn.Select<String>(
          value: value,
          placeholder: const Text('请选择'),
          itemBuilder:
              (context, item) => Text(
                field.options
                    .firstWhere(
                      (o) => o.value == item,
                      orElse: () => FieldOption(value: item, label: item),
                    )
                    .label,
              ),
          onChanged: (v) {
            if (v != null) controller.select(field.key, v);
          },
          popup:
              shadcn.SelectPopup(
                items: shadcn.SelectItemList(
                  children: [
                    for (final o in field.options)
                      shadcn.SelectItemButton(
                        value: o.value,
                        child: Text(o.label),
                      ),
                  ],
                ),
              ).call,
        ),
      );
    }
    final color = Theme.of(context).colorScheme.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < field.options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: FormOptionCard(
                selected: value == field.options[i].value,
                color: color,
                onTap:
                    () => controller.select(field.key, field.options[i].value),
                child: Text(
                  field.options[i].label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
