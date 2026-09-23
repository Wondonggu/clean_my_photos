import 'package:clean_my_photos/core/models/swipe_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 一部 iPhone 13 的逻辑尺寸。阈值按屏幕比例算，用真实数字更好对照。
  const extentX = 390.0;
  const extentY = 844.0;

  SwipeVerdict? settle(
    SwipeGestureState state, {
    double velocityX = 0,
    double velocityY = 0,
  }) =>
      state.verdictAtEnd(
        velocityX: velocityX,
        velocityY: velocityY,
        extentX: extentX,
        extentY: extentY,
      );

  group('轴向锁定', () {
    test('位移还没超过死区时，卡片一动不动', () {
      final state = SwipeGestureState.idle.dragBy(6, 5);

      expect(state.axis, SwipeAxis.none);
      expect(state.offsetX, 0);
      expect(state.offsetY, 0);
      expect(state.isIdle, isFalse);
    });

    test('死区内攒下的位移在锁定那一帧一次补齐，另一轴丢掉', () {
      final state = SwipeGestureState.idle.dragBy(6, 5).dragBy(14, 25);

      expect(state.axis, SwipeAxis.vertical);
      expect(state.offsetX, 0);
      expect(state.offsetY, 30);
    });

    test('锁定竖直之后，横向位移被完全忽略', () {
      final state = SwipeGestureState.idle.dragBy(0, -30).dragBy(50, -10);

      expect(state.axis, SwipeAxis.vertical);
      expect(state.offsetX, 0);
      expect(state.offsetY, -40);
    });

    test('锁定横向之后，纵向位移被完全忽略', () {
      final state = SwipeGestureState.idle.dragBy(-30, 0).dragBy(-10, 80);

      expect(state.axis, SwipeAxis.horizontal);
      expect(state.offsetX, -40);
      expect(state.offsetY, 0);
    });

    test('两轴分量相同时算竖直，免得斜着抖一下就横过去', () {
      expect(SwipeGestureState.idle.dragBy(20, -20).axis, SwipeAxis.vertical);
      expect(SwipeGestureState.idle.dragBy(21, -20).axis, SwipeAxis.horizontal);
    });
  });

  group('松手判定', () {
    test('上滑够远就是删除', () {
      final state = SwipeGestureState.idle.dragBy(0, -200);

      expect(settle(state), SwipeVerdict.delete);
    });

    test('下滑够远就是保留', () {
      final state = SwipeGestureState.idle.dragBy(0, 200);

      expect(settle(state), SwipeVerdict.keep);
    });

    test('左滑够远才是撤销，差一点就弹回', () {
      expect(
        settle(SwipeGestureState.idle.dragBy(-130, 0)),
        SwipeVerdict.undo,
      );
      expect(settle(SwipeGestureState.idle.dragBy(-100, 0)), isNull);
    });

    test('距离不够就弹回', () {
      expect(settle(SwipeGestureState.idle.dragBy(0, -100)), isNull);
      expect(settle(SwipeGestureState.idle.dragBy(0, 100)), isNull);
    });

    test('甩得够快就不必滑够距离', () {
      final short = SwipeGestureState.idle.dragBy(0, -40);

      expect(settle(short), isNull);
      expect(settle(short, velocityY: -2000), SwipeVerdict.delete);
      expect(settle(short, velocityY: 2000), SwipeVerdict.keep);
    });

    test('还没锁轴就被甩出去时，由速度定轴', () {
      expect(settle(SwipeGestureState.idle, velocityY: -1500), SwipeVerdict.delete);
      expect(settle(SwipeGestureState.idle, velocityX: -1500), SwipeVerdict.undo);
    });

    test('什么都没动就松手，不给结论', () {
      expect(settle(SwipeGestureState.idle), isNull);
      expect(settle(SwipeGestureState.idle, velocityY: 200, velocityX: -300), isNull);
    });

    test('已经锁定竖直时，横向的甩动不影响结论', () {
      final state = SwipeGestureState.idle.dragBy(0, -200);

      expect(settle(state, velocityX: -5000), SwipeVerdict.delete);
    });
  });

  group('右滑阻尼', () {
    test('右滑同样距离只跟一点点', () {
      final state = SwipeGestureState.idle.dragBy(100, 0);

      expect(state.axis, SwipeAxis.horizontal);
      expect(state.offsetX, 100 * SwipeGestureState.resistance);
      expect(state.intent, isNull);
    });

    test('右滑甩得再快也弹回，不会误触发撤销', () {
      final state = SwipeGestureState.idle.dragBy(300, 0);

      expect(settle(state, velocityX: 9000), isNull);
    });

    test('左滑跟手不打折', () {
      expect(SwipeGestureState.idle.dragBy(-100, 0).offsetX, -100);
    });
  });

  group('展示用的派生量', () {
    test('蒙层强度按满强度距离归一，并夹在 0~1', () {
      final half = SwipeGestureState.idle.dragBy(0, -200);
      final beyond = SwipeGestureState.idle.dragBy(0, -900);

      expect(
        half.progress(extentX: extentX, extentY: extentY),
        closeTo(200 / (extentY * SwipeGestureState.fullFraction), 0.001),
      );
      expect(beyond.progress(extentX: extentX, extentY: extentY), 1.0);
    });

    test('横向拖动才有倾角，竖直拖动不倾', () {
      final sideways = SwipeGestureState.idle.dragBy(-100, 0);
      final downward = SwipeGestureState.idle.dragBy(0, 100);

      expect(
        sideways.tiltRadians(extentX: extentX),
        closeTo(-100 / extentX * SwipeGestureState.maxTilt, 0.0001),
      );
      expect(downward.tiltRadians(extentX: extentX), 0);
    });

    test('拖动过程中就有徽标，不用等到松手', () {
      expect(SwipeGestureState.idle.dragBy(0, -20).intent, SwipeVerdict.delete);
      expect(SwipeGestureState.idle.dragBy(0, 20).intent, SwipeVerdict.keep);
      expect(SwipeGestureState.idle.dragBy(-20, 0).intent, SwipeVerdict.undo);
    });
  });

  group('动画期间重放位移', () {
    test('原样保留位移，不再打折', () {
      final replayed = SwipeGestureState.fromOffset(200, 0);

      expect(replayed.axis, SwipeAxis.horizontal);
      expect(replayed.offsetX, 200);
      expect(replayed.offsetY, 0);
    });

    test('飞出屏幕的位移仍然能推出徽标，好让章在飞行途中不掉', () {
      final flying = SwipeGestureState.fromOffset(0, -900);

      expect(flying.intent, SwipeVerdict.delete);
      expect(flying.progress(extentX: extentX, extentY: extentY), 1.0);
    });

    test('零位移就是静止状态', () {
      expect(SwipeGestureState.fromOffset(0, 0).isIdle, isTrue);
    });
  });
}
