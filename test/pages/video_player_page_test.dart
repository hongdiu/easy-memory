import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/pages/video_player_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('视频页渲染 AppBar 与长按倍速设置入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoPlayerPage(title: '测试视频', localPath: '不存在的文件.mp4'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试视频'), findsOneWidget);
    expect(find.byIcon(Icons.speed), findsOneWidget);
  });

  testWidgets('打开长按倍速配置层并持久化选择', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoPlayerPage(title: '测试视频', localPath: '不存在的文件.mp4'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speed));
    await tester.pumpAndSettle();

    // 配置层包含全部档位
    expect(find.text('1.5x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('3x'), findsOneWidget);
    expect(find.text('4x'), findsOneWidget);
    expect(find.text('5x'), findsOneWidget);

    // 选择 4x
    await tester.tap(find.text('4x'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('long_press_speed'), 4.0);
  });

  testWidgets('已有配置时加载为当前长按倍速', (tester) async {
    SharedPreferences.setMockInitialValues({'long_press_speed': 2.0});
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoPlayerPage(title: '测试视频', localPath: '不存在的文件.mp4'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speed));
    await tester.pumpAndSettle();

    // 2x 为当前选中（带勾选标记）
    final twoXItem = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '2x'),
    );
    expect(twoXItem.trailing, isA<Icon>());
  });
}