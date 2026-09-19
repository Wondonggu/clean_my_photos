/// 与具体插件解耦的媒体条目模型。
///
/// 界面层和算法层只依赖这个模型，不依赖 `photo_manager`，
/// 因此所有清理逻辑都可以在纯 Dart 单元测试中验证。
library;

/// 媒体的基础类型。
enum MediaKind {
  image('图片'),
  video('视频'),
  audio('音频'),
  other('其他');

  const MediaKind(this.label);

  /// 中文显示名。
  final String label;

  static MediaKind fromName(String? name) {
    switch (name?.toLowerCase()) {
      case 'image':
        return MediaKind.image;
      case 'video':
        return MediaKind.video;
      case 'audio':
        return MediaKind.audio;
      default:
        return MediaKind.other;
    }
  }
}

/// 相册中的一个媒体条目（照片 / 视频）。
class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    this.title,
    this.createdAt,
    this.modifiedAt,
    this.width = 0,
    this.height = 0,
    this.size = 0,
    this.duration = Duration.zero,
    this.isFavorite = false,
    this.isHidden = false,
    this.isLivePhoto = false,
    this.isScreenshot = false,
    this.isScreenRecording = false,
    this.isLocallyAvailable = true,
    this.mimeType,
    this.relativePath,
  });

  /// 系统相册中的唯一标识。
  final String id;

  final MediaKind kind;

  /// 原始文件名，可能为空（例如 iOS 的云同步资源）。
  final String? title;

  final DateTime? createdAt;
  final DateTime? modifiedAt;

  final int width;
  final int height;

  /// 文件大小（字节）。系统未提供时为 0，请改用 [effectiveSize]。
  final int size;

  final Duration duration;

  final bool isFavorite;
  final bool isHidden;
  final bool isLivePhoto;

  /// 屏幕截图（iOS: `PHAssetMediaSubtype.photoScreenshot`）。
  final bool isScreenshot;

  /// 屏幕录制（iOS: `PHAssetMediaSubtype.videoScreenRecording`）。
  ///
  /// 系统未提供该信息时，数据层会退化为按文件名判断。
  final bool isScreenRecording;

  /// 文件是否在本地。iOS 上可能只是一个尚未下载的 iCloud 占位符。
  final bool isLocallyAvailable;

  final String? mimeType;
  final String? relativePath;

  bool get isVideo => kind == MediaKind.video;

  double get aspectRatio {
    if (height == 0) return 1;
    return width / height;
  }

  int get pixelCount => width * height;

  /// 用于展示与统计的字节数。
  ///
  /// 系统没有返回大小时（常见于 iCloud 照片），按像素数做一个保守估算：
  /// JPEG 压缩后大致为 0.35 字节/像素。该估算只影响「预计可释放空间」的展示，
  /// 不影响删除对象的选择。
  int get effectiveSize {
    if (size > 0) return size;
    if (pixelCount == 0) return 0;
    return (pixelCount * 0.35).round();
  }

  /// 分辨率越高、文件越大，通常画质越好。用于「保留哪一张」的打分。
  int get resolutionScore => pixelCount;

  /// 时长（秒），仅视频有意义。
  int get durationSeconds => duration.inSeconds;

  /// 补上真实文件大小（相册元数据里拿不到，需要单独查询）。
  MediaItem withSize(int bytes) {
    if (bytes <= 0 || bytes == size) return this;
    return copyWith(size: bytes);
  }

  MediaItem copyWith({String? id, bool? isFavorite, int? size}) {
    return MediaItem(
      id: id ?? this.id,
      kind: kind,
      title: title,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      width: width,
      height: height,
      size: size ?? this.size,
      duration: duration,
      isFavorite: isFavorite ?? this.isFavorite,
      isHidden: isHidden,
      isLivePhoto: isLivePhoto,
      isScreenshot: isScreenshot,
      isScreenRecording: isScreenRecording,
      isLocallyAvailable: isLocallyAvailable,
      mimeType: mimeType,
      relativePath: relativePath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MediaItem && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'MediaItem($id, ${kind.name}, ${width}x$height, '
      '${effectiveSize}B${isScreenshot ? ', screenshot' : ''})';
}
