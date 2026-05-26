#!/usr/bin/env python3
"""
七星高照ETF轮动 - 研究/评分脚本（本地数据版）
替代原版 jqdata 依赖，使用 East Money + 腾讯财经 API 获取数据。
每个交易日收盘后自动运行，保存所有标的得分到文件。

更新内容：
  v2.1 - 2026-05-21
  1. ✅ 溢价率过滤：使用腾讯行情API获取ETF单位净值/IOPV，计算溢价率
  2. ✅ 过滤原因标注：明确显示每只ETF被过滤的具体原因
  3. ✅ 智能缓存：缓存过去25天数据，当天数据实时拉取，收盘后记录得分

用法:
  python3 七星研究-日志_本地版.py                  # 今天评分
  python3 七星研究-日志_本地版.py --refresh         # 强制刷新缓存后评分
  python3 七星研究-日志_本地版.py --date 2026-05-21 # 指定日期评分
  python3 七星研究-日志_本地版.py --quiet          # 安静模式
"""

import numpy as np
import math
import datetime
import pandas as pd
import json
import os
import sys
import time

# 添加项目根目录到 path
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, PROJECT_ROOT)

# ==================== 使用本地数据层 ====================
from data.east_money import get_security_name, get_premium_rate
from data.tencent import tencent_quote, get_fund_net_value

# ==================== 全局参数 ====================
class g:
    # 小池（7只，原始七星核心池）
    etf_pool_small = [
        "518880.XSHG",   # 黄金ETF
        "159985.XSHE",   # 豆粕ETF
        "501018.XSHG",   # 南方原油
        "161226.XSHE",   # 白银LOF
        "513100.XSHG",   # 纳指ETF
        "159915.XSHE",   # 创业板ETF
        "511220.XSHG",   # 城投债ETF
    ]
    # ETF池
    etf_pool = [
        # 大宗商品
        "518880.XSHG",  "159980.XSHE",  "159985.XSHE",  "501018.XSHG",
        '161226.XSHE',  "159981.XSHE",
        # 国际
        "513100.XSHG",  "159509.XSHE",  "513290.XSHG",  "513500.XSHG",
        "159529.XSHE",  "513400.XSHG",  "513520.XSHG",  "513030.XSHG",
        "513080.XSHG",  "513310.XSHG",  "513730.XSHG",
        # 香港
        "159792.XSHE",  "513130.XSHG",  "513050.XSHG",  "159920.XSHE",
        "513690.XSHG",
        # 指数
        "510300.XSHG",  "510500.XSHG",  "510050.XSHG",  "510210.XSHG",
        "159915.XSHE",  "588080.XSHG",  "512100.XSHG",  "563360.XSHG",
        "563300.XSHG",
        # 风格
        "512890.XSHG",  "159967.XSHE",  "512040.XSHG",  "159201.XSHE",
        # 债券
        "511380.XSHG",  "511010.XSHG",  "511220.XSHG",
    ]
    
    # ████████ 核心参数 ████████
    lookback_days = 25
    holdings_num = 1
    defensive_etf = "511880.XSHG"
    min_money = 5000

    # ████████ 盈利保护 ████████
    enable_profit_protection = True
    profit_protection_lookback = 1
    profit_protection_threshold = 0.05     # 当前价低于近N日最高价5%则过滤

    # ████████ 近3日跌幅过滤 ████████
    loss = 0.97                              # 单日跌幅超过3%则过滤
    min_score_threshold = 0
    max_score_threshold = 100.0

    # ████████ 成交量过滤 ████████
    enable_volume_check = True
    volume_lookback = 5
    volume_threshold = 2                     # 当日量 > 5日均量 × 阈值
    volume_return_limit = 1                  # 放量且年化>阈值则过滤

    # ████████ 短期动量过滤 ████████
    use_short_momentum_filter = True
    short_lookback_days = 10
    short_momentum_threshold = 0.0           # 短期年化 < 阈值则过滤

    # ████████ 溢价率过滤 ████████
    enable_premium_filter = True             # ✅ 本地版已支持
    premium_threshold = 0.20                 # 溢价率 > 20% 则过滤（基于IOPV/单位净值）
    premium_lookback_days = 1                # 使用最近N个交易日的数据

