import 'package:hive_flutter/hive_flutter.dart';

part 'draft_model_adapter.dart';

class DraftModel {
  final String id;
  final String text;
  final String visibility;
  final DateTime savedAt;

  DraftModel({
    required this.id,
    required this.text,
    required this.visibility,
    required this.savedAt,
  });
}
