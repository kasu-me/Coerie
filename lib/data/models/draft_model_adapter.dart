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

    return DraftModel(
      id: id,
      text: text,
      visibility: visibility,
      savedAt: savedAt,
      files: files,
      cw: cw,
      isSensitive: isSensitive,
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
  }
}
