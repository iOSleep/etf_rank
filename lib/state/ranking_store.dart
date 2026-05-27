import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/etf_result.dart';
import '../engine/ranking.dart';
import '../services/cache_service.dart';
import '../services/log_service.dart';

class RankingStore extends ChangeNotifier with WidgetsBindingObserver {
  final CacheService _cache;
  late final RankingEngine _engine;

  RankingState _state = const RankingState(loading: false);
  RankingState get state => _state;

  String _status = '';
  String get status => _status;

  DateTime? _lastRefreshTime;
  bool _initialLoadDone = false;

  static const _keyState = 'last_ranking_state';
  static const _keyTime = 'last_ranking_time';
  static const _autoRefreshMinutes = 10;

  RankingStore({required CacheService cache}) : _cache = cache {
    _engine = RankingEngine(cache: cache);
    WidgetsBinding.instance.addObserver(this);
    _loadCachedState();
    _autoRefreshIfNeeded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _initialLoadDone) {
      log.info('📱 从后台返回前台');
      _autoRefreshIfNeeded();
    }
  }

  Future<void> _loadCachedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keyState);
      final timeStr = prefs.getString(_keyTime);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        _state = RankingState.fromJson(data);
        _initialLoadDone = true;
        if (timeStr != null) _lastRefreshTime = DateTime.tryParse(timeStr);
        log.info('📦 加载历史数据: ${_state.allItems.length} 条');
        notifyListeners();
      }
    } catch (e) {
      log.warn('加载缓存状态失败: $e');
    }
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyState, json.encode(_state.toJson()));
      await prefs.setString(_keyTime, DateTime.now().toIso8601String());
      _lastRefreshTime = DateTime.now();
    } catch (e) {
      log.warn('保存状态失败: $e');
    }
  }

  void _autoRefreshIfNeeded() {
    if (_state.allItems.isEmpty) {
      refresh();
      return;
    }
    if (_lastRefreshTime != null) {
      final elapsed = DateTime.now().difference(_lastRefreshTime!);
      if (elapsed.inMinutes >= _autoRefreshMinutes) {
        log.info('⏰ 距上次刷新 ${elapsed.inMinutes} 分钟，自动刷新');
        refresh();
      } else {
        log.info('📦 数据有效 (${elapsed.inMinutes}分钟前)');
      }
    } else {
      refresh();
    }
  }

  Future<void> refresh() async {
    if (_state.loading) return;

    log.info('🔄 开始刷新...');
    _state = _state.copyWith(loading: true, error: null);
    _status = '正在刷新...';
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      final allItems = await _engine.run(
        onStatus: (s) {
          _status = s;
          notifyListeners();
        },
      );

      _state = RankingEngine.buildState(allItems);
      _status = '刷新完成';
      _initialLoadDone = true;
      stopwatch.stop();
      log.success(
          '刷新完成 - 共 ${allItems.length} 只，通过 ${_state.passedCount} 只，耗时 ${stopwatch.elapsedMilliseconds}ms');

      await _saveState();
    } catch (e, stack) {
      log.error('刷新失败: $e');
      log.error('$stack');
      _state = _state.copyWith(loading: false, error: '刷新失败: $e');
      _status = '';
    }

    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cache.close();
    super.dispose();
  }
}
