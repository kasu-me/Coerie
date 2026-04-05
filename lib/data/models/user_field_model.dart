class UserFieldModel {
  final String name;
  final String value;
  final bool? verified;

  const UserFieldModel({
    required this.name,
    required this.value,
    this.verified,
  });

  factory UserFieldModel.fromJson(Map<String, dynamic> json) {
    return UserFieldModel(
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      verified: json['verified'] as bool?,
    );
  }
}
