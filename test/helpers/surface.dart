import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把测试窗口放大到能装下整页内容。
///
/// 首页和设置页都是 `ListView`，超出一屏的卡片根本不会被创建，
/// `find.text` 自然找不到它们。与其在测试里到处滚动，不如直接给一块
/// 足够大的画布，让断言只关心内容本身。
void useLargeSurface(
  WidgetTester tester, {
  Size size = const Size(1000, 3000),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 把测试窗口调整成一部手机的大小（默认 iPhone 13 的逻辑分辨率）。
///
/// 滑动清理的判定阈值是按屏幕宽高的比例算的，用 [useLargeSurface] 那种
/// 1000×3000 的画布会让「滑多远才算数」完全失真，所以测手势必须用真实尺寸。
void usePhoneSurface(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 找到包含指定文字的 `ChoiceChip` / `ListTile` 等可点区域并点击。
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}
