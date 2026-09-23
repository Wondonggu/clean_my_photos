import 'media_item.dart';

/// 一条落盘的文件大小。
///
/// iOS 上没有批量取文件大小的接口，只能逐个问系统；三万个条目就是三万次
/// 平台调用，而大小几乎是不会变的。存下来，下次启动直接用。
///
/// [modifiedAt] 是「还作不作数」的依据：照片被编辑过（裁剪、加滤镜）之后
/// 文件会重写，大小也跟着变。两边有一边拿不到修改时间时只能选择相信缓存——
/// 总比每次都重新问一遍强，而且 iOS 上绝大多数照片都带着修改时间。
class FileSizeRecord {
  const FileSizeRecord({
    required this.id,
    required this.size,
    this.modifiedAt,
  });

  final String id;
  final int size;
  final DateTime? modifiedAt;

  /// 这条记录对 [item] 还成立吗。
  bool matches(MediaItem item) {
    if (size <= 0) return false;
    final known = modifiedAt;
    final current = item.modifiedAt;
    if (known == null || current == null) return true;
    return known == current;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'size': size,
        if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
      };

  static FileSizeRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final size = raw['size'];
    if (id is! String || id.isEmpty || size is! int || size <= 0) return null;

    final modified = raw['modifiedAt'];
    return FileSizeRecord(
      id: id,
      size: size,
      modifiedAt: modified is String ? DateTime.tryParse(modified) : null,
    );
  }

  @override
  String toString() => 'FileSizeRecord($id, $size)';
}
