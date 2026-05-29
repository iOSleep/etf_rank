import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/etf_result.dart';
import '../engine/config.dart';
import '../engine/ranking.dart';
import '../services/api_service.dart';
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

  // -- ETF Pool --
  List<String> _etfPool = List.unmodifiable(Config.etfPool);
  List<String> get etfPool => _etfPool;
  List<String> get etfPoolSmall => Config.etfPoolSmall;
  bool get isPoolDefault =>
      _etfPool.length == Config.etfPool.length &&
      _etfPool.toSet().containsAll(Config.etfPool);

  // -- Name cache (code -> name) persisted to SP --
  Map<String, String> _nameCache = {};
  Map<String, String> get nameCache => _nameCache;

  static const _keyState = 'last_ranking_state';
  static const _keyTime = 'last_ranking_time';
  static const _keyPool = 'user_etf_pool';
  static const _keyNames = 'etf_name_cache';
  static const _autoRefreshMinutes = 10;

  RankingStore({required CacheService cache}) : _cache = cache {
    _engine = RankingEngine(cache: cache);
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _loadSavedPool();
    await _loadNameCache();
    await _loadCachedState();
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
        // Merge names from cached results into name cache
        for (final item in _state.allItems) {
          final clean = Config.cleanCode(item.etf);
          if (item.name.isNotEmpty && item.name != clean) {
            _nameCache[clean] = item.name;
          }
        }
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

    log.info('🔄 开始刷新 (${_etfPool.length} 只)...');
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
        codes: _etfPool,
      );

      _state = RankingEngine.buildState(allItems);
      _status = '刷新完成';
      _initialLoadDone = true;
      stopwatch.stop();
      log.success(
          '刷新完成 - 共 ${allItems.length} 只，通过 ${_state.passedCount} 只，耗时 ${stopwatch.elapsedMilliseconds}ms');

      // Update name cache from results
      for (final item in _state.allItems) {
        final clean = Config.cleanCode(item.etf);
        if (item.name.isNotEmpty && item.name != clean) {
          _nameCache[clean] = item.name;
        }
      }
      await _saveNameCache();
      await _saveState();
    } catch (e, stack) {
      log.error('刷新失败: $e');
      log.error('$stack');
      _state = _state.copyWith(loading: false, error: '刷新失败: $e');
      _status = '';
    }

    notifyListeners();
  }

  // ── ETF Pool Management ──

  Future<void> _loadSavedPool() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_keyPool);
      if (saved != null && saved.isNotEmpty) {
        _etfPool = List.unmodifiable(saved);
        log.info('📋 加载自定义标的池: ${saved.length} 只');
        notifyListeners();
      }
    } catch (e) {
      log.warn('加载标的池失败: $e');
    }
  }

  Future<void> _savePool() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyPool, _etfPool.toList());
    } catch (e) {
      log.warn('保存标的池失败: $e');
    }
  }

  Future<void> _loadNameCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyNames);
      if (raw != null && raw.isNotEmpty) {
        final data = json.decode(raw) as Map<String, dynamic>;
        _nameCache = data.map((k, v) => MapEntry(k, v as String));
        // Seed with default pool names from Config
        for (final code in Config.etfPool) {
          final clean = Config.cleanCode(code);
          if (!_nameCache.containsKey(clean)) {
            _nameCache[clean] = _defaultName(clean);
          }
        }
        log.info('📋 加载名称缓存: ${_nameCache.length} 条');
      } else {
        // Seed from default pool
        for (final code in Config.etfPool) {
          final clean = Config.cleanCode(code);
          _nameCache[clean] = _defaultName(clean);
        }
      }
    } catch (e) {
      log.warn('加载名称缓存失败: $e');
      // Fallback: seed from default pool
      for (final code in Config.etfPool) {
        final clean = Config.cleanCode(code);
        _nameCache[clean] = _defaultName(clean);
      }
    }
  }

  Future<void> _saveNameCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyNames, json.encode(_nameCache));
    } catch (e) {
      log.warn('保存名称缓存失败: $e');
    }
  }

  /// Fallback names from the default pool
  static String _defaultName(String clean) {
    const names = {
      '518880': '黄金ETF', '159980': '有色ETF', '159985': '豆粕ETF',
      '501018': '南方原油', '161226': '白银LOF', '159981': '能源化工ETF',
      '513100': '纳指ETF', '159509': '纳指科技ETF', '513290': '德国ETF',
      '513500': '标普500ETF', '159529': '标普消费ETF', '513400': '道琼斯ETF',
      '513520': '日经ETF', '513030': '德国30ETF', '513080': '法国ETF',
      '513310': '东南亚科技ETF', '513730': '东南亚ETF',
      '159792': '港股通科技ETF', '513130': '恒生科技ETF', '513050': '中概互联ETF',
      '159920': '恒生ETF', '513690': '恒生高股息ETF',
      '510300': '沪深300ETF', '510500': '中证500ETF', '510050': '上证50ETF',
      '510210': '上证ETF', '159915': '创业板ETF', '588080': '科创50ETF',
      '512100': '中证1000ETF', '563360': '科创100ETF', '563300': '科创50增强ETF',
      '512890': '红利低波ETF', '159967': '创成长ETF', '512040': '价值ETF',
      '159201': '成长ETF',
      '511380': '可转债ETF', '511010': '国债ETF', '511220': '城投债ETF',
      '511880': '银华日利',
    };
    return names[clean] ?? clean;
  }

  /// Get display name for a code, using cache → results → fallback
  String displayName(String code) {
    final clean = Config.cleanCode(code);
    // 1. Check ranking results
    final item = _state.allItems.firstWhere(
      (e) => Config.cleanCode(e.etf) == clean,
      orElse: () => EtfResult(etf: code, name: ''),
    );
    if (item.name.isNotEmpty && item.name != clean) {
      _nameCache[clean] = item.name;
      return item.name;
    }
    // 2. Check name cache
    final cached = _nameCache[clean];
    if (cached != null && cached.isNotEmpty) return cached;
    // 3. Fallback
    return clean;
  }

  Future<void> addToPool(List<String> codes) async {
    final newCodes = codes.where((c) => !_etfPool.contains(c)).toList();
    if (newCodes.isEmpty) return;
    // Try to fetch names for new codes before adding
    final cleanNew = newCodes.map(Config.cleanCode).toList();
    try {
      final names = await fetchCodeNames(cleanNew);
      names.forEach((k, v) {
        _nameCache[k] = v;
      });
      await _saveNameCache();
    } catch (_) {}
    _etfPool = List.unmodifiable([..._etfPool, ...newCodes]);
    await _savePool();
    log.info('➕ 添加标的: $newCodes → 共 ${_etfPool.length} 只');
    notifyListeners();
    await refresh();
  }

  Future<void> removeFromPool(List<String> codes) async {
    _etfPool = List.unmodifiable(_etfPool.where((c) => !codes.contains(c)).toList());
    await _savePool();
    log.info('➖ 删除标的: $codes → 共 ${_etfPool.length} 只');
    notifyListeners();
    await refresh();
  }

  Future<void> resetPool() async {
    _etfPool = List.unmodifiable(Config.etfPool);
    await _savePool();
    log.info('🔄 恢复默认标的池: ${_etfPool.length} 只');
    notifyListeners();
    await refresh();
  }

  /// 腾讯实时API查询代码名称
  Future<Map<String, String>> fetchCodeNames(List<String> cleanCodes) async {
    final codesWithSuffix = cleanCodes.map((c) {
      if (c.contains('.')) return c;
      return attachSuffix(c);
    }).toList();
    final quotes = await ApiService.fetchRealTimeQuotes(codesWithSuffix);
    final result = <String, String>{};
    for (final entry in quotes.entries) {
      final name = entry.value['name'] as String?;
      if (name != null && name.isNotEmpty) {
        result[entry.key] = name;
      }
    }
    return result;
  }

  static String attachSuffix(String code) {
    if (code.startsWith('5') || code.startsWith('6')) return '$code.XSHG';
    if (code.startsWith('8')) return '$code.BJ';
    return '$code.XSHE';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cache.close();
    super.dispose();
  }
}