g.etf_pool_small_set = set(g.etf_pool_small)

def _width(s):
    w = 0
    for c in s:
        if '\u4e00' <= c <= '\u9fff' or '\u3000' <= c <= '\u303f' or '\uff00' <= c <= '\uffef':
            w += 2
        else:
            w += 1
    return w

def _ljust(s, width):
    return s + ' ' * max(0, width - _width(s))

RED = '\033[91m'
YELLOW = '\033[93m'
CYAN = '\033[96m'
GREEN = '\033[92m'
RESET = '\033[0m'

def _p(security, text):
    """小池标的高亮"""
    if security in g.etf_pool_small_set:
        return f"{RED}{text}{RESET}"
    return text

# ==================== 内存K线缓存 ====================

class KlineCache:
    """
    内存K线缓存。
    - 缓存过去 lookback_days + 10 天的K线数据
    - 当天数据使用实时行情API获取（非缓存）
    - 收盘后可保存最终数据
    """
    def __init__(self, lookback_days=25):
        self._data = {}
        self._today_prices = {}    # 存放当天实时价格
        self._fund_nav = {}        # 存放当天净值/IOPV/溢价率缓存
        self._names = {}           # 存放ETF名称缓存（复用一次批量请求）
        self._today_klines = {}    # 存放当天完整K线（收盘后填充）
        self._lookback_days = lookback_days
    
    def load_all(self, codes, force_refresh=False):
        """
        批量加载K线数据到内存。
        缓存策略：
          - 总是缓存至少 lookback_days + 10 天的数据（确保计算足够）
          - 当天数据（今天）通过实时行情API获取最新价格
          - 收盘后（15:00+）自动将当天K线并入缓存
        """
        from data.east_money import get_cached_klines
        
        clean_codes = [c.replace('.XSHG','').replace('.XSHE','').replace('.BJ','') for c in codes]
        total = len(clean_codes)
        success = 0
        
        # 计算缓存有效期：使用 lookback_days 参数
        # 如果 force_refresh 则 max_age=0（立即过期）
        # 否则 max_age=1（每天检查一次，过期自动刷新）
        max_age = 0 if force_refresh else 1
        
        for i, (orig, clean) in enumerate(zip(codes, clean_codes)):
            if i % 5 == 0:
                print(f"  [{i}/{total}]...", end='', flush=True)
            df = get_cached_klines(clean, max_age_days=max_age)
            if df is not None:
                self._data[clean] = df
                success += 1
        
        print(f"  [{total}/{total}]")
        
        # 加载成功后，尝试从实时行情获取今天价格
        self._fetch_today_prices(codes)
        
        return success
    
    def _fetch_today_prices(self, codes):
        """从腾讯API获取当天的实时价格 + 净值/IOPV，补充到缓存中"""
        clean_codes = [c.replace('.XSHG','').replace('.XSHE','').replace('.BJ','') for c in codes]
        q = tencent_quote(clean_codes)
        now = datetime.datetime.now()
        
        is_market_open = (9 <= now.hour < 15)
        
        for orig, clean in zip(codes, clean_codes):
            if clean in q and q[clean]['price'] > 0:
                self._today_prices[clean] = q[clean]['price']
            # 同样缓存净值数据（复用一个请求）
            if clean in q and 'unit_nav' in q[clean]:
                self._fund_nav[clean] = q[clean]
            # 缓存名称（同一个请求已经带回来了）
            if clean in q and 'name' in q[clean]:
                self._names[clean] = q[clean]['name']
        
        # 如果正在交易中，用实时价格覆盖K线最新价
        if is_market_open:
            for clean, price in self._today_prices.items():
                if clean in self._data and len(self._data[clean]) > 0:
                    df = self._data[clean]
                    last_date = df.iloc[-1]['date']
                    # 如果K线最后一条是今天的，更新close
                    today_str = datetime.date.today().strftime('%Y-%m-%d')
                    if last_date.strftime('%Y-%m-%d') == today_str:
                        df.iloc[-1, df.columns.get_loc('close')] = price
    
    def get_klines(self, code):
        """获取K线数据（含缓存，不含实时价格覆盖）"""
        clean = code.replace('.XSHG','').replace('.XSHE','').replace('.BJ','')
        return self._data.get(clean)
    
    def attribute_history(self, security, lookback, fields=['close']):
        """获取历史数据（盘中自动排除今天未完成的K线）

        核心规则：
          - 盘中(15:00前)：不返回今天的K线，由调用方追加实时价
          - 收盘后(15:00后)：返回缓存中的今天完整K线(含收盘价)
        """
        df = self.get_klines(security)
        if df is None or len(df) == 0:
            return pd.DataFrame()

        # 排除今天未完成的K线(确保 time window 只用已完结的交易日数据)
        now = datetime.datetime.now()
        today_start = datetime.datetime(now.year, now.month, now.day, 15, 0, 0)
        if now < today_start:
            today_str = datetime.date.today().strftime('%Y-%m-%d')
            df = df[df['date'] < pd.Timestamp(today_str)].copy()

        recent = df.tail(lookback).copy()
        recent = recent.set_index('date')
        field_map = {'close':'close','open':'open','high':'high','low':'low',
                     'volume':'volume','amount':'amount'}
        available = [field_map.get(f,f) for f in fields if field_map.get(f,f) in recent.columns]
        return recent[available]
    
    def get_fund_nav(self, security):
        """获取缓存的净值/IOPV/溢价率数据，优先使用实时批量数据。"""
        clean = security.replace('.XSHG','').replace('.XSHE','').replace('.BJ','')
        return self._fund_nav.get(clean)

    def get_name(self, security):
        """获取缓存的ETF名称（复用批量请求，不额外调API）"""
        clean = security.replace('.XSHG','').replace('.XSHE','').replace('.BJ','')
        name = self._names.get(clean)
        if name:
            return name
        # 缓存未命中时 fallback
        return get_name(security)

    def get_price(self, security, count=1):
        """获取价格，优先使用实时价格"""
        clean = security.replace('.XSHG','').replace('.XSHE','').replace('.BJ','')
        
        # 如果今天有实时价格，且 count=1，返回实时价格
        if clean in self._today_prices and count <= 1:
            df = self.get_klines(security)
            if df is not None and len(df) > 0:
                last_row = df.iloc[-1:].copy()
                last_row.loc[last_row.index[-1], 'close'] = self._today_prices[clean]
                return last_row
        
        # 否则返回缓存数据
        df = self.get_klines(security)
        if df is None or len(df) == 0:
            return None
        return df.tail(count)

