// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jmcomic_mobile/app.dart';
import 'package:jmcomic_mobile/providers/search_provider.dart';

/// 用于 App smoke test 的假分类 Provider，不触发真实网络请求
class _FakeCategoryNotifier extends CategoryNotifier
{
    _FakeCategoryNotifier() : super(null);

    @override
    Future<void> loadCategory({
        String category = '0',
        String time = 'a',
        String orderBy = 'mr',
        int page = 1,
    }) async {}

    @override
    Future<void> loadMore() async {}
}

void main()
{
    testWidgets('App smoke test', (WidgetTester tester) async
    {
        // 构建应用，使用假分类 Provider 避免触发网络请求
        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    categoryProvider.overrideWith(
                        (ref) => _FakeCategoryNotifier(),
                    ),
                ],
                child: const App(),
            ),
        );

        // 验证首页标题正常显示
        expect(find.text('七星天堂'), findsOneWidget);
    });
}
