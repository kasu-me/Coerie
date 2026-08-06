import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_settings_model.dart';
import '../../data/models/drawer_button_type.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/image_compression_level.dart';
import 'shared_preferences_provider.dart';

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettingsModel>((ref) {
      final prefs = ref.read(sharedPreferencesProvider);
      return SettingsNotifier(prefs);
    });

class SettingsNotifier extends StateNotifier<AppSettingsModel> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(_loadSync(_prefs));

  static AppSettingsModel _loadSync(SharedPreferences prefs) {
    final jsonStr = prefs.getString(AppConstants.settingsKey);
    if (jsonStr != null) {
      try {
        return AppSettingsModel.fromJsonString(jsonStr);
      } catch (_) {
        return const AppSettingsModel();
      }
    }
    return const AppSettingsModel();
  }

  /// 状態を差し替えて永続化する。各セッターの共通処理。
  Future<void> _apply(AppSettingsModel next) async {
    state = next;
    await _prefs.setString(AppConstants.settingsKey, next.toJsonString());
  }

  Future<void> setTheme(String theme) => _apply(state.copyWith(theme: theme));

  Future<void> setFontSize(double size) =>
      _apply(state.copyWith(fontSize: size));

  Future<void> setAvatarRadius(double radius) =>
      _apply(state.copyWith(avatarRadius: radius));

  Future<void> setRealtimeUpdate(bool value) =>
      _apply(state.copyWith(realtimeUpdate: value));

  Future<void> setTabs(List<TabConfigModel> tabs) =>
      _apply(state.copyWith(tabs: tabs));

  Future<void> setNotificationsEnabled(bool value) =>
      _apply(state.copyWith(notificationsEnabled: value));

  Future<void> setNotifyReply(bool value) =>
      _apply(state.copyWith(notifyReply: value));

  Future<void> setNotifyFollow(bool value) =>
      _apply(state.copyWith(notifyFollow: value));

  Future<void> setNotifyReaction(bool value) =>
      _apply(state.copyWith(notifyReaction: value));

  Future<void> setDateTimeRelative(bool value) =>
      _apply(state.copyWith(dateTimeRelative: value));

  Future<void> setDefaultVisibility(String value) =>
      _apply(state.copyWith(defaultVisibility: value));

  Future<void> setTimezoneOffsetHours(int? value) =>
      _apply(state.copyWith(timezoneOffsetHours: value));

  Future<void> setConfirmDestructive(bool value) =>
      _apply(state.copyWith(confirmDestructive: value));

  Future<void> setMfmAnimation(bool value) =>
      _apply(state.copyWith(mfmAnimation: value));

  Future<void> setCollapseNote(bool value) =>
      _apply(state.copyWith(collapseNote: value));

  Future<void> setDefaultImageCompressionLevel(ImageCompressionLevel level) =>
      _apply(state.copyWith(defaultImageCompressionLevel: level));

  Future<void> setRenoteVisibility(String value) =>
      _apply(state.copyWith(renoteVisibility: value));

  Future<void> setDrawerButtonHidden(DrawerButtonKey key, bool hidden) {
    final next = Set<String>.from(state.hiddenDrawerButtons);
    if (hidden) {
      next.add(key.name);
    } else {
      next.remove(key.name);
    }
    return _apply(state.copyWith(hiddenDrawerButtons: next.toList()));
  }

  Future<void> importSettings(AppSettingsModel settings) => _apply(settings);
}
