/// 这一次拖动被锁定在哪根轴上。
///
/// 手指几乎不可能走直线。不锁轴的话，「上滑删除」的卡片会一边往上飞
/// 一边左右歪，判定也会在上下与左右之间反复横跳。
enum SwipeAxis { none, vertical, horizontal }

/// 松手时给出的结论。
enum SwipeVerdict { delete, keep, undo }

/// 手指往哪边滑。
///
/// 一个结论可以由两个方向指向（下滑与左滑都是撤销），但一个方向只对应
/// 一个结论，所以徽标贴哪一端看的是方向，徽标上写什么看的是结论。
enum SwipeDirection { up, down, left, right }

/// 一张卡片当前的拖动状态。
///
/// 纯 Dart，刻意不引 `dart:ui`：这里全是数值比较，放在 core 里就能用普通
/// 单测把「滑多远 / 滑多快」的每种组合跑一遍，界面层只负责把
/// `GestureDetector` 的回调换算成这里的输入。
class SwipeGestureState {
  const SwipeGestureState._({
    required this.axis,
    this.offsetX = 0,
    this.offsetY = 0,
    double probeX = 0,
    double probeY = 0,
  })  : _probeX = probeX,
        _probeY = probeY;

  /// 还没有任何位移。
  static const SwipeGestureState idle = SwipeGestureState._(
    axis: SwipeAxis.none,
  );

  /// 把一段**已经算好**的位移直接解释成状态。
  ///
  /// 动画期间（卡片飞出屏幕、撤销时飞回来）位移是补间算出来的，不是手指
  /// 拖出来的，但蒙层、徽标、倾角得继续跟着走，所以要把它重新当成一次
  /// 拖动来看。这里既不做阻尼也不重判轴：传进来的位移本来就沿着轴走，
  /// 再来一遍会把它改小。
  factory SwipeGestureState.fromOffset(double x, double y) {
    if (x == 0 && y == 0) return idle;
    return SwipeGestureState._(
      axis: x.abs() >= y.abs() ? SwipeAxis.horizontal : SwipeAxis.vertical,
      offsetX: x,
      offsetY: y,
    );
  }

  final SwipeAxis axis;

  /// 卡片该往哪儿画。方向没定之前恒为 0，见 [dragBy]。
  final double offsetX;
  final double offsetY;

  /// 方向没定之前攒下来的位移，只用来判断往哪边滑。
  final double _probeX;
  final double _probeY;

  /// 超过这个位移才认定方向。再小的话手指的抖动就会被当成一次横滑。
  static const double axisLockDistance = 12;

  /// 「往前走一步」（删除、保留）要滑过的比例。
  ///
  /// 用屏幕长短边的比例而不是固定像素，是为了在小屏和大屏上手感一致。
  static const double commitFraction = 0.22;

  /// 「撤销」（左滑、下滑）要滑过的比例。
  ///
  /// 比删除的线更远：撤销会打断已经建立的节奏，不该被误触。
  static const double undoFraction = 0.30;

  /// 甩动的速度超过这个值（像素/秒）就算数，不必滑够距离。
  ///
  /// 快速上滑一下是比慢慢拖到底更自然的操作。
  static const double commitVelocity = 800;

  /// 每个结论的距离判定线（占总长/总宽的比例）。
  ///
  /// **同一个结论只允许一条线**：删除与保留都是往前走一步，共用
  /// [commitFraction]；两个撤销共用 [undoFraction]。否则同一个动作会因为
  /// 拖的方向不同而手感不同。
  static const Map<SwipeVerdict, double> thresholds = <SwipeVerdict, double>{
    SwipeVerdict.delete: commitFraction,
    SwipeVerdict.keep: commitFraction,
    SwipeVerdict.undo: undoFraction,
  };

  /// 拖到这个比例时，蒙层与徽标达到满强度。
  static const double fullFraction = 0.45;

  /// 横向拖动时的最大倾角（弧度）。
  static const double maxTilt = 0.18;

  bool get isIdle =>
      axis == SwipeAxis.none && _probeX == 0 && _probeY == 0;

  /// 叠加上一次位移，返回新状态。
  SwipeGestureState dragBy(double dx, double dy) {
    if (axis == SwipeAxis.none) {
      // 方向还没定，先把这段位移攒着，卡片先不动：手指刚落下时难免抖出
      // 一段斜着走的位移，立刻照做会让卡片乱晃。
      final probeX = _probeX + dx;
      final probeY = _probeY + dy;
      final locked = _lockAxis(probeX, probeY);
      if (locked == SwipeAxis.none) {
        return SwipeGestureState._(
          axis: SwipeAxis.none,
          probeX: probeX,
          probeY: probeY,
        );
      }
      // 定下来了：把攒下的位移交给选中的那根轴重走一遍，另一根轴连同
      // 它的分量一起丢掉。
      return SwipeGestureState._(axis: locked).dragBy(probeX, probeY);
    }

    // 左右都是真动作（左滑撤销、右滑保留），一律跟手。
    if (axis == SwipeAxis.horizontal) {
      return SwipeGestureState._(axis: axis, offsetX: offsetX + dx);
    }
    return SwipeGestureState._(axis: axis, offsetY: offsetY + dy);
  }

