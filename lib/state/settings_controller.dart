import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/cleanup_analyzer.dart';
import '../core/services/similarity_grouper.dart';
import '../core/utils/blur_analyzer.dart';

/// 用户在设置页里能调的参数。
///
/// 这些值直接决定 [CleanupAnalyzer] 的行为，改动后会重新计算分类。
class SettingsController extends ChangeNotifier {
  SettingsController({SharedPreferences? preferences})
      : _preferences = preferences;

  static const String _keySimilarity = 'similarity_preset';
  static const String _keyBlurThreshold = 'blur_threshold';
  static const String _keyLargeVideoMb = 'large_video_mb';
  static const String _keyLargePhotoMb = 'large_photo_mb';
  static const String _keyAutoAnalyze = 'auto_analyze';

  SharedPreferences? _preferences;

  SimilarityOptions _similarity = SimilarityOptions.balanced;
  double _blurThreshold = BlurAnalyzer.defaultThreshold;
  int _largeVideoMb = CleanupAnalyzer.defaultLargeVideoBytes ~/ (1024 * 1024);
  int _largePhotoMb = CleanupAnalyzer.defaultLargePhotoBytes ~/ (1024 * 1024);
  bool _autoAnalyze = true;
  bool _loaded = false;

  /// 相似度档位。
  SimilarityOptions get similarity => _similarity;

  /// 模糊判定阈值，越小越严格。
  double get blurThreshold => _blurThreshold;

  /// 超过该体积的视频算「超大视频」。
  int get largeVideoMb => _largeVideoMb;

  /// 超过该体积的照片算「超大照片」。
  int get largePhotoMb => _largePhotoMb;

  /// 加载完成后是否自动开始扫描重复 / 模糊照片。
  bool get autoAnalyze => _autoAnalyze;

  bool get isLoaded => _loaded;

  /// 生成当前设置对应的分析器。
  CleanupAnalyzer buildAnalyzer() {
    return CleanupAnalyzer(
      similarity: _similarity,
      blurThreshold: _blurThreshold,
      largeVideoBytes: _largeVideoMb * 1024 * 1024,
      largePhotoBytes: _largePhotoMb * 1024 * 1024,
    );
  }

  /// 从本地存储读取设置。失败时保持默认值。
  Future<void> load() async {
    try {
      final preferences = _preferences ??= await SharedPreferences.getInstance();
      final preset = preferences.getString(_keySimilarity);
      _similarity = switch (preset) {
        'strict' => SimilarityOptions.strict,
        'loose' => SimilarityOptions.loose,
        _ => SimilarityOptions.balanced,
      };
      _blurThreshold =
          preferences.getDouble(_keyBlurThreshold) ?? BlurAnalyzer.defaultThreshold;
      _largeVideoMb = preferences.getInt(_keyLargeVideoMb) ?? _largeVideoMb;
      _largePhotoMb = preferences.getInt(_keyLargePhotoMb) ?? _largePhotoMb;
      _autoAnalyze = preferences.getBool(_keyAutoAnalyze) ?? true;
    } catch (_) {
      // 读不到就用默认值，不影响使用。
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSimilarity(SimilarityOptions options) async {
    if (_similarity == options) return;
    _similarity = options;
    notifyListeners();
    await _preferences?.setString(_keySimilarity, _presetName(options));
  }

  Future<void> setBlurThreshold(double value) async {
    final clamped = value.clamp(10.0, 1000.0);
    if (_blurThreshold == clamped) return;
    _blurThreshold = clamped;
    notifyListeners();
    await _preferences?.setDouble(_keyBlurThreshold, clamped);
  }

  Future<void> setLargeVideoMb(int value) async {
    final clamped = value.clamp(10, 5000);
    if (_largeVideoMb == clamped) return;
    _largeVideoMb = clamped;
    notifyListeners();
    await _preferences?.setInt(_keyLargeVideoMb, clamped);
  }

  Future<void> setLargePhotoMb(int value) async {
    final clamped = value.clamp(1, 500);
    if (_largePhotoMb == clamped) return;
    _largePhotoMb = clamped;
    notifyListeners();
    await _preferences?.setInt(_keyLargePhotoMb, clamped);
  }

  Future<void> setAutoAnalyze(bool value) async {
    if (_autoAnalyze == value) return;
    _autoAnalyze = value;
    notifyListeners();
    await _preferences?.setBool(_keyAutoAnalyze, value);
  }

  static String _presetName(SimilarityOptions options) {
    if (options.maxDistance <= SimilarityOptions.strict.maxDistance) {
      return 'strict';
    }
    if (options.maxDistance >= SimilarityOptions.loose.maxDistance) {
      return 'loose';
    }
    return 'balanced';
  }
}
