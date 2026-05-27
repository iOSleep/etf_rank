import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/cache_service.dart';
import 'state/ranking_store.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final cacheService = CacheService();
  final rankingStore = RankingStore(cache: cacheService);

  runApp(
    ChangeNotifierProvider.value(
      value: rankingStore,
      child: const EtfRankApp(),
    ),
  );
}

class EtfRankApp extends StatelessWidget {
  const EtfRankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '七星高照ETF行情',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16A34A)),
        useMaterial3: true,
        fontFamily: '.SF UI Text',
      ),
      home: const HomePage(),
    );
  }
}