  /// 当前滑向哪一边；还没定轴或位移为零时为 `null`。
  SwipeDirection? get direction {
    switch (axis) {
      case SwipeAxis.vertical:
        if (offsetY < 0) return SwipeDirection.up;
        if (offsetY > 0) return SwipeDirection.down;
        return null;
      case SwipeAxis.horizontal:
        return offsetX < 0 ? SwipeDirection.left : SwipeDirection.right;
      case SwipeAxis.none:
        return null;
    }
  }

  /// 拖动过程中该显示什么徽标；`null` 表示什么都不显示。
  SwipeVerdict? get intent {
    switch (direction) {
      case SwipeDirection.up:
        return SwipeVerdict.delete;
      case SwipeDirection.down || SwipeDirection.left:
        return SwipeVerdict.undo;
      case SwipeDirection.right:
        return SwipeVerdict.keep;
      case null:
        return null;
    }
  }

  /// 松手时该判定成什么；`null` 表示没到线，卡片弹回原位。
  SwipeVerdict? verdictAtEnd({
    required double velocityX,
    required double velocityY,
    required double extentX,
    required double extentY,
  }) {
    // 又短又快的甩动可能还没攒够距离就松手了，轴向都还没锁上。这时改由
    // 速度定方向，否则一次干脆的快速上滑会被当成「没滑」。
    final dragged = direction;
    final flung = _directionFromSpeed(velocityX, velocityY);
    // 拖到一半反手甩回去：这是「反悔」，让干脆的甩动说了算。只认同一根轴
    // 上的反向——拖歪了顺手横向甩一下，不该把整张卡片的结论改掉。
    final resolved =
        dragged != null && flung != null && _opposes(dragged, flung)
            ? flung
            : (dragged ?? flung);
    final verdict = switch (resolved) {
      SwipeDirection.up => SwipeVerdict.delete,
      SwipeDirection.down || SwipeDirection.left => SwipeVerdict.undo,
      SwipeDirection.right => SwipeVerdict.keep,
      null => null,
    };
    if (verdict == null || resolved == null) return null;

    final horizontal = resolved == SwipeDirection.left ||
        resolved == SwipeDirection.right;
    // 朝正方向（下/右）记正号，朝负方向（上/左）记负号，于是「够不够远」
    // 可以一律写成 >=：距离和速度都得顺着这个方向来才算数。
    final sign = (resolved == SwipeDirection.down ||
            resolved == SwipeDirection.right)
        ? 1.0
        : -1.0;
    final offset = (horizontal ? offsetX : offsetY) * sign;
    final velocity = (horizontal ? velocityX : velocityY) * sign;
    final extent = horizontal ? extentX : extentY;

    if (offset >= extent * thresholds[verdict]! ||
        velocity >= commitVelocity) {
      return verdict;
    }
    return null;
  }

  /// 0 到 1 之间的强度，用来决定蒙层深浅与徽标透明度。
  double progress({required double extentX, required double extentY}) {
    final extent = axis == SwipeAxis.horizontal ? extentX : extentY;
    if (extent <= 0) return 0;
    final distance = axis == SwipeAxis.horizontal ? offsetX.abs() : offsetY.abs();
    return (distance / (extent * fullFraction)).clamp(0.0, 1.0);
  }

  /// 卡片倾斜的弧度。
  ///
  /// 只有横向拖动才倾：竖直方向的位移用不上「甩出去」的暗示，
  /// 让卡片歪着往上飞反而像出了故障。
  double tiltRadians({required double extentX}) {
    if (axis != SwipeAxis.horizontal || extentX <= 0) return 0;
    return offsetX / extentX * maxTilt;
  }

  static SwipeAxis _lockAxis(double x, double y) {
    if (x.abs() < axisLockDistance && y.abs() < axisLockDistance) {
      return SwipeAxis.none;
    }
    return x.abs() > y.abs() ? SwipeAxis.horizontal : SwipeAxis.vertical;
  }

  /// 两个方向是不是在同一根轴上刚好相反。
  static bool _opposes(SwipeDirection a, SwipeDirection b) => switch (a) {
        SwipeDirection.up => b == SwipeDirection.down,
        SwipeDirection.down => b == SwipeDirection.up,
        SwipeDirection.left => b == SwipeDirection.right,
        SwipeDirection.right => b == SwipeDirection.left,
      };

  static SwipeDirection? _directionFromSpeed(double velocityX, double velocityY) {
    if (velocityX.abs() < commitVelocity && velocityY.abs() < commitVelocity) {
      return null;
    }
    if (velocityX.abs() > velocityY.abs()) {
      return velocityX < 0 ? SwipeDirection.left : SwipeDirection.right;
    }
    return velocityY < 0 ? SwipeDirection.up : SwipeDirection.down;
  }
}
