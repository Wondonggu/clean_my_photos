/// 这一次拖动被锁定在哪根轴上。
///
/// 手指几乎不可能走直线。不锁轴的话，「上滑删除」的卡片会一边往上飞
/// 一边左右歪，判定也会在上下与左右之间反复横跳。
enum SwipeAxis { none, vertical, horizontal }

/// 松手时给出的结论。
enum SwipeVerdict { delete, keep, undo }

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

  /// 竖直方向滑过屏幕高度的这个比例，松手就判定。
  ///
  /// 用高度的比例而不是固定像素，是为了在小屏和大屏上手感一致。
  static const double commitFraction = 0.22;

  /// 左滑撤销要滑过宽度的这个比例。
  ///
  /// 比删除的线更远：撤销会打断已经建立的节奏，不该被误触。
  static const double undoFraction = 0.30;

  /// 甩动的速度超过这个值（像素/秒）就算数，不必滑够距离。
  ///
  /// 快速上滑一下是比慢慢拖到底更自然的操作。
  static const double commitVelocity = 800;

  /// 右滑的阻尼系数。
  ///
  /// 右滑没有对应操作，让它跟一点点再弹回去，比完全不跟手更好懂。
  static const double resistance = 0.25;

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

    if (axis == SwipeAxis.horizontal) {
      // 右滑走阻尼，左滑照常跟手。
      return SwipeGestureState._(
        axis: axis,
        offsetX: offsetX + (dx > 0 ? dx * resistance : dx),
      );
    }
    return SwipeGestureState._(axis: axis, offsetY: offsetY + dy);
  }

  /// 拖动过程中该显示什么徽标；`null` 表示什么都不显示。
  ///
  /// 右滑永远是「什么都没发生」，所以不给徽标——显示了撤销又不撤销，
  /// 比不显示更让人困惑。
  SwipeVerdict? get intent {
    switch (axis) {
      case SwipeAxis.vertical:
        if (offsetY < 0) return SwipeVerdict.delete;
        if (offsetY > 0) return SwipeVerdict.keep;
        return null;
      case SwipeAxis.horizontal:
        return offsetX < 0 ? SwipeVerdict.undo : null;
      case SwipeAxis.none:
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
    // 速度定轴，否则一次干脆的快速上滑会被当成「没滑」。
    final locked =
        axis != SwipeAxis.none ? axis : _axisFromSpeed(velocityX, velocityY);

    switch (locked) {
      case SwipeAxis.vertical:
        if (offsetY <= -extentY * commitFraction ||
            velocityY <= -commitVelocity) {
          return SwipeVerdict.delete;
        }
        if (offsetY >= extentY * commitFraction ||
            velocityY >= commitVelocity) {
          return SwipeVerdict.keep;
        }
        return null;
      case SwipeAxis.horizontal:
        // 只有左滑算数。右滑即便甩得再快也弹回，否则「撤销」会误触发。
        if (offsetX <= -extentX * undoFraction ||
            velocityX <= -commitVelocity) {
          return SwipeVerdict.undo;
        }
        return null;
      case SwipeAxis.none:
        return null;
    }
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

  static SwipeAxis _axisFromSpeed(double velocityX, double velocityY) {
    if (velocityX.abs() < commitVelocity && velocityY.abs() < commitVelocity) {
      return SwipeAxis.none;
    }
    return velocityX.abs() > velocityY.abs()
        ? SwipeAxis.horizontal
        : SwipeAxis.vertical;
  }
}