# ==================== 工具函数 ====================

def get_name(security):
    try:
        return get_security_name(security)
    except:
        return "未知"

def check_profit_protection(kc, security, lookback=None, threshold=None):
    """盈利保护检查"""
    lookback = lookback or g.profit_protection_lookback
    threshold = threshold or g.profit_protection_threshold
    hist = kc.attribute_history(security, lookback, ['high'])
    if hist.empty or len(hist) < lookback:
        return False
    max_high = hist['high'].max()
    df = kc.get_price(security, count=1)
    if df is None:
        return False
    current_price = df.iloc[-1]['close']
    return current_price <= max_high * (1 - threshold)

def get_volume_ratio(kc, security, current_dt, lookback=None, threshold=None):
    """成交量比"""
    lookback = lookback or g.volume_lookback
    threshold = threshold or g.volume_threshold
    try:
        hist = kc.attribute_history(security, lookback, ['volume'])
        if hist.empty or len(hist) < lookback:
            return None
        avg_vol = hist['volume'].mean()
        df = kc.get_klines(security)
        if df is None:
            return None
        current_vol = df.iloc[-1]['volume']
        ratio = current_vol / avg_vol if avg_vol > 0 else 0
        return ratio if ratio > threshold else None
    except:
        return None

def get_annualized_returns(price_series, lookback_days):
    """加权年化收益"""
    recent = price_series[-(lookback_days + 1):]
    y = np.log(recent)
    x = np.arange(len(y))
    weights = np.linspace(1, 2, len(y))
    slope, _ = np.polyfit(x, y, 1, w=weights)
    return math.exp(slope * 250) - 1

# ==================== 核心动量计算（含过滤原因）====================

