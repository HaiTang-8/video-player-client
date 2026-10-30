/// 存储源驱动声明（`GET /storages/drivers`），前端按它渲染表单
class DriverMeta {
  final String type;
  final String label;
  final List<FieldSpec> fields;
  final DriverCaps capabilities;

  const DriverMeta({
    required this.type,
    required this.label,
    this.fields = const [],
    this.capabilities = const DriverCaps(),
  });

  factory DriverMeta.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final label = json['label'] as String?;
    return DriverMeta(
      type: type,
      label: label == null || label.isEmpty ? type : label,
      fields: [
        for (final f in json['fields'] as List? ?? const [])
          if (f is Map<String, dynamic>) FieldSpec.fromJson(f),
      ],
      capabilities:
          json['capabilities'] is Map<String, dynamic>
              ? DriverCaps.fromJson(json['capabilities'])
              : const DriverCaps(),
    );
  }

  static DriverMeta? find(List<DriverMeta> metas, String type) {
    final normalized = type.trim().toLowerCase();
    for (final m in metas) {
      if (m.type.toLowerCase() == normalized) return m;
    }
    return null;
  }
}

enum FieldKind {
  text,
  password,
  textarea,
  url,
  number,
  select;

  static FieldKind fromString(String? value) => FieldKind.values.firstWhere(
    (e) => e.name == value,
    orElse: () => FieldKind.text,
  );
}

class FieldOption {
  final String value;
  final String label;

  const FieldOption({required this.value, required this.label});

  factory FieldOption.fromJson(Map<String, dynamic> json) {
    final value = json['value']?.toString() ?? '';
    final label = json['label'] as String?;
    return FieldOption(
      value: value,
      label: label == null || label.isEmpty ? value : label,
    );
  }
}

class FieldSpec {
  final String key;
  final String label;
  final FieldKind kind;
  final bool required;
  final String defaultValue;
  final String? placeholder;
  final String? help;
  final List<FieldOption> options;
  final bool rotating;

  const FieldSpec({
    required this.key,
    required this.label,
    this.kind = FieldKind.text,
    this.required = false,
    this.defaultValue = '',
    this.placeholder,
    this.help,
    this.options = const [],
    this.rotating = false,
  });

  factory FieldSpec.fromJson(Map<String, dynamic> json) {
    final key = json['key'] as String? ?? '';
    final label = json['label'] as String?;
    String? optional(String k) {
      final v = json[k] as String?;
      return v == null || v.isEmpty ? null : v;
    }

    return FieldSpec(
      key: key,
      label: label == null || label.isEmpty ? key : label,
      kind: FieldKind.fromString(json['kind'] as String?),
      required: json['required'] as bool? ?? false,
      defaultValue: json['default']?.toString() ?? '',
      placeholder: optional('placeholder'),
      help: optional('help'),
      options: [
        for (final o in json['options'] as List? ?? const [])
          if (o is Map<String, dynamic>) FieldOption.fromJson(o),
      ],
      rotating: json['rotating'] as bool? ?? false,
    );
  }
}

class DriverCaps {
  final bool directLink;
  final bool variants;
  final List<String> streamModes;
  final bool qrLogin;

  const DriverCaps({
    this.directLink = false,
    this.variants = false,
    this.streamModes = const [],
    this.qrLogin = false,
  });

  factory DriverCaps.fromJson(Map<String, dynamic> json) => DriverCaps(
    directLink: json['direct_link'] as bool? ?? false,
    variants: json['variants'] as bool? ?? false,
    streamModes: [
      for (final m in json['stream_modes'] as List? ?? const [])
        if (m is String && m.isNotEmpty) m,
    ],
    qrLogin: json['qr_login'] as bool? ?? false,
  );
}
