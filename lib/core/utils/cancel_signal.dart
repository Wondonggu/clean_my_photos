/// 一个可以取消长耗时操作的信号。
///
/// 相册扫描可能持续几十秒，用户随时可能想退出或者换个分类看看；
/// 与其强杀任务，不如让任务在每个循环里主动检查这个标记。
class CancelSignal {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// 若已取消则抛出 [OperationCancelled]，用于在深层调用栈里提前退出。
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelled();
  }
}

/// 操作被用户取消。
class OperationCancelled implements Exception {
  const OperationCancelled();

  @override
  String toString() => '操作已取消';
}
