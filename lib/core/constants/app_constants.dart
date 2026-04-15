class AppConstants {
  AppConstants._();

  static const String appName = 'Coerie';
  static const int defaultNoteLimit = 3000;

  // Hive box names
  static const String draftsBox = 'drafts';
  static const String accountsBox = 'accounts';

  // SharedPreferences keys
  static const String settingsKey = 'app_settings';

  // Misskey visibility
  static const String visibilityPublic = 'public';
  static const String visibilityHome = 'home';
  static const String visibilityFollowers = 'followers';
  static const String visibilitySpecified = 'specified';

  // Tab types
  static const String tabTypeHome = 'home';
  static const String tabTypeLocal = 'local';
  static const String tabTypeSocial = 'social';
  static const String tabTypeGlobal = 'global';
  static const String tabTypeNotifications = 'notifications';
  static const String tabTypeList = 'list';
  static const String tabTypeAntenna = 'antenna';
  static const String tabTypeChannel = 'channel';

  static const Map<String, String> visibilityLabels = {
    visibilityPublic: '全体公開',
    visibilityHome: 'ホームのみ',
    visibilityFollowers: 'フォロワーのみ',
    visibilitySpecified: 'ユーザー指定',
  };

  static const Map<String, String> tabTypeLabels = {
    tabTypeHome: 'ホーム',
    tabTypeLocal: 'ローカル',
    tabTypeSocial: 'ソーシャル',
    tabTypeGlobal: '連合',
    tabTypeNotifications: '通知',
    tabTypeList: 'リスト',
    tabTypeAntenna: 'アンテナ',
    tabTypeChannel: 'チャンネル',
  };
}
