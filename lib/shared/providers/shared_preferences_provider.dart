import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// main() でインスタンスを事前ロードし overrideWithValue() で渡す。
/// これにより各プロバイダーが同期的に値を読める。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('SharedPreferences not initialized'),
);
