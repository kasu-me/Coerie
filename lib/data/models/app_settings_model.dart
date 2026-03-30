import 'dart:convert';

class TabConfigModel {
  final String id;
  final String label;
  final String type;

  const TabConfigModel({
    required this.id,
    required this.label,
    required this.type,
  });

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'type': type};

  factory TabConfigModel.fromJson(Map<String, dynamic> json) => TabConfigModel(
    id: json['id'] as String,
    label: json['label'] as String,
    type: json['type'] as String,
  );

  TabConfigModel copyWith({String? id, String? label, String? type}) =>
      TabConfigModel(
        id: id ?? this.id,
        label: label ?? this.label,
        type: type ?? this.type,
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
  );

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
      );

  factory AppSettingsModel.fromJsonString(String jsonString) =>
      AppSettingsModel.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());
}
