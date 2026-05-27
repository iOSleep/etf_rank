import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:charset/charset.dart';
import '../models/kline.dart';
import '../engine/config.dart';
import 'log_service.dart';

class ApiService {
  static Future<Map<String, Map<String, dynamic>>> fetchRealTimeQuotes(
    List<String> codes,
  ) async {
    final cleanCodes = codes.map(Config.cleanCode).toList();
    final prefixed = cleanCodes.map((c) => _prefix(c)).join(',');
    final url = 'https://qt.gtimg.cn/q=$prefixed';

    log.api('腾讯行情请求: ${cleanCodes.length} 只');
    final sw = Stopwatch()..start();
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        log.error('腾讯API HTTP ${resp.statusCode}');
        return {};
      }
      final data = gbk.decode(resp.bodyBytes);
      if (data.length < 100) {
        log.error('腾讯API返回过短: ${data.length} bytes');
        return {};
      }
      final result = <String, Map<String, dynamic>>{};
      for (final line in data.split(';')) {
        if (!line.contains('=') || !line.contains('"')) continue;
        try {
          final key = line.split('=')[0].split('_').last;
          final vals = line.split('"')[1].split('~');
          if (vals.length < 53) continue;
          final code = key.substring(2);
          final entry = <String, dynamic>{
            'name': vals[1],
            'price': double.tryParse(vals[3]) ?? 0,
            'last_close': double.tryParse(vals[4]) ?? 0,
            'open': double.tryParse(vals[5]) ?? 0,
            'high': double.tryParse(vals[33]) ?? 0,
            'low': double.tryParse(vals[34]) ?? 0,
            'volume': double.tryParse(vals[36]) ?? 0,
            'amount_wan': double.tryParse(vals[37]) ?? 0,
          };
          final nav = _parseNavFields(vals);
          if (nav != null) entry.addAll(nav);
          result[code] = entry;
        } catch (_) {}
      }
      log.api('腾讯行情成功: ${result.length}只, ${sw.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      log.error('腾讯API异常(${sw.elapsedMilliseconds}ms): $e');
      return {};
    }
  }

  static String _prefix(String code) {
    if (code.startsWith('6') || code.startsWith('9') || code.startsWith('5')) return 'sh$code';
    if (code.startsWith('8')) return 'bj$code';
    return 'sz$code';
  }

  static Map<String, dynamic>? _parseNavFields(List<String> vals) {
    int n = vals.length;
    while (n > 0 && vals[n - 1] == '"') { n--; }
    if (n < 60) return null;
    int cnyIdx = -1;
    for (int i = n - 1; i > math.max(0, n - 20); i--) {
      if (vals[i].contains('CNY')) { cnyIdx = i; break; }
    }
    if (cnyIdx < 7) return null;
    double? sf(int idx) {
      if (idx < 0 || idx >= n) return null;
      final s = vals[idx].trim();
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }
    final premiumPct = sf(cnyIdx - 5);
    final unitNav = sf(cnyIdx - 4);
    final iopv = sf(cnyIdx + 3);
    final currentPrice = double.tryParse(vals[3]) ?? 0;
    double? premiumRate;
    if (premiumPct != null) {
      premiumRate = premiumPct / 100.0;
    } else if (unitNav != null && unitNav > 0 && currentPrice > 0) {
      premiumRate = (currentPrice - unitNav) / unitNav;
    } else if (iopv != null && iopv > 0 && currentPrice > 0) {
      premiumRate = (currentPrice - iopv) / iopv;
    }
    return {
      'unit_nav': unitNav, 'prev_nav': sf(cnyIdx - 1), 'iopv': iopv,
      'premium_rate': premiumRate, 'premium_pct': premiumPct,
      'nav_change_pct': sf(cnyIdx - 2),
    };
  }

  // ── K-line ──

  /// 默认拉近 500 天，截止昨天（盘中今天K线未收）
  static String _defaultBeg() {
    final d = DateTime.now().subtract(const Duration(days: 500));
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  static String _yesterdayStr() {
    final d = DateTime.now().subtract(const Duration(days: 1));
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  static Future<List<KlineRow>?> fetchKlines(
    String code, {String? beg, String? end, int retries = 1}) async {
    final clean = Config.cleanCode(code);
    final int market =
        clean.startsWith('5') || clean.startsWith('6') || clean.startsWith('9') ? 1 : 0;
    final secid = '$market.$clean';
    final beg0 = beg ?? _defaultBeg();
    final end0 = end ?? _yesterdayStr(); // 默认截止昨天

    for (int attempt = 0; attempt <= retries; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt * 2));
        log.cache('$clean: 重试 $attempt');
      }
      final result = await _tryEastMoney(secid, clean, beg0, end0);
      if (result != null) return result;
    }

    final baidu = await _tryBaidu(clean, beg0, end0);
    if (baidu != null) return baidu;

    log.error('$clean: K线获取最终失败 (beg=$beg0 end=$end0)');
    return null;
  }

  static Future<List<KlineRow>?> _tryEastMoney(
    String secid, String label, String beg, String end,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final url = Uri.parse(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get',
      ).replace(queryParameters: {
        'fields1': 'f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13',
        'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
        'beg': beg, 'end': end,
        'rtntype': '6', 'secid': secid, 'klt': '101', 'fqt': '1',
      });

      final resp = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Referer': 'https://quote.eastmoney.com/',
      }).timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        log.warn('$label: 东财 HTTP ${resp.statusCode} (${sw.elapsedMilliseconds}ms)');
        return null;
      }

      final data = json.decode(resp.body);
      final klines = data['data']?['klines'] as List<dynamic>?;
      if (klines == null || klines.isEmpty) {
        log.warn('$label: 东财响应无K线 (${sw.elapsedMilliseconds}ms)');
        return null;
      }

      final rows = _parseEastMoneyKlines(klines);
      log.cache('$label: 东财 ${rows.length}条 (${sw.elapsedMilliseconds}ms)');
      return rows.isNotEmpty ? rows : null;
    } catch (e) {
      log.warn('$label: 东财异常(${sw.elapsedMilliseconds}ms): $e');
      return null;
    }
  }

  static List<KlineRow> _parseEastMoneyKlines(List<dynamic> klines) {
    final rows = <KlineRow>[];
    for (final k in klines) {
      final parts = (k as String).split(',');
      if (parts.length < 7) continue;
      final date = DateTime.tryParse(parts[0]);
      if (date == null) continue;
      rows.add(KlineRow(
        date: date,
        open: double.tryParse(parts[1]) ?? 0,
        close: double.tryParse(parts[2]) ?? 0,
        high: double.tryParse(parts[3]) ?? 0,
        low: double.tryParse(parts[4]) ?? 0,
        volume: double.tryParse(parts[5]) ?? 0,
        amount: double.tryParse(parts[6]) ?? 0,
      ));
    }
    rows.sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }

  static Future<List<KlineRow>?> _tryBaidu(
    String code, String beg, String end,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final url = Uri.parse(
        'https://finance.pae.baidu.com/selfselect/getstockquotation',
      ).replace(queryParameters: {
        'code': code, 'all': '1', 'isIndex': 'false', 'isBk': 'false',
        'isBlock': 'false', 'isFutures': 'false', 'isStock': 'true',
        'newFormat': '1', 'group': 'quotation_kline_ab',
        'finClientType': 'pc', 'start_time': '', 'ktype': '1',
      });
      final resp = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
        'Accept': 'application/json',
        'Origin': 'https://gushitong.baidu.com',
        'Referer': 'https://gushitong.baidu.com/',
      }).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        log.warn('$code: 百度 HTTP ${resp.statusCode} (${sw.elapsedMilliseconds}ms)');
        return null;
      }

      final data = json.decode(resp.body);
      final md = data['Result']?['newMarketData'];
      final raw = md?['marketData'] as String?;
      if (raw == null || raw.isEmpty) {
        log.warn('$code: 百度响应无数据 (${sw.elapsedMilliseconds}ms)');
        return null;
      }

      final rows = _parseBaiduKlines(raw, beg, end);
      if (rows.isNotEmpty) {
        log.cache('$code: 百度 ${rows.length}条 (${sw.elapsedMilliseconds}ms)');
      }
      return rows.isNotEmpty ? rows : null;
    } catch (e) {
      log.warn('$code: 百度异常(${sw.elapsedMilliseconds}ms): $e');
      return null;
    }
  }

  static List<KlineRow> _parseBaiduKlines(String raw, String beg, String end) {
    final rows = <KlineRow>[];
    final begDt = DateTime.tryParse(beg) ?? DateTime(1900);
    final endDt = DateTime.tryParse(end) ?? DateTime(2050);
    for (final line in raw.split(';')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 8) continue;
      final date = DateTime.tryParse(parts[1]);
      if (date == null || date.isBefore(begDt) || date.isAfter(endDt)) continue;
      rows.add(KlineRow(
        date: date,
        open: double.tryParse(parts[2]) ?? 0,
        close: double.tryParse(parts[3]) ?? 0,
        high: double.tryParse(parts[5]) ?? 0,
        low: double.tryParse(parts[6]) ?? 0,
        volume: double.tryParse(parts[4]) ?? 0,
        amount: double.tryParse(parts[7]) ?? 0,
      ));
    }
    rows.sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }
}
