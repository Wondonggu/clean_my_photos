import UIKit
import Flutter
import Photos

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let messenger = controller.binaryMessenger

      FlutterMethodChannel(
        name: "clean_my_photos/asset_locator",
        binaryMessenger: messenger
      ).setMethodCallHandler { call, result in
        AssetLocator.handle(call, result: result)
      }

      FlutterMethodChannel(
        name: "clean_my_photos/background_task",
        binaryMessenger: messenger
      ).setMethodCallHandler { call, result in
        BackgroundTaskBridge.handle(call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// 申请一段「别急着挂起我」的时间。
///
/// 注意 `beginBackgroundTask` 只买到**有界**的窗口（大约 30 秒），到点系统
/// 照样挂起。它只是让「切走时正好还剩最后一批」的情况能跑完，真正保证
/// 「切回来能接着清」的是 Dart 侧的增量落盘。
enum BackgroundTaskBridge {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "begin":
      result(begin())
    case "end":
      let raw = (call.arguments as? [String: Any])?["id"] as? NSNumber
      if let raw = raw {
        UIApplication.shared.endBackgroundTask(
          UIBackgroundTaskIdentifier(rawValue: raw.intValue))
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 返回系统给的令牌；系统不给（后台刷新被关、已经在前台之外等）时返回 nil。
  private static func begin() -> NSNumber? {
    var identifier = UIBackgroundTaskIdentifier.invalid

    identifier = UIApplication.shared.beginBackgroundTask(
      withName: "clean_my_photos.scan"
    ) {
      // 到点了：系统会在这之后挂起 App，先把令牌还回去。
      if identifier != .invalid {
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
      }
    }

    guard identifier != .invalid else { return nil }
    return NSNumber(value: identifier.rawValue)
  }
}

/// 反查「这张照片在系统『照片』App 里属于哪些相册」。
///
/// `photo_manager` 只有「相册 → 条目」这一个方向，而 PhotoKit 的
/// `fetchAssetCollectionsContaining` 正好是反向，所以这段只能自己接。
///
/// 写在这里而不是新建一个 Swift 文件：新建文件要手改 `project.pbxproj`
/// 的四处（PBXBuildFile、PBXFileReference、group 子项、Sources 阶段），
/// 而 AppDelegate 本来就在编译列表里。
enum AssetLocator {
  /// 相册大到这个程度就不再算「第几张」了：为了一个序号遍历两万条不划算。
  static let maxCountForIndex = 5000

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "locateAsset" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard
      let args = call.arguments as? [String: Any],
      let assetId = args["assetId"] as? String
    else {
      result(FlutterError(code: "badArgs", message: "缺少 assetId", details: nil))
      return
    }

    // 相册遍历可能读到几千条记录，别堵住主线程；算完再回主线程答复。
    DispatchQueue.global(qos: .userInitiated).async {
      let payload = locate(assetId: assetId)
      DispatchQueue.main.async { result(payload) }
    }
  }

  static func locate(assetId: String) -> [String: Any] {
    guard
      let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        .firstObject
    else {
      // 已经不在相册里了：别的设备删的，或者上一次会话删的。
      return ["assetId": assetId, "albums": [], "status": "notFound"]
    }

    var albums: [[String: Any]] = []
    var seen = Set<String>()

    func add(_ collection: PHAssetCollection, kind: String) {
      let id = collection.localIdentifier
      guard !seen.contains(id) else { return }
      seen.insert(id)

      var entry: [String: Any] = [
        "albumId": id,
        "name": collection.localizedTitle ?? "",
        "kind": kind,
      ]

      // 序号要和 App 里的顺序对得上：一律按拍摄时间倒序。
      let options = PHFetchOptions()
      options.sortDescriptors = [
        NSSortDescriptor(key: "creationDate", ascending: false)
      ]
      let assets = PHAsset.fetchAssets(in: collection, options: options)
      if assets.count > 0 && assets.count <= maxCountForIndex {
        let position = self.index(of: asset, in: assets)
        if position >= 0 {
          entry["index"] = position + 1
          entry["assetCount"] = assets.count
        }
      }

      albums.append(entry)
    }

    // 用户相册和智能相册得分两次取：只要 `.album` 拿不到「截图」这类，
    // 只要 `.smartAlbum` 又拿不到用户自己建的。
    let userAlbums = PHAssetCollection.fetchAssetCollectionsContaining(
      asset, with: .album, options: nil)
    userAlbums.enumerateObjects { collection, _, _ in
      add(collection, kind: "user")
    }

    let smartAlbums = PHAssetCollection.fetchAssetCollectionsContaining(
      asset, with: .smartAlbum, options: nil)
    smartAlbums.enumerateObjects { collection, _, _ in
      add(collection, kind: "smart")
    }

    // 「最近项目 / 相机胶卷」是 smartAlbum 里的 `smartAlbumUserLibrary`，
    // 而 `fetchAssetCollectionsContaining` 拿不到它——PhotoKit 的老坑，
    // 只能反过来问这本相册里有没有它。
    let libraries = PHAssetCollection.fetchAssetCollections(
      with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
    libraries.enumerateObjects { collection, _, _ in
      if contains(asset, in: collection) {
        add(collection, kind: "smart")
      }
    }

    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    return [
      "assetId": assetId,
      "albums": albums,
      "isLimited": status == .limited,
    ]
  }

  /// 这张照片在 [assets] 里排第几（0 起），找不到返回 -1。
  ///
  /// `PHFetchResult.index(of:)` 按对象身份比较，而这里的 `asset` 来自另一次
  /// 查询，身份往往对不上、返回 `NSNotFound`，所以还要按 localIdentifier
  /// 自己扫一遍兜底。没有 `enumerateObjects` 的提前退出，就是因为它不支持。
  static func index(of asset: PHAsset, in assets: PHFetchResult<PHAsset>) -> Int {
    let direct = assets.index(of: asset)
    if direct != NSNotFound { return direct }

    let total = assets.count
    for position in 0..<total {
      if assets.object(at: position).localIdentifier == asset.localIdentifier {
        return position
      }
    }
    return -1
  }

  /// 这本相册里有没有这张照片。
  ///
  /// 用谓词按 localIdentifier 过滤并且只取一条，避免把整本相册拉出来。
  /// 万一系统忽略了谓词（智能相册上偶有发生），拿到的是「相册非空」——
  /// 对「最近项目」来说这本来也总是成立的，所以最坏情况不会更差。
  static func contains(_ asset: PHAsset, in collection: PHAssetCollection) -> Bool {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
      format: "localIdentifier == %@", asset.localIdentifier)
    options.fetchLimit = 1
    return PHAsset.fetchAssets(in: collection, options: options).count > 0
  }
}
