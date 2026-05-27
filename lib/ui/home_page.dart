import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/ranking_store.dart';
import 'widgets/stats_bar.dart';
import 'widgets/signal_banner.dart';
import 'widgets/rank_card.dart';
import 'log_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('⭐ 七星高照ETF行情'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          if (_tabIndex == 0)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () {
                final store = context.read<RankingStore>();
                store.refresh();
              },
              tooltip: '刷新',
            ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          _RankingTab(),
          LogPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.leaderboard), label: '排名'),
          BottomNavigationBarItem(icon: Icon(Icons.article_outlined), label: '日志'),
        ],
      ),
    );
  }
}

class _RankingTab extends StatelessWidget {
  const _RankingTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingStore>(
      builder: (context, store, _) {
        final state = store.state;

        if (state.loading && state.allItems.isEmpty) {
          return ListView(
            children: [
              const SizedBox(height: 80),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Center(
                child: Text(store.status, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ],
          );
        }

        if (state.error != null && state.allItems.isEmpty) {
          return ListView(
            children: [
              const SizedBox(height: 80),
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(state.error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => store.refresh(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final passed = state.passed;
        final failed = state.failed;

        return RefreshIndicator(
          onRefresh: () => store.refresh(),
          child: ListView(
            padding: const EdgeInsets.only(top: 4),
            children: [
              if (state.allItems.isNotEmpty) ...[
                StatsBar(store: store),
                const SizedBox(height: 4),
              ],
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(),
                ),
              if (state.targets.isNotEmpty) SignalBanner(targets: state.targets),
              if (passed.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (int i = 0; i < passed.length; i++)
                  RankCard(result: passed[i], index: i + 1, isPassed: true),
              ],
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('已过滤', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 2),
                for (int i = 0; i < failed.length; i++)
                  RankCard(result: failed[i], index: i + 1, isPassed: false),
              ],
              const SizedBox(height: 16),
              const Center(
                child: Text('基于加权动量因子 · 每日自动更新', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 10)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}
