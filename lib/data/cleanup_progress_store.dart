import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/cleanup_progress.dart';

/// 清理进度的存放处。
///
/// 抽成接口是为了让单测不必碰 SharedPreferences，也方便以后换成文件。
abstract class CleanupProgressStore {
  Future<Map<String, CleanupProgress>> load();

  Future<void> save(Map<String, CleanupProgress> all);
}

/// 落到 SharedPreferences。
///
/// 数据规模很小——几个作用域，每个约两百字节——不值得为它引入文件系统。
/// 版本号写进键名而不是值里：格式一变，旧数据直接失效，不用写迁移逻辑。
class PreferencesCleanupProgressStore implements CleanupProgressStore {
  const PreferencesCleanupProgressStore();

  static const String key = 'cleanup_progress_v1';

  @override
  Future<Map<String, CleanupProgress>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, CleanupProgress>{};

    // 存档坏了（写了一半被杀、被别的版本覆写过）时当作没有进度：
    // 丢掉一次断点只是从头再看一遍，抛异常会让时间线整个打不开。
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return <String, CleanupProgress>{};
    }
    if (decoded is! Map) return <String, CleanupProgress>{};

    final result = <String, CleanupProgress>{};
    for (final entry in decoded.entries) {
      final scope = entry.key;
      final value = entry.value;
      if (scope is! String || value is! Map) continue;
      final progress = CleanupProgress.fromJson(
        scope,
        value.cast<String, Object?>(),
      );
      if (progress != null) result[scope] = progress;
    }
    return result;
  }

  @override
  Future<void> save(Map<String, CleanupProgress> all) async {
    final prefs = await SharedPreferences.getInstance();
    if (all.isEmpty) {
      await prefs.remove(key);
      return;
    }

    await prefs.setString(
      key,
      jsonEncode(<String, Object?>{
        for (final entry in all.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}

/// 只放在内存里，测试用。
class MemoryCleanupProgressStore implements CleanupProgressStore {
  Map<String, CleanupProgress> _data = <String, CleanupProgress>{};

  int saveCount = 0;

  @override
  Future<Map<String, CleanupProgress>> load() async =>
      Map<String, CleanupProgress>.of(_data);

  @override
  Future<void> save(Map<String, CleanupProgress> all) async {
    saveCount++;
    _data = Map<String, CleanupProgress>.of(all);
  }
}
