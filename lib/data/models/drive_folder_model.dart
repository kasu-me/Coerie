/// ドライブのフォルダ（drive/folders/*）。
class DriveFolderModel {
  final String id;
  final String name;

  /// 親フォルダ。ルート直下のフォルダでは null。
  final String? parentId;

  const DriveFolderModel({
    required this.id,
    required this.name,
    this.parentId,
  });

  factory DriveFolderModel.fromJson(Map<String, dynamic> json) {
    return DriveFolderModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      parentId: json['parentId'] as String?,
    );
  }
}
