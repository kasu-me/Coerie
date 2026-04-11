class PollChoiceModel {
  final String text;
  final int votes;
  final bool isVoted;

  const PollChoiceModel({
    required this.text,
    this.votes = 0,
    this.isVoted = false,
  });

  factory PollChoiceModel.fromJson(dynamic raw) {
    if (raw is String) {
      return PollChoiceModel(text: raw, votes: 0, isVoted: false);
    }
    if (raw is Map<String, dynamic>) {
      final text = (raw['text'] ?? raw['name'] ?? '') as String;
      final votes = (raw['count'] ?? raw['votes'] ?? 0) as int;
      final isVoted = (raw['voted'] ?? raw['isVoted'] ?? false) as bool;
      return PollChoiceModel(text: text, votes: votes, isVoted: isVoted);
    }
    return PollChoiceModel(
      text: raw?.toString() ?? '',
      votes: 0,
      isVoted: false,
    );
  }

  Map<String, dynamic> toJson() => {'text': text};
}

class PollModel {
  final bool multiple;
  final DateTime? expiresAt;
  final List<PollChoiceModel> choices;

  const PollModel({
    this.multiple = false,
    this.expiresAt,
    this.choices = const [],
  });

  factory PollModel.fromJson(Map<String, dynamic> json) {
    final multiple = json['multiple'] as bool? ?? false;
    DateTime? expiresAt;
    final exp = json['expiresAt'];
    if (exp != null) {
      try {
        expiresAt = DateTime.parse(exp as String);
      } catch (_) {
        if (exp is int) expiresAt = DateTime.fromMillisecondsSinceEpoch(exp);
      }
    }
    final rawChoices = json['choices'] as List<dynamic>? ?? [];
    final choices = rawChoices.map((c) => PollChoiceModel.fromJson(c)).toList();
    return PollModel(
      multiple: multiple,
      expiresAt: expiresAt,
      choices: choices,
    );
  }

  /// Create payload suitable for `notes/create` API's `poll` parameter.
  Map<String, dynamic> toCreateJson() {
    final map = <String, dynamic>{
      'choices': choices.map((c) => c.text).toList(),
      'multiple': multiple,
    };
    if (expiresAt != null) map['expiresAt'] = expiresAt!.toIso8601String();
    return map;
  }
}
