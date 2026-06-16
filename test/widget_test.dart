// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:jmcomic_mobile/app.dart';

void main()
{
    testWidgets('App smoke test', (WidgetTester tester) async
    {
        // 构建应用并触发一帧
        await tester.pumpWidget(const App());

        // 验证应用正常启动
        expect(find.text('搜索'), findsWidgets);
    });
}
