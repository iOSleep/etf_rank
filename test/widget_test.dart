import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:etf_rank_app/services/cache_service.dart';
import 'package:etf_rank_app/state/ranking_store.dart';
import 'package:etf_rank_app/ui/home_page.dart';

void main() {
  testWidgets('App shows title and tabs', (WidgetTester tester) async {
    final cacheService = CacheService();
    final rankingStore = RankingStore(cache: cacheService);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: rankingStore,
        child: const MaterialApp(
          home: HomePage(),
        ),
      ),
    );

    expect(find.text('⭐ 七星高照ETF行情'), findsOneWidget);
    expect(find.text('排名'), findsOneWidget);
    expect(find.text('日志'), findsOneWidget);
    // Default tab shows stats
    expect(find.text('暂无日志，下拉刷新开始'), findsNothing); // not on log tab
  });
}