def calculate_momentum_metrics(kc, etf, current_dt):
    """
    计算ETF动量得分，返回详细结果或过滤原因。
    
    Returns:
        dict with keys: etf, name, score, annual, r2, short_annual, premium, filter_reason
        - 如果通过过滤，filter_reason 为 None
        - 如果被过滤，返回 {'etf': etf, 'name': name, 'filter_reason': '原因'}
    """
    try:
        name = kc.get_name(etf)
        lookback = max(g.lookback_days, g.short_lookback_days) + 20
        prices = kc.attribute_history(etf, lookback, ['close', 'high'])
        
        if len(prices) < g.lookback_days:
            return {
                'etf': etf, 'name': name, 'filter_reason': f'⚠️ 数据不足(需{g.lookback_days}天, 仅{len(prices)}天)',
            }
        
        df = kc.get_price(etf, count=1)
        if df is None:
            return {
                'etf': etf, 'name': name, 'filter_reason': '⚠️ 无价格数据',
            }
        current_price = df.iloc[-1]['close']
        # 构造价格序列: attribute_history 的最后日期若已是今天，
        # 用实时价替换K线收盘价（比K线收盘更实时，跌幅过滤依赖它）
        last_hist_date = prices.index[-1].date()
        if last_hist_date == current_dt:
            # 今天的数据已在 attribute_history 中 → 替换最后一条为实时价
            price_series = prices["close"].values.copy().astype(float)
            price_series[-1] = current_price
        else:
            # 今天数据不在 attribute_history → 追加实时价
            price_series = np.append(prices["close"].values, current_price)

        # ===== 提前计算得分（无论是否过滤，都算出得分） =====
        recent = price_series[-(g.lookback_days + 1):]
        y_log = np.log(recent)
        x_arr = np.arange(len(y_log))
        weights_arr = np.linspace(1, 2, len(y_log))
        slope_val, intercept_val = np.polyfit(x_arr, y_log, 1, w=weights_arr)
        annualized_returns = math.exp(slope_val * 250) - 1
        ss_res = np.sum(weights_arr * (y_log - (slope_val * x_arr + intercept_val)) ** 2)
        ss_tot = np.sum(weights_arr * (y_log - np.mean(y_log)) ** 2)
        r_squared = 1 - ss_res / ss_tot if ss_tot != 0 else 0
        score_val = annualized_returns * r_squared

        if len(price_series) >= g.short_lookback_days + 1:
            short_return = price_series[-1] / price_series[-(g.short_lookback_days + 1)] - 1
            short_annualized = (1 + short_return) ** (250 / g.short_lookback_days) - 1
        else:
            short_annualized = 0

        # ===== 1. 盈利保护检查 =====
        if check_profit_protection(kc, etf):
            record = check_profit_protection.__wrapped__ if hasattr(check_profit_protection, '__wrapped__') else None
            max_high = prices['high'].max() if not prices.empty else 0
            return {
                'etf': etf, 'name': name, 'filter_reason':
                    f"🛡️ 盈利保护: 当前{current_price:.4f} <= 近{g.profit_protection_lookback}日最高{max_high:.4f}×(1-{g.profit_protection_threshold*100:.0f}%)={max_high*(1-g.profit_protection_threshold):.4f}",
                'score': score_val, 'annual': annualized_returns, 'r2': r_squared,
                'short_annual': short_annualized,
            }

        # ===== 2. 溢价率过滤 =====
        premium_rate = None
        if g.enable_premium_filter:
            try:
                # 优先使用批量缓存数据（复用 tencent_quote 的一次请求）
                nav_data = kc.get_fund_nav(etf)
                if nav_data is None or 'unit_nav' not in nav_data:
                    # 缓存未命中时再单独请求
                    nav_data = get_fund_net_value(etf)
                if nav_data:
                    premium_rate = nav_data.get('premium_rate')
                    unit_nav = nav_data.get('unit_nav')
                    iopv = nav_data.get('iopv')
                    
                    if premium_rate is not None and abs(premium_rate) > g.premium_threshold:
                        ref = 'IOPV' if nav_data.get('iopv') else '单位净值'
                        return {
                            'etf': etf, 'name': name, 'filter_reason':
                                f"❌ 溢价率过滤: 溢价率{premium_rate*100:.2f}% > 阈值{g.premium_threshold*100:.0f}% (基于{ref})",
                            'score': score_val, 'annual': annualized_returns, 'r2': r_squared,
                            'short_annual': short_annualized, 'premium': premium_rate,
                        }
                    elif premium_rate is None:
                        # 无法获取溢价率，告警但不过滤
                        pass
                # 如果无法获取溢价率数据，跳过过滤
            except Exception as e:
                pass  # 静默失败，不阻塞流程

        # ===== 3. 成交量过滤 =====
        if g.enable_volume_check:
            vol_ratio = get_volume_ratio(kc, etf, current_dt)
            if vol_ratio is not None:
                annualized = get_annualized_returns(price_series, g.lookback_days)
                if annualized > g.volume_return_limit:
                    return {
                        'etf': etf, 'name': name, 'filter_reason':
                            f"📊 成交量过滤: 当日量/5日均量={vol_ratio:.1f}倍(阈值{g.volume_threshold:.0f}), 年化{annualized*100:.1f}% > {g.volume_return_limit*100:.0f}%",
                        'score': score_val, 'annual': annualized_returns, 'r2': r_squared,
                        'short_annual': short_annualized,
                    }

        # ===== 4. 短期动量过滤 =====
        if g.use_short_momentum_filter and short_annualized < g.short_momentum_threshold:
            return {
                'etf': etf, 'name': name, 'filter_reason':
                    f"⏳ 短期动量过滤: 近{g.short_lookback_days}日年化{short_annualized*100:.2f}% < 阈值{g.short_momentum_threshold*100:.0f}%",
                'score': score_val, 'annual': annualized_returns, 'r2': r_squared,
                'short_annual': short_annualized,
            }

        # ===== 5. (已提前计算) =====

        # ===== 6. 近3日跌幅过滤 =====
        if len(price_series) >= 4:
            day1 = price_series[-1] / price_series[-2]
            day2 = price_series[-2] / price_series[-3]
            day3 = price_series[-3] / price_series[-4]
            min_return = min(day1, day2, day3)
            if min_return < g.loss:
                return {
                    'etf': etf, 'name': name, 'filter_reason':
                        f"📉 跌幅过滤: 近3日最小单日收益{(min_return-1)*100:.2f}% < 阈值{(g.loss-1)*100:.0f}%",
                    'score': score_val, 'annual': annualized_returns, 'r2': r_squared,
                    'short_annual': short_annualized,
                }

        # ===== ✅ 通过全部过滤 =====
        return {
            'etf': etf, 'name': name, 'score': score_val,
            'annual': annualized_returns, 'r2': r_squared,
            'short_annual': short_annualized,
            'premium': premium_rate,
            'filter_reason': None,  # 通过
        }
        
    except Exception as e:
        return {
            'etf': etf, 'name': kc.get_name(etf), 'filter_reason': f'⚠️ 计算异常: {e}',
        }

