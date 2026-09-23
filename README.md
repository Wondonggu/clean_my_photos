# 相册清理（Clean My Photos）

用 Flutter 写的 iOS 相册清理工具，目标系统 **iOS 15.5 及以上**。

它会扫描系统相册，找出**重复照片、相似照片、截图、屏幕录制、模糊照片、超大视频/照片**，
给出「保留哪一张、删掉哪些」的建议，确认后调用系统相册接口批量删除。

- 所有图像分析都在本机完成，照片不会上传到任何服务器；
- 删除前必须二次确认，系统还会再弹一次确认框；
- 收藏的照片永远不会被建议删除，界面上也不允许勾选；
- 删除的照片进入系统「最近删除」，30 天内可以恢复。

清理有两条路：

- **按问题清**（首页那几个分类）：重复、相似、截图……回答的是「清什么」；
- **按时间清**（右上角「时间线」与「相册」）：按自然日分段或整本相册翻着清，
  回答的是「什么时候拍的」。两条路都走同一套手势——**上滑删除、下滑保留、
  左滑撤销**，滑到底之后再一次性确认。中途退出会记下落点，下次进来接着清。

---

## 目录结构

```
lib/
  core/                 与 Flutter 无关的纯 Dart 逻辑（可单测，不碰平台 API）
    models/             MediaItem / MediaGroup / CleanupCategory / AssetSignature
                        CleanupProgress（清理落点）/ SwipeGestureState（手势状态机）
                        落盘用的记录：AssetFingerprintRecord / FileSizeRecord
    services/           感知哈希分析、相似度聚类、保留项选择、清理分类
    utils/              感知哈希、模糊度检测、灰度图、日期分段、格式化、取消信号
  data/                 相册数据层
    photo_repository.dart         抽象接口（界面只依赖它，方便注入假实现）
    photo_manager_repository.dart 基于 photo_manager 的真实实现
    thumbnail_cache.dart          缩略图 LRU 缓存
    cleanup_progress_store.dart   清理进度的落盘（SharedPreferences）
    scan_cache.dart               分析结果的落盘（JSONL，见「扫描为什么不用等」）
    background_task.dart          向 iOS 申请一段延长执行时间
    asset_locator_channel.dart    反查照片属于哪些相册（原生通道）
  state/                provider + ChangeNotifier 状态
    library_controller.dart  权限 → 读取相册 → 图像分析 → 大小扫描 → 生成建议
    cleanup_progress_controller.dart  各作用域的清理落点
    selection_controller.dart 勾选状态
    settings_controller.dart  用户偏好（持久化到 SharedPreferences）
  ui/                   界面
    home/               首页（相册概况 + 各分类入口）
    review/             分类复核页、照片网格、重复照片分组
    swipe/              滑动清理（上滑删、下滑留、左滑撤销）
    viewer/             全屏查看器（可缩放，显示照片的相册归属）
    browse/             时间线（按自然日分段，可整条或逐日清理）
    albums/             相册浏览与整本清理
    settings/           设置
    permission/         权限引导
    widgets/, theme/    公共组件与主题（含全局任务条）
test/
  core/                 纯逻辑单测
  data/                 存储层单测（含文件实现与降级路径）
  state/                状态层单测（缓存的复用与失效）
  widget/               界面测试（用假相册跑完整流程）
  helpers/              假数据与假仓库
```

分层的原则：`core/` 不引用 Flutter，`ui/` 不直接调用 `photo_manager`。
因此「找重复、判模糊」这类最容易出错的逻辑可以在 Ubuntu 上直接跑测试验证。

---

## 在 Ubuntu 上开发

本机不需要 macOS，也不需要 Android SDK：界面逻辑全部可以用假数据测试。

```bash
flutter pub get
flutter analyze
flutter test
```

> ⚠️ 如果本机配了 `http_proxy` / `ALL_PROXY` 之类的环境变量，`flutter test` 会
> 因为代理拦截了 `flutter_tester` 的 localhost WebSocket 而失败。用
> `env -u http_proxy -u https_proxy -u ALL_PROXY flutter test` 绕开即可。

**iOS 只能在 macOS 上编译**，所以在 Ubuntu 上无法 `flutter build ios`。
iOS 的编译、签名与上传全部交给 Codemagic（见下）。

