import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/background_task.dart';
import 'data/photo_manager_repository.dart';
import 'data/photo_repository.dart';
import 'data/scan_cache.dart';
import 'data/thumbnail_cache.dart';
import 'state/cleanup_progress_controller.dart';
import 'state/library_controller.dart';
import 'state/settings_controller.dart';
import 'ui/home/home_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/global_task_bar.dart';

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

class _CleanMyPhotosAppState extends State<CleanMyPhotosApp>
    with WidgetsBindingObserver {
  late final PhotoRepository _repository;
  late final ThumbnailCache _thumbnailCache;
  late final SettingsController _settings;
  late final CleanupProgressController _progress;
  late final ScanCache _scanCache;
  late final FileSizeCache _sizeCache;
  late final BackgroundTaskGuard _backgroundTasks;
  late final LibraryController _library;

  /// 切到后台时申请的延长执行令牌。
  Object? _lifecycleToken;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PhotoManagerRepository();
    _thumbnailCache = ThumbnailCache(_repository);
    _settings = SettingsController();
    _progress = CleanupProgressController();

    // 扫描结果是边算边落盘的：切走、被杀、重开都接得上。
    _scanCache = ScanCache();
    _sizeCache = FileSizeCache();
    // 只有真实数据源才去问系统要延长执行时间；测试和预览里注入的假仓库不该
    // 触发平台通道。
    _backgroundTasks = ChannelBackgroundTaskGuard(
      isSupportedPlatform: _repository is PhotoManagerRepository,
    );

    _library = LibraryController(
      repository: _repository,
      settings: _settings,
      cache: _scanCache,
      sizeCache: _sizeCache,
      backgroundTasks: _backgroundTasks,
    );

    // 设置变化后重新计算相似度分组与阈值。
    _settings.addListener(_library.onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _settings.load();
    // 读进度比读相册便宜得多，但也要在读相册之前完成：
    // 首页的「继续清理」一出现就该是对的，不能先空一下再补。
    await _progress.load();
    if (!mounted) return;
    await _library.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 攒批写盘的最后一道保险：切走或被杀之前把最近的滑动落进去。
    _progress.flush();
    _settings.removeListener(_library.onSettingsChanged);
    _library.dispose();
    _progress.dispose();
    _settings.dispose();
    unawaited(_backgroundTasks.release(_lifecycleToken));
    super.dispose();
  }

  /// 切到后台时，替正在跑的扫描再争取一点时间。
  ///
  /// 注意这只买到几十秒：真正让「切回来不用重扫」成立的是增量落盘，
  /// 这里只是让「正好还剩最后一批」的情况能收尾。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (_library.isBusy && _lifecycleToken == null) {
          unawaited(_holdBackgroundTime());
        }
      case AppLifecycleState.resumed:
        unawaited(_backgroundTasks.release(_lifecycleToken));
        _lifecycleToken = null;
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _holdBackgroundTime() async {
    final token = await _backgroundTasks.acquire('扫描相册');
    // 这中间可能已经切回前台并还掉了，那就别再留着。
    if (token == null) return;
    if (_library.isBusy) {
      _lifecycleToken = token;
    } else {
      await _backgroundTasks.release(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // 不写显式泛型：`SingleChildWidget` 来自 provider 的内部依赖包，
      // 直接引用会触发 depend_on_referenced_packages 检查。
      providers: [
        Provider<PhotoRepository>.value(value: _repository),
        Provider<ThumbnailCache>.value(value: _thumbnailCache),
        ChangeNotifierProvider<CleanupProgressController>.value(value: _progress),
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
        // 任务条挂在这里，才能在任何页面都看得见。
        builder: (BuildContext context, Widget? child) => Stack(
          children: <Widget>[
            child ?? const SizedBox.shrink(),
            const GlobalTaskBar(),
          ],
        ),
        home: const HomePage(),
      ),
    );
  }
}
