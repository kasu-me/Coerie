part of 'draft_model.dart';

class DraftModelAdapter extends TypeAdapter<DraftModel> {
  @override
  final int typeId = 0;

  @override
  DraftModel read(BinaryReader reader) {
    return DraftModel(
      id: reader.readString(),
      text: reader.readString(),
      visibility: reader.readString(),
      savedAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
    );
  }

  @override
  void write(BinaryWriter writer, DraftModel obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.text);
    writer.writeString(obj.visibility);
    writer.writeInt(obj.savedAt.millisecondsSinceEpoch);
  }
}
