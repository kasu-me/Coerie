part of 'draft_model.dart';

class DraftModelAdapter extends TypeAdapter<DraftModel> {
  @override
  final int typeId = 0;

  @override
  DraftModel read(BinaryReader reader) {
    final id = reader.readString();
    final text = reader.readString();
    final visibility = reader.readString();
    final savedAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());

    List<DriveFileModel> files = [];
    if (reader.availableBytes > 0) {
      final fileStrings = reader.readStringList();
      files = fileStrings
          .map((s) {
            try {
              return DriveFileModel.fromJson(
                jsonDecode(s) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<DriveFileModel>()
          .toList();
    }

    String? cw;
    if (reader.availableBytes > 0) {
      final cwRaw = reader.readString();
      cw = cwRaw.isEmpty ? null : cwRaw;
    }

    bool isSensitive = false;
    if (reader.availableBytes > 0) {
      isSensitive = reader.readInt() == 1;
    }

    // 第5世代: localFiles。旧レコードには後続バイトが無いので空で読む。
    List<DraftLocalFileModel> localFiles = [];
    if (reader.availableBytes > 0) {
      final localStrings = reader.readStringList();
      localFiles = localStrings
          .map((s) {
            try {
              return DraftLocalFileModel.fromJson(
                jsonDecode(s) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<DraftLocalFileModel>()
          .toList();
    }

    // 第6世代: 返信先/引用元。旧レコードには後続バイトが無いので null で読む。
    final replyId = _readNullableString(reader);
    final replyAcct = _readNullableString(reader);
    final renoteId = _readNullableString(reader);
    final renoteAcct = _readNullableString(reader);

    return DraftModel(
      id: id,
      text: text,
      visibility: visibility,
      savedAt: savedAt,
      files: files,
      cw: cw,
      isSensitive: isSensitive,
      localFiles: localFiles,
      replyId: replyId,
      replyAcct: replyAcct,
      renoteId: renoteId,
      renoteAcct: renoteAcct,
    );
  }

  @override
  void write(BinaryWriter writer, DraftModel obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.text);
    writer.writeString(obj.visibility);
    writer.writeInt(obj.savedAt.millisecondsSinceEpoch);
    writer.writeStringList(
      obj.files.map((f) => jsonEncode(f.toJson())).toList(),
    );
    writer.writeString(obj.cw ?? '');
    writer.writeInt(obj.isSensitive ? 1 : 0);
    writer.writeStringList(
      obj.localFiles.map((f) => jsonEncode(f.toJson())).toList(),
    );
    writer.writeString(obj.replyId ?? '');
    writer.writeString(obj.replyAcct ?? '');
    writer.writeString(obj.renoteId ?? '');
    writer.writeString(obj.renoteAcct ?? '');
  }

  /// 末尾に追加された nullable な文字列を読む。
  /// 未保存（旧レコード）と空文字はどちらも null として扱う。
  static String? _readNullableString(BinaryReader reader) {
    if (reader.availableBytes <= 0) return null;
    final value = reader.readString();
    return value.isEmpty ? null : value;
  }
}
