part of 'account_model.dart';

class AccountModelAdapter extends TypeAdapter<AccountModel> {
  @override
  final int typeId = 1;

  // フィールドを追加するときは必ず末尾に追記すること。
  // 旧バージョンで保存されたレコードには後続バイトが存在しないため、
  // availableBytes を確認してから読み、無ければ既定値を使う。
  // avatarUrl は「フラグ＋本体」の2段構えなので、フラグを読んだあとにも確認する。
  // （フィールドの削除・並べ替え・型変更は既存データを読めなくするため不可）
  @override
  AccountModel read(BinaryReader reader) {
    final id = reader.readString();
    final host = reader.readString();
    final token = reader.readString();
    final userId = reader.readString();
    final username = reader.readString();
    final name = reader.readString();

    String? avatarUrl;
    if (reader.availableBytes > 0) {
      final hasAvatar = reader.readBool();
      if (hasAvatar && reader.availableBytes > 0) {
        avatarUrl = reader.readString();
      }
    }

    bool isActive = false;
    if (reader.availableBytes > 0) {
      isActive = reader.readBool();
    }

    return AccountModel(
      id: id,
      host: host,
      token: token,
      userId: userId,
      username: username,
      name: name,
      avatarUrl: avatarUrl,
      isActive: isActive,
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