# ==================== 保存得分 ====================

def save_scores(results, today, kc=None, output_dir=None):
    """保存得分到文件"""
    if output_dir is None:
        output_dir = os.path.join(PROJECT_ROOT, '得分记录')
    os.makedirs(output_dir, exist_ok=True)
    
    date_str = today.strftime('%Y%m%d') if isinstance(today, datetime.date) else today
    
    serializable = []
    for r in results:
        if r.get('filter_reason') is not None:
            continue  # 只保存通过过滤的
        serializable.append({
            'etf': r['etf'], 'name': r['name'],
            'score': round(r.get('score', 0), 6),
            'annual': round(r.get('annual', 0), 6),
            'r2': round(r.get('r2', 0), 6),
            'short_annual': round(r.get('short_annual', 0), 6),
            'premium': round(r.get('premium', 0), 6) if r.get('premium') is not None else None,
        })
    
    # JSON
    json_file = os.path.join(output_dir, f'scores_{date_str}.json')
    with open(json_file, 'w', encoding='utf-8') as f:
        json.dump(serializable, f, ensure_ascii=False, indent=2)
    print(f"💾 JSON: {json_file} ({len(serializable)} 标的)")
    
    # CSV
    csv_file = os.path.join(output_dir, f'scores_{date_str}.csv')
    if serializable:
        df = pd.DataFrame(serializable)
        df.to_csv(csv_file, index=False, encoding='utf-8-sig')
    
    # 历史汇总（去重：替换今天的旧记录）
    history_file = os.path.join(output_dir, 'scores_history.csv')
    if serializable:
        df_h = pd.DataFrame(serializable)
        df_h.insert(0, 'date', date_str)
        if os.path.exists(history_file):
            old_df = pd.read_csv(history_file, encoding='utf-8-sig')
            old_df = old_df[old_df['date'] != date_str]  # 移除今天旧记录
            combined = pd.concat([old_df, df_h], ignore_index=True)
            combined.to_csv(history_file, index=False, encoding='utf-8-sig')
        else:
            df_h.to_csv(history_file, index=False, encoding='utf-8-sig')

