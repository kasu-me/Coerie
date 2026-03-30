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
}
