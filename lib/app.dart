import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/photo_manager_repository.dart';
import 'data/photo_repository.dart';
import 'data/thumbnail_cache.dart';
import 'state/library_controller.dart';
import 'state/settings_controller.dart';
import 'ui/home/home_page.dart';
import 'ui/theme/app_theme.dart';

/// 应用根组件。
///
/// 负责把数据层、状态层通过 Provider 注入，并在启动时完成
/// 「读设置 → 检查权限 → 加载相册」这条链路。
class CleanMyPhotosApp extends StatefulWidget {
  const CleanMyPhotosApp({super.key, this.repository});

  /// 允许注入别的数据源（测试 / 预览用），默认使用真实相册。
  final PhotoRepository? repository;

  @override
  State<CleanMyPhotosApp> createState() => _CleanMyPhotosAppState();
}

class _CleanMyPhotosAppState extends State<CleanMyPhotosApp> {
  late final PhotoRepository _repository;
  late final ThumbnailCache _thumbnailCache;
  late final SettingsController _settings;
  late final LibraryController _library;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PhotoManagerRepository();
    _thumbnailCache = ThumbnailCache(_repository);
    _settings = SettingsController();
    _library = LibraryController(repository: _repository, settings: _settings);

    // 设置变化后重新计算相似度分组与阈值。
    _settings.addListener(_library.onSettingsChanged);

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _settings.load();
    if (!mounted) return;
    await _library.initialize();
  }

  @override
  void dispose() {
    _settings.removeListener(_library.onSettingsChanged);
    _library.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // 不写显式泛型：`SingleChildWidget` 来自 provider 的内部依赖包，
      // 直接引用会触发 depend_on_referenced_packages 检查。
      providers: [
        Provider<PhotoRepository>.value(value: _repository),
        Provider<ThumbnailCache>.value(value: _thumbnailCache),
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
        ChangeNotifierProvider<LibraryController>.value(value: _library),
      ],
      child: MaterialApp(
        title: '相册清理',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // 界面文案全部是中文，因此固定使用简体中文，
        // 让系统组件（日期、弹窗按钮等）与应用文案保持一致。
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomePage(),
      ),
    );
  }
}
