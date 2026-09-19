import 'package:flutter/material.dart';

/// 应用配色。
///
/// 全部写成明确的 ARGB 常量，不用 `withOpacity` / `withValues` 之类的
/// 辅助方法，避免不同 Flutter 版本之间的 API 差异。
class AppColors {
  const AppColors._();

  static const Color seed = Color(0xFF2F6BFF);

  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF30A46C);
  static const Color warning = Color(0xFFF5A524);

  /// 分类卡片配色。
  static const Color blue = Color(0xFF2F6BFF);
  static const Color purple = Color(0xFF8E4EC6);
  static const Color teal = Color(0xFF12A594);
  static const Color orange = Color(0xFFF76B15);
  static const Color pink = Color(0xFFE93D82);
  static const Color indigo = Color(0xFF3E63DD);
  static const Color brown = Color(0xFFAD7F58);

  /// 浅色背景上的半透明遮罩，用于图片上的文字。
  static const Color scrim = Color(0x99000000);
  static const Color scrimLight = Color(0x33000000);
}

/// 主题定义。
///
/// 刻意保持精简：不设置 `CardTheme`、`TabBarTheme` 这类会随 Flutter 版本
/// 改名的子主题，避免升级 SDK 时编译不过。
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      // 用 `InkRipple` 而不是 Material 3 默认的 `InkSparkle`。
      //
      // `InkSparkle` 需要加载并运行一段片元着色器（shaders/ink_sparkle.frag）：
      // 一是首帧会多一次着色器编译，在 iOS 15.5 这类老设备上有可见的卡顿；
      // 二是无 GPU 的 CI 环境里 `flutter test` 会因着色器无法通过运行时校验而
      // 直接抛异常，导致界面测试全红。水波纹是纯 Dart 实现，没有这些依赖。
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
