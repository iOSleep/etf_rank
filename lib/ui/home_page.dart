import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/etf_result.dart';
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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('⭐ 七星高照ETF行情'),
        centerTitle: true, backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0.5,
        actions: [
          if (_tab == 0)
            IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () => context.read<RankingStore>().refresh(), tooltip: '刷新'),
        ],
      ),
      body: IndexedStack(index: _tab, children: const [_RankingTab(), LogPage()]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab, onTap: (i) => setState(() => _tab = i),
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
  final _ctrl = TextEditingController();
  bool _wasLoading = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  List<EtfResult> _filter(List<EtfResult> items) {
    if (_query.isEmpty) return items;
    final q = _query.toLowerCase();
    return items.where((r) => r.name.toLowerCase().contains(q) || r.etf.toLowerCase().contains(q) || Config.cleanCode(r.etf).contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingStore>(builder: (context, store, _) {
      final s = store.state;

      // SnackBar on refresh complete
      if (_wasLoading && !s.loading && s.allItems.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('刷新完成 — 通过 ${s.passedCount}/${s.allItems.length} 只'),
            duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 60, left: 16, right: 16),
          ));
        });
      }
      _wasLoading = s.loading;

      if (s.loading && s.allItems.isEmpty) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 60), const CircularProgressIndicator(), const SizedBox(height: 16),
          Text(store.status, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ]));
      }

      if (s.error != null && s.allItems.isEmpty) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 56, color: Color(0xFFCCCCCC)), const SizedBox(height: 16),
          Text(s.error!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: () => store.refresh(), icon: const Icon(Icons.refresh, size: 16), label: const Text('重试')),
        ]));
      }

      if (s.allItems.isEmpty && !s.loading) {
        return RefreshIndicator(
          onRefresh: () => store.refresh(),
          child: ListView(children: const [
            SizedBox(height: 140),
            Center(child: Column(children: [
              Icon(Icons.show_chart, size: 64, color: Color(0xFFDDDDDD)), SizedBox(height: 20),
              Text('下拉刷新获取数据', style: TextStyle(color: Colors.grey, fontSize: 15)),
              SizedBox(height: 8),
              Text('基于加权动量因子 · 每日评分', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 12)),
            ])),
          ]),
        );
      }

      final fp = _filter(s.passed);
      final ff = _filter(s.failed);

      return RefreshIndicator(onRefresh: () => store.refresh(), child: ListView(padding: const EdgeInsets.only(top: 4), children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: TextField(
          controller: _ctrl, onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: '搜索 ETF 名称或代码...', hintStyle: const TextStyle(fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _ctrl.clear(); setState(() => _query = ''); }) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            filled: true, fillColor: Colors.white,
          ),
        )),
        StatsBar(store: store), const SizedBox(height: 4),
        if (s.loading) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: LinearProgressIndicator()),
        if (s.targets.isNotEmpty && _query.isEmpty) SignalBanner(targets: s.targets),
        if (fp.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (int i = 0; i < fp.length; i++) RankCard(result: fp[i], index: i + 1, isPassed: true),
        ],
        if (ff.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_query.isNotEmpty ? '搜索结果 - 已过滤' : '已过滤', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500))),
          const SizedBox(height: 2),
          for (int i = 0; i < ff.length; i++) RankCard(result: ff[i], index: i + 1, isPassed: false),
        ],
        if (_query.isNotEmpty && fp.isEmpty && ff.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('无匹配结果', style: TextStyle(color: Colors.grey)))),
        const SizedBox(height: 40),
      ]));
    });
  }
}