---

## 在 Codemagic 上构建 iOS

仓库根目录的 [`codemagic.yaml`](codemagic.yaml) 定义了两个工作流：

| 工作流 | 用途 | 需要 Apple 账号 |
| --- | --- | --- |
| `ios-unsigned-check` | `pub get` → `analyze` → `test` → `flutter build ios --no-codesign`，并校验产物确实是 iOS 15.5 | 不需要 |
| `ios-release` | 签名打包 ipa，上传 TestFlight（打 `v*` tag 时触发） | 需要 |

### 1. 先跑通不需要签名的那条

把仓库接到 Codemagic，直接跑 `ios-unsigned-check`。
它会验证代码能编译、测试能过，并检查 `Runner.app` 的 `MinimumOSVersion` 就是 `15.5`
（`ios-release` 里也有一模一样的检查）。

### 2. 配置签名（跑 `ios-release` 前）

1. **App Store Connect API key**：App Store Connect → *用户和访问* → *集成* → *App Store Connect API*
   新建一个 **App Manager** 权限的 key，下载 `.p8`（只能下一次）。
2. 在 Codemagic 的 **Team settings → Team integrations → Developer Portal** 里添加这个 key，
   给它起个名字，然后把 `codemagic.yaml` 里 `integrations.app_store_connect` 的值改成这个名字
   （现在是占位值 `clean_my_photos_asc`）。
3. 在 **Team settings → codemagic.yaml settings → Code signing identities** 里准备好
   iOS 发布证书与描述文件；`ios_signing` 那一节会让 Codemagic 自动装到构建机上。
4. 在 App Store Connect 里**手动创建一次 App 记录**（Bundle ID `com.cleanphotos.cleanMyPhotos`），
   并把它的数字 Apple ID 填到 `environment.vars.APP_STORE_APP_ID`。
   没填（保持 `0`）也能打 ipa，只是构建号会退化成用 Codemagic 的流水号。

之后打一个 `v1.0.0` 这样的 tag 就会自动出包并上传 TestFlight。

---

## iOS 15.5 是怎么配的

四处必须保持一致，改一处要改全部：

| 位置 | 值 |
| --- | --- |
| `ios/Runner.xcodeproj/project.pbxproj` 里的 `IPHONEOS_DEPLOYMENT_TARGET`（Debug/Release/Profile 三处） | `15.5` |
| `ios/Flutter/AppFrameworkInfo.plist` 的 `MinimumOSVersion` | `15.5` |
| `ios/Podfile` 的 `platform :ios` | `'15.5'` |
| `codemagic.yaml` 里的一致性检查脚本 | `15.5` |

为什么是 15.5 而不是更低：

- 目标机型是 iPhone 6s 及之后的设备，它们能升级到的最后一个大版本就是 iOS 15；
- **Flutter 3.47 起最低支持 iOS 15**，再往下配也没有意义。

`codemagic.yaml` 的两个工作流都会在构建后读产物里的 `MinimumOSVersion`，
对不上就直接让构建失败——避免哪天被误改回 11.0 却没人发现。

### 权限文案

`ios/Runner/Info.plist`：

- `NSPhotoLibraryUsageDescription` —— 读取相册必须；
- `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = true` —— 关掉 iOS 在「有限访问」
  模式下自动弹出的提示。App 自己会在首页顶部显示一条「只允许访问部分照片」的横幅，
  并提供「更改」按钮打开系统的照片选择器，不需要系统再插一脚。

如果以后加了「保存到相册」之类的功能，记得补一个 `NSPhotoLibraryAddUsageDescription`。

---

## 清理逻辑是怎么判断的

| 分类 | 判断方式 |
| --- | --- |
| 重复照片 | dHash 感知哈希完全相同（汉明距离 0），不看拍摄时间 |
| 相似照片 | 拍摄时间在时间窗口内、宽高比接近、哈希距离 ≤ 阈值；单链接聚类成组 |
| 模糊照片 | 缩略图的拉普拉斯方差低于阈值。分辨率过低或接近纯色的图不参与判定（结果不可靠） |
| 截图 / 录屏 | 读 iOS 智能相册「截图」「屏幕录制」，另有文件名启发式兜底 |
| 超大视频 / 照片 | 文件体积超过设置里的门槛；录屏单独归类，不重复计入 |

