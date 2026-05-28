import 'dart:async';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/kline.dart';
import '../engine/config.dart';
import 'api_service.dart';
import 'log_service.dart';

class CacheService {
  Database? _db;
  static const String _table = 'klines';
  static const int _minRows = 25;

  static const int _concurrency = 1;
  static const int _batchDelayMs = 400; // 降到 400ms（已验证不会封）
  final _rng = math.Random();

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'etf_klines.db');
    log.cache('数据库路径: $path');
    return openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE $_table (
          code TEXT NOT NULL, date TEXT NOT NULL,
          open REAL NOT NULL, close REAL NOT NULL,
          high REAL NOT NULL, low REAL NOT NULL,
          volume REAL NOT NULL, amount REAL NOT NULL,
          PRIMARY KEY (code, date)
        )
      ''');
    });
  }

  Future<List<KlineRow>> getKlines(String code) async {
    final database = await db;
    final clean = Config.cleanCode(code);
    final rows = await database.query(_table,
        where: 'code = ?', whereArgs: [clean], orderBy: 'date ASC');
    return rows.map(KlineRow.fromJson).toList();
  }

  Future<void> insertKlines(String code, List<KlineRow> rows) async {
    if (rows.isEmpty) return;
    final database = await db;
    final clean = Config.cleanCode(code);
    final batch = database.batch();
    for (final row in rows) {
      batch.insert(_table, {'code': clean, ...row.toJson()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static String _yesterdayStr() {
    final d = DateTime.now().subtract(const Duration(days: 1));
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  Future<List<KlineRow>> loadKlines(String code) async {
    final clean = Config.cleanCode(code);
    final cached = await getKlines(code);

    // 缓存充足 → 直接返回
    if (cached.length >= _minRows) {
      final lastDate = cached.last.date;
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayDate =
          DateTime(yesterday.year, yesterday.month, yesterday.day);

      // 数据已是最新（截止昨天），完全走缓存
      if (!lastDate.isBefore(yesterdayDate)) {
        return cached;
      }

      // 缺几天增量
      final nextDay = lastDate.add(const Duration(days: 1));
      final beg =
          '${nextDay.year}${nextDay.month.toString().padLeft(2, '0')}${nextDay.day.toString().padLeft(2, '0')}';
      final delta = await ApiService.fetchKlines(code, beg: beg, end: _yesterdayStr());
      if (delta != null && delta.isNotEmpty) {
        await insertKlines(code, delta);
        cached.addAll(delta);
        log.cache('$clean: 增量 ${delta.length}条 (总计 ${cached.length}条)');
      }
      return cached;
    }

    // 缓存不足 → 全量拉取
    if (cached.isNotEmpty) {
      final database = await db;
      await database.delete(_table, where: 'code = ?', whereArgs: [clean]);
    }
    final fresh = await ApiService.fetchKlines(code, end: _yesterdayStr());
    if (fresh != null && fresh.isNotEmpty) {
      await insertKlines(code, fresh);
      return fresh;
    }
    log.warn('$clean: 无K线数据');
    return [];
  }

  Future<Map<String, List<KlineRow>>> loadAll(
    List<String> codes, {
    void Function(int done, int total)? onProgress,
  }) async {
    final result = <String, List<KlineRow>>{};
    final total = codes.length;
    int done = 0;
    int cacheHits = 0;
    int apiCalls = 0;

    log.info('开始加载K线 (串行, 需要更新才请求API)');

    for (int i = 0; i < total; i += _concurrency) {
      final batch = codes.sublist(i, math.min(i + _concurrency, total));

      // 先查每只的缓存状态（不发起网络）
      final needFetch = <String>[];
      for (final code in batch) {
        final cached = await getKlines(code);
        if (cached.length >= _minRows) {
          final lastDate = cached.last.date;
          final yesterday = DateTime.now().subtract(const Duration(days: 1));
          final yesterdayDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
          if (!lastDate.isBefore(yesterdayDate)) {
            result[code] = cached;
            cacheHits++;
            done++;
            onProgress?.call(done, total);
            continue;
          }
        }
        needFetch.add(code);
      }

      // 只对需要更新的发起网络请求
      if (needFetch.isNotEmpty) {
        final futures = needFetch.map((code) async {
          final klines = await loadKlines(code);
          return (code, klines);
        });
        final batchResults = await Future.wait(futures);
        for (final (code, klines) in batchResults) {
          result[code] = klines;
          apiCalls++;
          done++;
          onProgress?.call(done, total);
        }

        // 批次间冷却
        if (i + _concurrency < total) {
          final jitter = _rng.nextInt(300);
          await Future.delayed(
              Duration(milliseconds: _batchDelayMs + jitter));
        }
      }
    }

    log.success('K线完成: 缓存命中 $cacheHits, API请求 $apiCalls, 总计 ${result.length}');
    return result;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
