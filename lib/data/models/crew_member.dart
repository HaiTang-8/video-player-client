/// 职员条目（用于详情页“职员表”展示）
class CrewMember {
  final String name;
  final String? job;
  final String? department;
  final String? profilePath;

  const CrewMember({
    required this.name,
    this.job,
    this.department,
    this.profilePath,
  });

  factory CrewMember.fromJson(Map<String, dynamic> json) {
    return CrewMember(
      name: json['name']?.toString() ?? '',
      job: json['job']?.toString(),
      department: json['department']?.toString(),
      profilePath: json['profile_path']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'job': job,
    'department': department,
    'profile_path': profilePath,
  };
}
