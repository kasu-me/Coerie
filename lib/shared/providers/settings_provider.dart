import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_settings_model.dart';
import '../../core/constants/app_constants.dart';
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

  Future<void> _save() async {
    await _prefs.setString(AppConstants.settingsKey, state.toJsonString());
  }

  Future<void> setTheme(String theme) async {
    state = state.copyWith(theme: theme);
    await _save();
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size);
    await _save();
  }

  Future<void> setAvatarRadius(double radius) async {
    state = state.copyWith(avatarRadius: radius);
    await _save();
  }

  Future<void> setRealtimeUpdate(bool value) async {
    state = state.copyWith(realtimeUpdate: value);
    await _save();
  }

  Future<void> setTabs(List<TabConfigModel> tabs) async {
    state = state.copyWith(tabs: tabs);
    await _save();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    state = state.copyWith(notificationsEnabled: value);
    await _save();
  }

  Future<void> setNotifyReply(bool value) async {
    state = state.copyWith(notifyReply: value);
    await _save();
  }

  Future<void> setNotifyFollow(bool value) async {
    state = state.copyWith(notifyFollow: value);
    await _save();
  }

  Future<void> setNotifyReaction(bool value) async {
    state = state.copyWith(notifyReaction: value);
    await _save();
  }

  Future<void> setDateTimeRelative(bool value) async {
    state = state.copyWith(dateTimeRelative: value);
    await _save();
  }

  Future<void> setDefaultVisibility(String value) async {
    state = state.copyWith(defaultVisibility: value);
    await _save();
  }

  Future<void> setTimezoneOffsetHours(int? value) async {
    state = state.copyWith(timezoneOffsetHours: value);
    await _save();
  }

  Future<void> setConfirmDestructive(bool value) async {
    state = state.copyWith(confirmDestructive: value);
    await _save();
  }

  Future<void> setMfmAnimation(bool value) async {
    state = state.copyWith(mfmAnimation: value);
    await _save();
  }

  Future<void> setCollapseNote(bool value) async {
    state = state.copyWith(collapseNote: value);
    await _save();
  }

  Future<void> importSettings(AppSettingsModel settings) async {
    state = settings;
    await _save();
  }
}
