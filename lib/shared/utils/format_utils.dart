/// 日時・サイズの表示整形ユーティリティ。
///
/// intl はプロジェクトの直接依存ではないため、必要な書式のみ手組みで用意する。
library;

String _p2(int v) => v.toString().padLeft(2, '0');

/// `yyyy/MM/dd`
String formatYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}/${_p2(d.month)}/${_p2(d.day)}';

/// `HH:mm`
String formatHm(DateTime d) => '${_p2(d.hour)}:${_p2(d.minute)}';

/// `HH:mm:ss`
String formatHms(DateTime d) => '${formatHm(d)}:${_p2(d.second)}';

/// `yyyy/MM/dd HH:mm`
String formatYmdHm(DateTime d) => '${formatYmd(d)} ${formatHm(d)}';

/// `yyyy/MM/dd HH:mm:ss`
String formatYmdHms(DateTime d) => '${formatYmd(d)} ${formatHms(d)}';

/// 現在時刻からの経過を「◯秒前 / ◯分前 / ◯時間前」で表す。
/// 24時間を超えたものは `M/D`（端末のローカル時刻）で表す。
String formatRelativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
  if (diff.inHours < 24) return '${diff.inHours}時間前';
  final local = dt.toLocal();
  return '${local.month}/${local.day}';
}

/// 投稿日時を設定に応じて整形する。
///
/// [relative] が true なら [formatRelativeTime]、false なら絶対表記。
/// [timezoneOffsetHours] が指定された場合は端末のタイムゾーンではなく
/// その UTC オフセットで表示する。
String formatNoteDateTime(
  DateTime dt, {
  required bool relative,
  int? timezoneOffsetHours,
}) {
  if (relative) return formatRelativeTime(dt);
  final d = timezoneOffsetHours != null
      ? dt.toUtc().add(Duration(hours: timezoneOffsetHours))
      : dt.toLocal();
  return formatYmdHms(d);
}

/// バイト数を人が読みやすい単位に変換する。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  double value = bytes / 1024;
  int unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unitIndex]}';
}
