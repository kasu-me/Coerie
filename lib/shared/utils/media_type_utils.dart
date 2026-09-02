/// 端末内のファイルを拡張子から種別判定するユーティリティ。
///
/// アップロード前のローカルファイルには MIME タイプが付かないため、Drive の
/// ファイル（`DriveFileModel.isImage` など）と違い拡張子で判定するしかない。
/// 判定に使う拡張子は image_picker / file_picker が返しうるものに合わせている。
library;

bool isImagePath(String path) {
  final s = path.toLowerCase();
  return s.endsWith('.png') ||
      s.endsWith('.jpg') ||
      s.endsWith('.jpeg') ||
      s.endsWith('.gif') ||
      s.endsWith('.webp') ||
      s.endsWith('.heic') ||
      s.endsWith('.heif');
}

bool isVideoPath(String path) {
  final s = path.toLowerCase();
  return s.endsWith('.mp4') ||
      s.endsWith('.mov') ||
      s.endsWith('.mkv') ||
      s.endsWith('.webm') ||
      s.endsWith('.3gp') ||
      s.endsWith('.avi');
}

bool isAudioPath(String path) {
  final s = path.toLowerCase();
  return s.endsWith('.mp3') ||
      s.endsWith('.wav') ||
      s.endsWith('.m4a') ||
      s.endsWith('.aac') ||
      s.endsWith('.ogg') ||
      s.endsWith('.flac');
}