几个刻意的取舍：

- **收藏优先**：分组时优先保留收藏的照片，其次本地文件优先于 iCloud 占位符，
  然后是分辨率、清晰度、体积。整组都是收藏时不给出任何删除建议。
- **宁可少判，不可错判**：相似度默认用「均衡」档；模糊检测在缩略图太小时直接放弃判定
  而不是硬猜。设置页可以把三条阈值都调严或调松。
- **可释放空间按 id 去重**：一张模糊的截图会同时命中两个分类，但只统计一次。
- **图像分析在 isolate 里跑**：解码 + 哈希 + 拉普拉斯都在后台 isolate，
  读满一屏就能先出结果，不必等全部分析完。
- **缓存里只存客观量**：落盘的是哈希和清晰度，不是「算不算模糊」。
  模糊阈值是用户偏好，存在缓存里的话，拖一次设置页的滑杆整份缓存就废了。

---

## 扫描为什么不用等

图像分析和文件大小扫描都是几分钟量级的事，而用户完全可以一边扫一边翻相册。
做法是**每算完一批就立刻落盘**，于是：

- 进度条挂在 `MaterialApp.builder` 上，**任何页面都看得见**，还能随时取消；
- 切到别的 App 再回来，接着算没算完的那部分；
- **杀掉进程重开也不用从头再算**——上次算到哪就是哪；
- 已经算过的照片不会重复请求缩略图，界面会说明「已复用 N 条缓存」。

指望系统在后台把任务跑完是另一条路，但 iOS 上走不通：`beginBackgroundTask`
只买到几十秒，`BGProcessingTask` 由系统择机调度（常常要等充电空闲），
还可能几十分钟后才跑、且跑在独立进程里读不到内存状态，照样得重扫。
所以后台任务只用来给「正好还剩最后一批」收尾，**正确性靠的是增量落盘**。

落盘格式是一行一条 JSON，首行写着这份数据按什么参数算出来的
（指纹是 `v1-t256-q75`）。参数一变，**整份作废**，而不是逐条判断新旧——
比逐条判断便宜，也不会留下半新半旧的混合体。指纹键里刻意不含模糊阈值，
原因见上。

设置页有「清空扫描缓存」。缓存文件放在 App 沙盒的 Application Support 目录，
测试环境拿不到平台目录时自动退到内存，功能照常，只是这次不落盘。

---

## 已知限制

- **iOS 上的「有限访问」**：用户只授权部分照片时，结果自然不完整，首页会提示并可跳转修改。
- **文件大小是逐个查的**：iOS 没有批量接口，为了不让超大相册卡住，默认最多查 4000 个文件的大小，
  且优先查视频和像素最多的照片。已经量过的会先剔出候选，不占这 4000 个名额；
  照片被编辑过（修改时间变了）会重新量一次。设置页可以手动重新扫描。
- **「切走后一定跑完」做不到**：`beginBackgroundTask` 的窗口有界（约 30 秒），
  到点系统照样挂起。增量落盘把代价从「全部重来」降到「只差最后一批」，
  但不是「一定跑完」。
- **超大相册会有上限**：一次最多读取 30000 条，超出时首页会提示本次只读了一部分。
- **视频不参与相似度分组**：视频只能拿封面帧做哈希，误判率明显高于照片，因此默认关掉。
- **断点会跳过新照片**：清理进度按「下一张要看的」记，而列表是时间倒序的，
  所以断点之后新拍的照片落在断点上方，这一轮看不到。时间线会显式提示有多少张，
  并提供「从头看一遍」。
- **单日清理不记进度**：从时间线的某一天进去清理不写存档——一天的量有限，
  走完就走完了，记下来只会攒出一堆再也用不到的作用域。
- **「所在相册」只在 iOS 上有**：反查照片属于哪些相册要用 PhotoKit 的
  `fetchAssetCollectionsContaining`，`photo_manager` 没有这个方向，所以走的是
  `ios/Runner/AppDelegate.swift` 里的原生通道。Android 上按目录名只能猜个大概，
  与其给个半准的答案，不如明说「当前平台不支持」。
- **Linux 上跑不了 iOS**：本地只能验证纯逻辑与界面（`flutter test`），iOS 编译必须走 Codemagic。
