"""
East Money API 封装 - K线数据获取
使用 push2his.eastmoney.com 接口，直连。
含重试逻辑和文件缓存。
"""

import pandas as pd
import pickle
import os
import time
import random
import json
from datetime import datetime

# ==================== Fallback 数据源 ====================
# 当 eastmoney API 失败时，使用 mootdx (TCP) 或 百度股市通 (HTTP) 作为备选
# 参考: a-stock-data skill (V3.1)
_MOOTDX_AVAILABLE = False
try:
    from mootdx.quotes import Quotes
    _MOOTDX_AVAILABLE = True
except ImportError:
    pass

def _try_mootdx(code, market):
    """Fallback 1: 使用 mootdx TCP 协议获取K线 (最多800条)"""
    if not _MOOTDX_AVAILABLE:
        return None
    try:
        client = Quotes.factory(market='std')
        # category=10 日K, offset=800 最多800条
        df = client.bars(symbol=code, category=10, offset=800)
        if df is None or len(df) == 0:
            return None
        # mootdx 同时有 vol 和 volume 列，保留 volume 并删除 vol
        if 'vol' in df.columns and 'volume' in df.columns:
            df = df.drop(columns=['vol'])
        elif 'vol' in df.columns:
            df = df.rename(columns={'vol': 'volume'})
        df['date'] = pd.to_datetime(df['datetime'])
        df = df[['date', 'open', 'close', 'high', 'low', 'volume', 'amount']].copy()
        df = df.sort_values('date').reset_index(drop=True)
        print(f"✅ [mootdx fallback] {code}: {len(df)} 条")
        return df
    except Exception as e:
        print(f"⚠️ [mootdx失败] {code}: {e}")
        return None

def _try_baidu(code):
    """Fallback 2: 使用百度股市通API获取K线 (HTTP, 全量)"""
    import requests
    try:
        url = "https://finance.pae.baidu.com/selfselect/getstockquotation"
        params = {
            "all": "1", "isIndex": "false", "isBk": "false", "isBlock": "false",
            "isFutures": "false", "isStock": "true", "newFormat": "1",
            "group": "quotation_kline_ab", "finClientType": "pc",
            "code": code, "start_time": "", "ktype": "1",
        }
        headers = {
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/vnd.finance-web.v1+json",
            "Origin": "https://gushitong.baidu.com",
            "Referer": "https://gushitong.baidu.com/",
        }
        r = requests.get(url, params=params, headers=headers, timeout=15)
        d = r.json()
        md = d.get("Result", {}).get("newMarketData", {})
        raw = md.get("marketData", "")
        if not raw:
            return None
        
        rows = []
        for line in raw.split(";"):
            if not line.strip():
                continue
            parts = line.split(",")
            if len(parts) < 8:
                continue
            rows.append({
                'date': parts[1],
                'open': float(parts[2]),
                'close': float(parts[3]),
                'high': float(parts[5]),
                'low': float(parts[6]),
                'volume': float(parts[4]),
                'amount': float(parts[7]),
            })
        
        df = pd.DataFrame(rows)
        df['date'] = pd.to_datetime(df['date'])
        df = df.sort_values('date').reset_index(drop=True)
        print(f"✅ [百度 fallback] {code}: {len(df)} 条")
        return df
    except Exception as e:
        print(f"⚠️ [百度API失败] {code}: {e}")
        return None


CACHE_DIR = os.path.join(os.path.dirname(__file__), '..', 'cache')
os.makedirs(CACHE_DIR, exist_ok=True)

def _new_session():
    """每次新建 session"""
    import requests
    sess = requests.Session()
    sess.trust_env = False
    sess.headers.update({
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Referer": "https://quote.eastmoney.com/",
        "Connection": "close",
    })
    return sess

def _market_for(code):
    """判断市场：1=上海, 0=深圳"""
    return 1 if code.startswith(('5', '6', '9')) else 0