# ==================== 主运行函数 ====================

def run_etf_rank(today=None, auto_save=True, quiet=False, force_refresh=False):
    """
    运行ETF评分，详细展示过滤原因。
    
    Returns:
        (results, target_list)
    """
    if today is None:
        today = datetime.date.today()
    
    t0 = time.time()
    
    if not quiet:
        print(f"\n{'='*65}")
        print(f"  七星高照ETF轮动 - 评分 {today}")
        print(f"  ▸ 参数: 回看{g.lookback_days}天 | 溢价率阈值{g.premium_threshold*100:.0f}% | 短期动量阈值{g.short_momentum_threshold*100:.0f}%")
        print(f"  ▸ 池大小: {len(g.etf_pool)} 只 | 持有: {g.holdings_num} 只")
        print(f"{'='*65}")
    
    # 1. 批量加载K线数据
    if not quiet:
        print(f"\n📥 加载 {len(g.etf_pool)} 个ETF的K线数据 (缓存窗口: {g.lookback_days}天)...")
    kc = KlineCache(lookback_days=g.lookback_days)
    kc.load_all(g.etf_pool, force_refresh=force_refresh)
    t1 = time.time()
    if not quiet:
        print(f"  ⏱ 加载: {t1-t0:.1f}s")
    
    # 2. 逐只计算得分 + 过滤
    if not quiet:
        print(f"\n⚙️ 计算动量得分（含过滤）...")
        print(f"  {'='*60}")
    
    results = []
    filter_stats = {
        '通过': 0,
        '盈利保护': 0, '溢价率': 0, '成交量': 0, '短期动量': 0, '跌幅': 0,
        '数据不足': 0, '非上涨趋势': 0, '强势': 0, '未知原因': 0,
    }
    
    all_items = []  # 保存所有结果（含过滤）
    
    for etf in g.etf_pool:
        res = calculate_momentum_metrics(kc, etf, today)
        all_items.append(res)
        
        # 检查是否通过过滤且有得分
        if res.get('filter_reason') is None and 'score' in res:
            score = res['score']
            if g.min_score_threshold < score < g.max_score_threshold:
                results.append(res)
                if not quiet:
                    name = res['name']
                    line = f"  ✅ {etf:14s} {_ljust(name, 24)} | {GREEN}得分:{score:.4f}{RESET}"
                    print(_p(etf, line) if etf in g.etf_pool_small_set else line)
                filter_stats['通过'] += 1
            else:
                # 得分不在范围内
                name = res['name']
                if score <= g.min_score_threshold:
                    label = '非上涨趋势'
                else:
                    label = '强势'
                line = f"  ⏭️ {etf:14s} {_ljust(name, 24)} | {YELLOW}{label}{RESET}: 得分{score:.4f} ∉ ({g.min_score_threshold}, {g.max_score_threshold})"
                print(_p(etf, line) if etf in g.etf_pool_small_set else line)
                filter_stats[label] += 1
        else:
            reason = res.get('filter_reason', '未知原因')
            sc = res.get('score')
            sc_str = f" | {YELLOW}得分:{sc:.4f}{RESET}" if sc is not None else ''
            if not quiet:
                name = res.get('name', '未知')
                line = f"  ⏭️ {etf:14s} {_ljust(name, 24)} | {reason}{sc_str}"
                print(_p(etf, line) if etf in g.etf_pool_small_set else line)
            
            # 统计过滤类型
            if '溢价率' in reason:
                filter_stats['溢价率'] += 1
            elif '盈利保护' in reason:
                filter_stats['盈利保护'] += 1
            elif '成交量' in reason:
                filter_stats['成交量'] += 1
            elif '短期动量' in reason:
                filter_stats['短期动量'] += 1
            elif '跌幅' in reason:
                filter_stats['跌幅'] += 1
            elif '数据不足' in reason:
                filter_stats['数据不足'] += 1
            else:
                filter_stats['未知原因'] += 1
    
    t2 = time.time()
    if not quiet:
        print(f"  {'='*60}")
        print(f"  ⏱ 计算: {t2-t1:.1f}s")
    
    # 3. 排序
    results = sorted(results, key=lambda x: x['score'], reverse=True)
    
    if not quiet:
        print(f"\n{'='*65}")
        print(f"  📊 过滤统计")
        print(f"{'='*65}")
        total = sum(filter_stats.values()) + filter_stats['通过']
        print(f"  ✅ 通过: {filter_stats['通过']:2d}/{total}")
        print(f"  🛡️  盈利保护: {filter_stats['盈利保护']:2d}")
        print(f"  ❌ 溢价率:   {filter_stats['溢价率']:2d}")
        print(f"  📊 成交量:   {filter_stats['成交量']:2d}")
        print(f"  ⏳ 短期动量: {filter_stats['短期动量']:2d}")
        print(f"  📉 跌幅:     {filter_stats['跌幅']:2d}")
        print(f"  ⚠️  数据不足: {filter_stats['数据不足']:2d}")
        print(f"  📉 非上涨趋势: {filter_stats['非上涨趋势']:2d}")
        print(f"  🔥 强势:     {filter_stats['强势']:2d}")
        print(f"  ❓ 未知原因: {filter_stats['未知原因']:2d}")
    
    if not quiet and results:
        print(f"\n{'='*65}")
        print(f"  🏆 排名 (通过 {len(results)}/{len(g.etf_pool)})")
        print(f"{'='*65}")
        for i, item in enumerate(results):
            mk = _p(item['etf'], " ★" if item['etf'] in g.etf_pool_small_set else "")
            premium_str = f" | 溢价率:{item.get('premium',0)*100:.2f}%" if item.get('premium') is not None else ""
            line = f"  {i+1:2d}. {item['etf']:14s} {_ljust(item['name'], 24)} | 得分:{item['score']:.4f} | 年化:{item['annual']*100:.2f}%{premium_str}{mk}"
            print(_p(item['etf'], line) if item['etf'] in g.etf_pool_small_set else line)
    
    # 4. 最终选中
    target_etfs = []
    for item in results[:g.holdings_num]:
        if item.get('score', 0) >= g.min_score_threshold:
            target_etfs.append(item)
    if not target_etfs:
        target_etfs = [{'etf': g.defensive_etf, 'name': kc.get_name(g.defensive_etf)}]
    
    if not quiet:
        print(f"\n{'='*65}")
        print(f"  🎯 今日最终选中")
        print(f"{'='*65}")
        for t in target_etfs:
            premium_str = f" | 溢价率:{t.get('premium',0)*100:.2f}%" if t.get('premium') is not None else ""
            line = f"  ✅ {t['etf']:14s} {_ljust(t['name'], 24)}{premium_str}"
            print(_p(t['etf'], line) if t['etf'] in g.etf_pool_small_set else line)
    
    # 5. 保存得分
    if auto_save:
        save_scores(results, today, kc=kc)
        print(f"  📝 已记录今日得分到 得分记录/")
    
    if not quiet:
        print(f"\n⏱ 总耗时: {time.time()-t0:.1f}s")
    
    return results, target_etfs, all_items

# ==================== 命令行入口 ====================

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='七星高照ETF轮动 - 评分系统')
    parser.add_argument('--date', type=str, help='指定日期 YYYY-MM-DD')
    parser.add_argument('--refresh', action='store_true', help='强制刷新缓存')
    parser.add_argument('--no-save', action='store_true', help='不保存')
    parser.add_argument('--quiet', '-q', action='store_true', help='安静模式')
    args = parser.parse_args()
    
    today = datetime.date.today()
    if args.date:
        today = datetime.datetime.strptime(args.date, '%Y-%m-%d').date()
    
    run_etf_rank(today=today, auto_save=not args.no_save,
                 quiet=args.quiet, force_refresh=args.refresh)
