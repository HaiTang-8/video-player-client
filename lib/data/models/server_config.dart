import 'package:uuid/uuid.dart';

class ServerConfig {
  final String id;
  final String name;
  final String url;
  final DateTime createdAt;

  ServerConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.createdAt,
  });

  factory ServerConfig.create({required String name, required String url}) {
    return ServerConfig(
      id: const Uuid().v4(),
      name: name,
      url: url,
      createdAt: DateTime.now(),
    );
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  ServerConfig copyWith({String? name, String? url}) {
    return ServerConfig(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      createdAt: createdAt,
    );
  }
}
