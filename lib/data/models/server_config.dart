import 'package:uuid/uuid.dart';

class ServerConfig {
  final String id;
  final String name;
  final String url;
  final String proxyUrl;
  final DateTime createdAt;

  ServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.proxyUrl = '',
    required this.createdAt,
  });

  factory ServerConfig.create({
    required String name,
    required String url,
    String proxyUrl = '',
  }) {
    return ServerConfig(
      id: const Uuid().v4(),
      name: name,
      url: url,
      proxyUrl: proxyUrl,
      createdAt: DateTime.now(),
    );
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      proxyUrl: json['proxyUrl'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'proxyUrl': proxyUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  ServerConfig copyWith({String? name, String? url, String? proxyUrl}) {
    return ServerConfig(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      createdAt: createdAt,
    );
  }
}
