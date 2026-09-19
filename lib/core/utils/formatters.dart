/// 展示层的格式化工具（纯函数，便于测试）。
library;

const List<String> _sizeUnits = <String>['B', 'KB', 'MB', 'GB', 'TB'];

/// 把字节数格式化为人类可读的字符串，例如 `1.4 GB`。
///
/// 使用 1024 进制（与 iOS「设置 → 通用 → iPhone 储存空间」一致）。
String formatBytes(int bytes, {int fractionDigits = 1}) {
  if (bytes <= 0) return '0 B';

  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _sizeUnits.length - 1) {
    value /= 1024;
    unit++;
  }

  // 整数且单位是 B 时不显示小数位。
  final digits = unit == 0 ? 0 : fractionDigits;
  final text = value.toStringAsFixed(digits);
  // 去掉 "1.0" 这类多余的尾零。
  final trimmed = digits == 0 || !text.contains('.')
      ? text
      : text.replaceFirst(RegExp(r'\.?0+$'), '');

  return '$trimmed ${_sizeUnits[unit]}';
}

/// 把秒数格式化为 `1:05` / `1:02:03`。
String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.abs();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  String two(int value) => value.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:${two(minutes)}:${two(seconds)}';
  }
  return '$minutes:${two(seconds)}';
}

/// 把毫秒时长格式化为「1 分 05 秒」这样的中文描述。
String formatDurationText(Duration duration) {
  final totalSeconds = duration.inSeconds.abs();
  if (totalSeconds < 60) return '$totalSeconds 秒';
  final minutes = totalSeconds ~/ 60;
  if (minutes < 60) return '$minutes 分 ${totalSeconds % 60} 秒';
  final hours = minutes ~/ 60;
  return '$hours 小时 ${minutes % 60} 分';
}

/// `2024-05-06` 形式。
String formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// `2024-05-06 14:30` 形式。
String formatDateTime(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${formatDate(date)} ${two(date.hour)}:${two(date.minute)}';
}

/// 相对今天的口语化描述：`今天 14:30`、`昨天`、`3 天前`、`2024-05-06`。
///
/// [now] 仅用于测试注入。
String formatRelativeDate(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final target = DateTime(date.year, date.month, date.day);
  final diffDays = today.difference(target).inDays;

  String two(int value) => value.toString().padLeft(2, '0');

  if (diffDays == 0) return '今天 ${two(date.hour)}:${two(date.minute)}';
  if (diffDays == 1) return '昨天';
  if (diffDays > 1 && diffDays < 30) return '$diffDays 天前';
  if (diffDays < 0 && diffDays > -30) return '${-diffDays} 天后';
  return formatDate(date);
}

/// 带千位分隔符的计数，例如 `12,345`。
String formatCount(int count) {
  final text = count.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return count < 0 ? '-$buffer' : buffer.toString();
}

/// 百分比，例如 `72%`。
String formatPercent(double ratio, {int fractionDigits = 0}) {
  final clamped = ratio.isNaN ? 0.0 : ratio.clamp(0.0, 1.0);
  return '${(clamped * 100).toStringAsFixed(fractionDigits)}%';
}
