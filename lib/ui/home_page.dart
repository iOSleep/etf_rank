import 'package:flutter/material.dart';
import '../models/etf_result.dart';
import 'package:provider/provider.dart';
import '../state/ranking_store.dart';
import '../engine/config.dart';
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

class _RankingTab extends StatefulWidget {
  const _RankingTab();

  @override
  State<_RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<_RankingTab> {
  String _query = '';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<EtfResult> _filter(List<EtfResult> items) {
    if (_query.isEmpty) return items;
    final q = _query.toLowerCase();
    return items.where((r) {
      return r.name.toLowerCase().contains(q) ||
          r.etf.toLowerCase().contains(q) ||
          Config.cleanCode(r.etf).contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingStore>(
      builder: (context, store, _) {
        final state = store.state;

        if (state.loading && state.allItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 60),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(store.status, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          );
        }

        if (state.error != null && state.allItems.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 56, color: Color(0xFFCCCCCC)),
                  const SizedBox(height: 16),
                  Text(state.error!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => store.refresh(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        if (state.allItems.isEmpty && !state.loading) {
          return RefreshIndicator(
            onRefresh: () => store.refresh(),
            child: ListView(
              children: const [
                SizedBox(height: 140),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.show_chart, size: 64, color: Color(0xFFDDDDDD)),
                      SizedBox(height: 20),
                      Text('下拉刷新获取数据', style: TextStyle(color: Colors.grey, fontSize: 15)),
                      SizedBox(height: 8),
                      Text('基于加权动量因子 · 每日评分', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final allPassed = state.passed;
        final allFailed = state.failed;
        final passed = _filter(allPassed);
        final failed = _filter(allFailed);

        return RefreshIndicator(
          onRefresh: () => store.refresh(),
          child: ListView(
            padding: const EdgeInsets.only(top: 4),
            children: [
              // 搜索框
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TextField(
                  controller: _controller,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: '搜索 ETF 名称或代码...',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),

              StatsBar(store: store),
              const SizedBox(height: 4),
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(),
                ),
              if (state.targets.isNotEmpty && _query.isEmpty)
                SignalBanner(targets: state.targets),
              if (passed.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (int i = 0; i < passed.length; i++)
                  RankCard(result: passed[i], index: i + 1, isPassed: true),
              ],
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _query.isNotEmpty ? '搜索结果 - 已过滤' : '已过滤',
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 2),
                for (int i = 0; i < failed.length; i++)
                  RankCard(result: failed[i], index: i + 1, isPassed: false),
              ],
              if (_query.isNotEmpty && passed.isEmpty && failed.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('无匹配结果', style: TextStyle(color: Colors.grey)),
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}
