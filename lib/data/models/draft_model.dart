import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'note_model.dart';

part 'draft_model_adapter.dart';

class DraftModel {
  final String id;
  final String text;
  final String visibility;
  final DateTime savedAt;
  final List<DriveFileModel> files;
  final String? cw;
  final bool isSensitive;

  DraftModel({
    required this.id,
    required this.text,
    required this.visibility,
    required this.savedAt,
    this.files = const [],
    this.cw,
    this.isSensitive = false,
  });
}
