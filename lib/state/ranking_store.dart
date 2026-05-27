import 'package:flutter/foundation.dart';
import '../models/etf_result.dart';
import '../engine/ranking.dart';
import '../services/cache_service.dart';
import '../services/log_service.dart';

class RankingStore extends ChangeNotifier {
  final CacheService _cache;
  late final RankingEngine _engine;

  RankingState _state = const RankingState(loading: false);
  RankingState get state => _state;

  String _status = '';
  String get status => _status;

  RankingStore({required CacheService cache})
      : _cache = cache {
    _engine = RankingEngine(cache: cache);
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
      stopwatch.stop();
      log.success('刷新完成 - 共 ${allItems.length} 只，通过 ${_state.passedCount} 只，耗时 ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stack) {
      log.error('刷新失败: $e');
      log.error('$stack');
      _state = _state.copyWith(
        loading: false,
        error: '刷新失败: $e',
      );
      _status = '';
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _cache.close();
    super.dispose();
  }
}