def get_all_klines(code, market=None, retries=3):
    """
    获取全量日K线数据（含重试）。
    
    Parameters:
        code: str, ETF代码 e.g. '518880'
        market: int, 0=深圳, 1=上海 (自动推断)
        retries: int, 失败重试次数
    
    Returns:
        DataFrame with columns: date, open, close, high, low, volume, amount
    """
    if market is None:
        market = _market_for(code)
    
    secid = f"{market}.{code}"
    
    url = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
    params = {
        'fields1': 'f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13',
        'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
        'beg': '19000101',
        'end': '20500101',
        'rtntype': '6',
        'secid': secid,
        'klt': '101',
        'fqt': '1',
    }
    
    last_error = None
    for attempt in range(retries + 1):
        try:
            if attempt > 0:
                delay = attempt * random.uniform(1, 3)
                print(f"⏳ 重试 {code} (第{attempt}次, 等待{delay:.1f}秒)...")
                time.sleep(delay)
            
            sess = _new_session()
            r = sess.get(url, params=params, timeout=30)
            data = r.json()
            klines = data.get('data', {}).get('klines', [])
            
            if not klines:
                print(f"⚠️ {code} 无K线数据")
                return None
            
            rows = []
            for k in klines:
                parts = k.split(',')
                rows.append({
                    'date': parts[0],
                    'open': float(parts[1]),
                    'close': float(parts[2]),
                    'high': float(parts[3]),
                    'low': float(parts[4]),
                    'volume': float(parts[5]),
                    'amount': float(parts[6]),
                })
            
            df = pd.DataFrame(rows)
            df['date'] = pd.to_datetime(df['date'])
            df = df.sort_values('date').reset_index(drop=True)
            return df
        
        except Exception as e:
            last_error = e
    
    print(f"❌ 获取 {code} K线失败 (已重试{retries}次): {last_error}")
    
    # ===== Fallback 1: mootdx TCP =====
    print(f"🔄 [切换 mootdx] {code}...", flush=True)
    df = _try_mootdx(code, market)
    if df is not None:
        return df
    
    # ===== Fallback 2: 百度股市通 =====
    print(f"🔄 [切换 百度] {code}...", flush=True)
    df = _try_baidu(code)
    if df is not None:
        return df
    
    print(f"❌ 所有数据源均失败: {code}")
    return None

META_FILE = os.path.join(CACHE_DIR, 'cache_meta.json')

def _read_cache_meta():
    """读取统一缓存元数据文件 {code: date_str}"""
    if not os.path.exists(META_FILE):
        return {}
    try:
        with open(META_FILE, 'r') as f:
            return json.load(f)
    except:
        return {}

def _write_cache_meta(meta):
    """写入统一缓存元数据文件"""
    with open(META_FILE, 'w') as f:
        json.dump(meta, f, indent=2)

def get_cached_klines(code, max_age_days=1):
    """
    获取带缓存的K线数据（增量更新）。
    
    不再用"距上次拉取的天数"判断过期，而是：
    1. 看缓存数据里最后一条的日期
    2. 如果最后日期 < 今天，只拉缺失的增量数据（beg=最后日期+1）
    3. 追加到缓存，永不重拉历史数据
    
    Args:
        code: 纯数字代码 (如 '518880')
        max_age_days: 保留参数（向下兼容），实际用增量逻辑
    """
    cache_file = os.path.join(CACHE_DIR, f'klines_{code}.pkl')
    meta = _read_cache_meta()
    
    # ===== 尝试加载缓存 =====
    df_cached = None
    if os.path.exists(cache_file):
        try:
            with open(cache_file, 'rb') as f:
                df_cached = pickle.load(f)
        except Exception as e:
            print(f"⚠️ [缓存读取失败] {code}: {e}")
    
    today = datetime.now()
    today_str = today.strftime('%Y-%m-%d')
    today_begin = today.strftime('%Y%m%d')
    today_ts = pd.Timestamp(today_str)
    
    if df_cached is not None and len(df_cached) > 0:
        # 找到缓存中最后一条数据的日期
        last_date = df_cached['date'].max()
        
        if last_date >= today_ts:
            # 缓存已经包含今天的数据，无需更新
            print(f"📦 [缓存] {code}: {len(df_cached)} 条 (最新: {last_date.strftime('%Y-%m-%d')})")
            return df_cached
        
        # 只拉缺失的日期
        begin_date = (last_date + pd.Timedelta(days=1)).strftime('%Y%m%d')
        print(f"📦 [缓存] {code}: {len(df_cached)} 条 (最新: {last_date.strftime('%Y-%m-%d')})")
        print(f"🌐 [增量获取] {code}: {begin_date} ~ {today_begin}", flush=True)
        
        df_new = _fetch_klines_range(code, market=None, beg=begin_date, end=today_begin)
        
        if df_new is not None and len(df_new) > 0:
            # 合并缓存 + 增量
            df = pd.concat([df_cached, df_new], ignore_index=True)
            df = df.drop_duplicates(subset=['date']).sort_values('date').reset_index(drop=True)
            with open(cache_file, 'wb') as f:
                pickle.dump(df, f)
            meta[code] = today_str
            _write_cache_meta(meta)
            print(f"💾 [已缓存] {code}: {len(df)} 条 (新增{len(df_new)}条)")
            return df
        else:
            # 增量没拉到新数据（非交易日等），缓存不变
            return df_cached
    
    # ===== 无缓存，全量拉取 =====
    print(f"🌐 [全量获取] {code} K线...", flush=True)
    df = get_all_klines(code)
    if df is not None:
        with open(cache_file, 'wb') as f:
            pickle.dump(df, f)
        meta[code] = today_str
        _write_cache_meta(meta)
        print(f"💾 [已缓存] {code}: {len(df)} 条")
    
    return df


