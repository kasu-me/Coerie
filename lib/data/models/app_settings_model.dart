import 'dart:convert';

class TabConfigModel {
  final String id;
  final String label;
  final String type;
  final String? sourceId; // リスト/アンテナタブ用のID

  const TabConfigModel({
    required this.id,
    required this.label,
    required this.type,
    this.sourceId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type,
    if (sourceId != null) 'sourceId': sourceId,
  };

  factory TabConfigModel.fromJson(Map<String, dynamic> json) => TabConfigModel(
    id: json['id'] as String,
    label: json['label'] as String,
    type: json['type'] as String,
    sourceId: json['sourceId'] as String?,
  );

  TabConfigModel copyWith({
    String? id,
    String? label,
    String? type,
    String? sourceId,
  }) => TabConfigModel(
    id: id ?? this.id,
    label: label ?? this.label,
    type: type ?? this.type,
    sourceId: sourceId ?? this.sourceId,
  );
}

class AppSettingsModel {
  final String theme; // 'light', 'dark', 'system'
  final double fontSize;
  final bool realtimeUpdate;
  final List<TabConfigModel> tabs;
  final bool notificationsEnabled;
  final bool notifyReply;
  final bool notifyFollow;
  final bool notifyReaction;
  final bool dateTimeRelative; // true=相対表示, false=絶対表示
  final String defaultVisibility; // 投稿のデフォルト公開範囲
  final int? timezoneOffsetHours; // null=デバイスのローカルタイムゾーン, 数値=UTC+N
  final bool confirmDestructive; // 破壊的操作の確認ダイアログを表示する
  final bool mfmAnimation; // MFMアニメーションを有効にする（デフォルト: false=静的表示）
  final bool collapseNote; // 長い投稿を省略表示する（デフォルト: true）
  final double avatarRadius; // タイムラインのユーザーアイコンの半径（デフォルト: 20.0）

  const AppSettingsModel({
    this.theme = 'system',
    this.fontSize = 14.0,
    this.realtimeUpdate = true,
    this.tabs = const [],
    this.notificationsEnabled = true,
    this.notifyReply = true,
    this.notifyFollow = true,
    this.notifyReaction = true,
    this.dateTimeRelative = true,
    this.defaultVisibility = 'public',
    this.timezoneOffsetHours,
    this.confirmDestructive = false,
    this.mfmAnimation = false,
    this.collapseNote = true,
    this.avatarRadius = 20.0,
  });

  AppSettingsModel copyWith({
    String? theme,
    double? fontSize,
    bool? realtimeUpdate,
    List<TabConfigModel>? tabs,
    bool? notificationsEnabled,
    bool? notifyReply,
    bool? notifyFollow,
    bool? notifyReaction,
    bool? dateTimeRelative,
    String? defaultVisibility,
    Object? timezoneOffsetHours = _sentinel,
    bool? confirmDestructive,
    bool? mfmAnimation,
    bool? collapseNote,
    double? avatarRadius,
  }) => AppSettingsModel(
    theme: theme ?? this.theme,
    fontSize: fontSize ?? this.fontSize,
    realtimeUpdate: realtimeUpdate ?? this.realtimeUpdate,
    tabs: tabs ?? this.tabs,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    notifyReply: notifyReply ?? this.notifyReply,
    notifyFollow: notifyFollow ?? this.notifyFollow,
    notifyReaction: notifyReaction ?? this.notifyReaction,
    dateTimeRelative: dateTimeRelative ?? this.dateTimeRelative,
    defaultVisibility: defaultVisibility ?? this.defaultVisibility,
    timezoneOffsetHours: identical(timezoneOffsetHours, _sentinel)
        ? this.timezoneOffsetHours
        : timezoneOffsetHours as int?,
    confirmDestructive: confirmDestructive ?? this.confirmDestructive,
    mfmAnimation: mfmAnimation ?? this.mfmAnimation,
    collapseNote: collapseNote ?? this.collapseNote,
    avatarRadius: avatarRadius ?? this.avatarRadius,
  );

  static const Object _sentinel = Object();

  Map<String, dynamic> toJson() => {
    'theme': theme,
    'fontSize': fontSize,
    'realtimeUpdate': realtimeUpdate,
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'notificationsEnabled': notificationsEnabled,
    'notifyReply': notifyReply,
    'notifyFollow': notifyFollow,
    'notifyReaction': notifyReaction,
    'dateTimeRelative': dateTimeRelative,
    'defaultVisibility': defaultVisibility,
    if (timezoneOffsetHours != null) 'timezoneOffsetHours': timezoneOffsetHours,
    'confirmDestructive': confirmDestructive,
    'mfmAnimation': mfmAnimation,
    'collapseNote': collapseNote,
    'avatarRadius': avatarRadius,
  };

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) =>
      AppSettingsModel(
        theme: json['theme'] as String? ?? 'system',
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        realtimeUpdate: json['realtimeUpdate'] as bool? ?? true,
        tabs: (json['tabs'] as List<dynamic>? ?? [])
            .map((t) => TabConfigModel.fromJson(t as Map<String, dynamic>))
            .toList(),
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        notifyReply: json['notifyReply'] as bool? ?? true,
        notifyFollow: json['notifyFollow'] as bool? ?? true,
        notifyReaction: json['notifyReaction'] as bool? ?? true,
        dateTimeRelative: json['dateTimeRelative'] as bool? ?? true,
        defaultVisibility: json['defaultVisibility'] as String? ?? 'public',
        timezoneOffsetHours: json['timezoneOffsetHours'] as int?,
        confirmDestructive: json['confirmDestructive'] as bool? ?? false,
        mfmAnimation: json['mfmAnimation'] as bool? ?? false,
        collapseNote: json['collapseNote'] as bool? ?? true,
        avatarRadius: (json['avatarRadius'] as num?)?.toDouble() ?? 20.0,
      );

  factory AppSettingsModel.fromJsonString(String jsonString) =>
      AppSettingsModel.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());
}
