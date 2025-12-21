/// 演员条目（用于详情页“相关演员”展示）
class CastMember {
  final String name;
  /// 角色名（TMDB credits 里通常为 character）
  final String? character;
  /// 头像 URL（后端已把 TMDB 的 profile_path 转成可直接访问的图片 URL）
  final String? profilePath;

  const CastMember({
    required this.name,
    this.character,
    this.profilePath,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      name: json['name']?.toString() ?? '',
      character: json['character']?.toString(),
      profilePath: json['profile_path']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'character': character,
        'profile_path': profilePath,
      };
}