def _fetch_klines_range(code, market=None, beg='19000101', end='20500101', retries=2):
    """
    按日期范围拉取K线（增量更新用）。
    
    走 eastmoney → mootdx → 百度 的 fallback 链，
    但只拉 beg~end 范围，不全量。
    """
    from datetime import datetime as dt_mod
    if market is None:
        market = _market_for(code)
    
    secid = f"{market}.{code}"
    url = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
    params = {
        'fields1': 'f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13',
        'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
        'beg': beg, 'end': end,
        'rtntype': '6', 'secid': secid, 'klt': '101', 'fqt': '1',
    }
    
    # East Money
    last_error = None
    for attempt in range(retries + 1):
        try:
            if attempt > 0:
                time.sleep(attempt * random.uniform(1, 2))
            sess = _new_session()
            r = sess.get(url, params=params, timeout=30)
            data = r.json()
            klines = data.get('data', {}).get('klines', [])
            if not klines:
                return None
            rows = []
            for k in klines:
                parts = k.split(',')
                if len(parts) < 7:
                    continue
                rows.append({
                    'date': parts[0], 'open': float(parts[1]), 'close': float(parts[2]),
                    'high': float(parts[3]), 'low': float(parts[4]),
                    'volume': float(parts[5]), 'amount': float(parts[6]),
                })
            df = pd.DataFrame(rows)
            df['date'] = pd.to_datetime(df['date'])
            df = df.sort_values('date').reset_index(drop=True)
            return df
        except Exception as e:
            last_error = e
    
    # Fallback: mootdx
    if _MOOTDX_AVAILABLE:
        try:
            client = Quotes.factory(market='std')
            df = client.bars(symbol=code, category=10, offset=800)
            if df is not None and len(df) > 0:
                if 'vol' in df.columns and 'volume' in df.columns:
                    df = df.drop(columns=['vol'])
                elif 'vol' in df.columns:
                    df = df.rename(columns={'vol': 'volume'})
                df['date'] = pd.to_datetime(df['datetime'])
                df = df[['date','open','close','high','low','volume','amount']].copy()
                df = df.sort_values('date').reset_index(drop=True)
                # mootdx 不支持日期筛选，用增量范围过滤
                beg_dt = pd.Timestamp(beg)
                end_dt = pd.Timestamp(end)
                df = df[(df['date'] >= beg_dt) & (df['date'] <= end_dt)]
                if len(df) > 0:
                    return df
        except Exception:
            pass
    
    # Fallback: baidu
    try:
        url_bd = "https://finance.pae.baidu.com/selfselect/getstockquotation"
        params_bd = {
            "all": "1", "isIndex": "false", "isBk": "false", "isBlock": "false",
            "isFutures": "false", "isStock": "true", "newFormat": "1",
            "group": "quotation_kline_ab", "finClientType": "pc",
            "code": code, "start_time": "", "ktype": "1",
        }
        headers = {
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/vnd.finance-web.v1+json",
            "Origin": "https://gushitong.baidu.com",
            "Referer": "https://gushitong.baidu.com/",
        }
        r = requests.get(url_bd, params=params_bd, headers=headers, timeout=15)
        md = r.json().get("Result", {}).get("newMarketData", {})
        raw = md.get("marketData", "")
        if raw:
            rows = []
            for line in raw.split(";"):
                if not line.strip():
                    continue
                parts = line.split(",")
                if len(parts) < 8:
                    continue
                rows.append({
                    'date': parts[1], 'open': float(parts[2]), 'close': float(parts[3]),
                    'high': float(parts[5]), 'low': float(parts[6]),
                    'volume': float(parts[4]), 'amount': float(parts[7]),
                })
            df = pd.DataFrame(rows)
            df['date'] = pd.to_datetime(df['date'])
            beg_dt = pd.Timestamp(beg)
            end_dt = pd.Timestamp(end)
            df = df[(df['date'] >= beg_dt) & (df['date'] <= end_dt)]
            if len(df) > 0:
                return df
    except Exception:
        pass
    
    return None

