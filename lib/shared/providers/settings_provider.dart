import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_settings_model.dart';
import '../../core/constants/app_constants.dart';

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettingsModel>(
      (ref) => SettingsNotifier(),
    );

class SettingsNotifier extends StateNotifier<AppSettingsModel> {
  SettingsNotifier() : super(const AppSettingsModel()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(AppConstants.settingsKey);
    if (jsonStr != null) {
      state = AppSettingsModel.fromJsonString(jsonStr);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.settingsKey, state.toJsonString());
  }

  Future<void> setTheme(String theme) async {
    state = state.copyWith(theme: theme);
    await _save();
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size);
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
}
