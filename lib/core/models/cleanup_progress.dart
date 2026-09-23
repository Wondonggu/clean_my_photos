import 'media_item.dart';

/// 进度作用域的键。
///
/// 用字符串而不是枚举：相册 id 要到运行时才知道。键是不透明的，只用来
/// 查表，不需要反解析出相册名——名字单独存在 [CleanupProgress.label] 里。
abstract final class CleanupScopes {
  static const String timeline = 'timeline';

  static String album(String albumId) => 'album:$albumId';

  static String category(String typeName) => 'category:$typeName';
}

/// 一次清理进行到哪儿了。
///
/// 断点用「下一张要看的是谁」表示，而不是「刚处理完的是谁」：这样重开时
/// 落回的就是当初没来得及处理的那一张，不会重复看一遍刚决定过的照片。
class CleanupProgress {
  const CleanupProgress({
    required this.scope,
    required this.label,
    this.anchorId,
    this.anchorDate,
    this.roundStartDate,
    this.processed = 0,
    this.deleted = 0,
    this.reclaimedBytes = 0,
    this.updatedAt,
  });

  /// 见 [CleanupScopes]。
  final String scope;

  /// 给人看的名字（「时间线」「截图」……），用于首页和横幅。
  final String label;

  /// 下一张要看的条目的 id。
  final String? anchorId;

  /// 同一个条目的拍摄时间，作为 id 失效时的兜底水位。
  final DateTime? anchorDate;

  /// 这一轮开始清理时，列表里最新那张照片的时间。
  ///
  /// 拿它和当前列表比一比就知道中途有没有新照片进来——那些排在锚点上方、
  /// 永远不会被这一轮看到。
  final DateTime? roundStartDate;

  final int processed;
  final int deleted;
  final int reclaimedBytes;
  final DateTime? updatedAt;

  bool get isEmpty => processed == 0 && deleted == 0;

  CleanupProgress copyWith({
    String? label,
    String? anchorId,
    DateTime? anchorDate,
    DateTime? roundStartDate,
    int? processed,
    int? deleted,
    int? reclaimedBytes,
    DateTime? updatedAt,
    bool clearAnchor = false,
  }) {
    return CleanupProgress(
      scope: scope,
      label: label ?? this.label,
      anchorId: clearAnchor ? null : (anchorId ?? this.anchorId),
      anchorDate: clearAnchor ? null : (anchorDate ?? this.anchorDate),
      roundStartDate: roundStartDate ?? this.roundStartDate,
      processed: processed ?? this.processed,
      deleted: deleted ?? this.deleted,
      reclaimedBytes: reclaimedBytes ?? this.reclaimedBytes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'label': label,
        'anchorId': anchorId,
        'anchorDate': anchorDate?.toIso8601String(),
        'roundStartDate': roundStartDate?.toIso8601String(),
        'processed': processed,
        'deleted': deleted,
        'reclaimedBytes': reclaimedBytes,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  /// 从存档里恢复；字段缺失或类型不对时返回 null，当作没有这条进度。
  ///
  /// 宁可丢掉一条进度重新开始，也不能让一条坏数据把时间线卡在打不开的状态。
  static CleanupProgress? fromJson(String scope, Map<String, Object?> json) {
    final label = json['label'];
    if (label is! String) return null;

    return CleanupProgress(
      scope: scope,
      label: label,
      anchorId: json['anchorId'] as String?,
      anchorDate: _date(json['anchorDate']),
      roundStartDate: _date(json['roundStartDate']),
      processed: _int(json['processed']),
      deleted: _int(json['deleted']),
      reclaimedBytes: _int(json['reclaimedBytes']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static int _int(Object? value) => value is int && value >= 0 ? value : 0;
}

/// 断点在列表里的下标。
///
/// 列表是按拍摄时间倒序的（整库、相册、时间线都是这个顺序），所以锚点
/// 之后的条目一定更老。
///
/// 找不找得到锚点这件事本身不可靠：那张照片可能已经被删掉了——上次会话删的、
/// 在别的设备上删的、在这个 App 的另一个作用域里删的。所以用 id 和日期两个锚，
/// id 没了就退到日期水位，用户不至于被扔回列表开头重看一遍。
///
/// 返回的下标可以直接当作滑动清理页的 `startIndex`。
int resolveStartIndex(List<MediaItem> items, CleanupProgress? progress) {
  if (items.isEmpty) return 0;

  final anchorId = progress?.anchorId;
  if (anchorId != null) {
    final index = items.indexWhere((item) => item.id == anchorId);
    if (index >= 0) return index;
  }

  final anchorDate = progress?.anchorDate;
  if (anchorDate != null) {
    final index = items.indexWhere((item) {
      final date = item.createdAt;
      return date != null && date.isBefore(anchorDate);
    });
    if (index >= 0) return index;
    // 列表里没有比锚点更老的了：锚点要么是最后一张、要么比现存最老的还老，
    // 两种情况都说明这一轮已经看到底了。
    return items.length;
  }

  return 0;
}

/// 锚点上方有多少张是这一轮开始之后才出现的。
///
/// 倒序列表意味着新照片落在锚点**上方**，这一轮永远走不到它们。数量对不上
/// 时宁可多提示一次，也不要让用户以为「都清完了」。
int countNewerThanRoundStart(
  List<MediaItem> items,
  CleanupProgress? progress,
) {
  final start = progress?.roundStartDate;
  if (start == null) return 0;
  return items.where((item) {
    final date = item.createdAt;
    return date != null && date.isAfter(start);
  }).length;
}