def get_security_name(code):
    """获取证券名称"""
    from data.tencent import tencent_quote
    clean_code = code.replace('.XSHG', '').replace('.XSHE', '').replace('.BJ', '')
    qt = tencent_quote([clean_code])
    if clean_code in qt:
        return qt[clean_code].get('name', '未知')
    return code

def get_security_info(code):
    """简化版 get_security_info"""
    from collections import namedtuple
    Info = namedtuple('SecurityInfo', ['display_name', 'code'])
    name = get_security_name(code)
    return Info(display_name=name, code=code)


# ==================== jqdata 兼容函数 ====================

def get_price(code, end_date=None, count=1, fields='close', frequency='daily'):
    """兼容 jqdata.get_price 精简版"""
    clean_code = code.replace('.XSHG', '').replace('.XSHE', '').replace('.BJ', '')
    df = get_cached_klines(clean_code)
    if df is None or len(df) == 0:
        return pd.Series(dtype=float) if isinstance(fields, str) else pd.DataFrame()
    
    result = df.tail(count).copy()
    
    if end_date is not None:
        if isinstance(end_date, datetime):
            end_date = end_date.date()
        if isinstance(end_date, pd.Timestamp):
            end_date = end_date.date()
        result = result[result['date'].dt.date <= end_date]
    
    single_field = isinstance(fields, str)
    if single_field:
        fields = [fields]
    
    available = [f for f in fields if f in result.columns]
    if not available:
        return pd.Series(dtype=float) if single_field else pd.DataFrame()
    
    result = result[['date'] + available].set_index('date')
    
    if single_field and len(available) == 1:
        return result[available[0]]
    
    return result

def attribute_history(security, lookback, frequency='1d', fields=['close']):
    """兼容 jqdata.attribute_history"""
    clean_code = security.replace('.XSHG', '').replace('.XSHE', '').replace('.BJ', '')
    df = get_cached_klines(clean_code)
    if df is None or len(df) == 0:
        return pd.DataFrame()
    
    recent = df.tail(lookback).copy()
    recent = recent.set_index('date')
    
    field_map = {
        'close': 'close', 'open': 'open', 'high': 'high', 'low': 'low',
        'volume': 'volume', 'amount': 'amount',
    }
    available = [field_map.get(f, f) for f in fields if field_map.get(f, f) in recent.columns]
    return recent[available]


# ==================== 溢价率 ====================
def get_premium_rate(code, date_obj, max_back_days=5):
    """免费数据源无法获取ETF净值，返回 None"""
    return None, None, None

def get_premium_rate(code, date_obj=None, max_back_days=5):
    """
    获取ETF溢价率。
    
    使用腾讯行情API获取实时净值/溢价率数据。
    盘中使用IOPV溢价率，盘后使用官方单位净值溢价率。
    
    Args:
        code: ETF代码（可带后缀如 .XSHG）
        date_obj: 日期（保留参数兼容，实际用实时数据）
        max_back_days: 最大回退天数（保留兼容）
    
    Returns:
        (premium_rate, price, net_value)
        - premium_rate: 溢价率（小数，如0.05=5%），None表示获取失败
        - price: 当前市价
        - net_value: 净值（IOPV或单位净值）
    """
    try:
        from data.tencent import get_fund_net_value
        nav_data = get_fund_net_value(code)
        if nav_data is None:
            return None, None, None
        
        premium_rate = nav_data.get('premium_rate')
        price = nav_data.get('price')
        net_value = nav_data.get('unit_nav') or nav_data.get('iopv')
        
        return premium_rate, price, net_value
    except Exception as e:
        print(f"⚠️ 溢价率获取失败 {code}: {e}")
        return None, None, None
