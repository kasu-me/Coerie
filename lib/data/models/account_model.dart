import 'package:hive_flutter/hive_flutter.dart';

part 'account_model_adapter.dart';

class AccountModel {
  final String id;
  final String host;
  final String token;
  final String userId;
  final String username;
  final String name;
  final String? avatarUrl;
  bool isActive;

  AccountModel({
    required this.id,
    required this.host,
    required this.token,
    required this.userId,
    required this.username,
    required this.name,
    this.avatarUrl,
    this.isActive = false,
  });

  String get acct => '@$username@$host';

  Map<String, dynamic> toJson() => {
    'id': id,
    'host': host,
    'token': token,
    'userId': userId,
    'username': username,
    'name': name,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    'isActive': isActive,
  };

  factory AccountModel.fromJson(Map<String, dynamic> json) => AccountModel(
    id: json['id'] as String,
    host: json['host'] as String,
    token: json['token'] as String,
    userId: json['userId'] as String,
    username: json['username'] as String,
    name: json['name'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    isActive: json['isActive'] as bool? ?? false,
  );
}
