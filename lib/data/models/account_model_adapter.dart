part of 'account_model.dart';

class AccountModelAdapter extends TypeAdapter<AccountModel> {
  @override
  final int typeId = 1;

  @override
  AccountModel read(BinaryReader reader) {
    return AccountModel(
      id: reader.readString(),
      host: reader.readString(),
      token: reader.readString(),
      userId: reader.readString(),
      username: reader.readString(),
      name: reader.readString(),
      avatarUrl: reader.readBool() ? reader.readString() : null,
      isActive: reader.readBool(),
    );
  }

  @override
  void write(BinaryWriter writer, AccountModel obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.host);
    writer.writeString(obj.token);
    writer.writeString(obj.userId);
    writer.writeString(obj.username);
    writer.writeString(obj.name);
    final hasAvatar = obj.avatarUrl != null;
    writer.writeBool(hasAvatar);
    if (hasAvatar) writer.writeString(obj.avatarUrl!);
    writer.writeBool(obj.isActive);
  }
}
