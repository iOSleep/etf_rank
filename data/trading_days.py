"""
交易日历模块。
从 East Money 获取全量K线数据提取交易日，本地缓存。
"""

import os
import pandas as pd
from datetime import datetime, date, timedelta
import pickle

CACHE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'cache')
TRADING_CALENDAR_FILE = os.path.join(CACHE_DIR, 'trading_calendar.pkl')

def ensure_cache_dir():
    os.makedirs(CACHE_DIR, exist_ok=True)

def _build_calendar_from_klines():
    """从任一ETF的K线数据提取交易日"""
    from data.east_money import get_cached_klines
    
    # 用 518880 (上海) 的K线做交易日历（数据最全）
    df = get_cached_klines('518880', max_age_days=7)
    if df is not None and len(df) > 0:
        return sorted(df['date'].dt.date.unique())
    return None

def build_trading_calendar():
    """
    构建交易日历，优先从缓存读取。
    返回 (calendar_dict, days_list)
    """
    ensure_cache_dir()
    
    # 从缓存读取
    if os.path.exists(TRADING_CALENDAR_FILE):
        try:
            with open(TRADING_CALENDAR_FILE, 'rb') as f:
                days = pickle.load(f)
            return {d: True for d in days}, days
        except:
            pass
    
    # 从K线重建
    print("🌐 重建交易日历...")
    days = _build_calendar_from_klines()
    
    if days is not None:
        with open(TRADING_CALENDAR_FILE, 'wb') as f:
            pickle.dump(days, f)
        return {d: True for d in days}, days
    
    # 兜底
    return _fallback_calendar()

def _fallback_calendar():
    """简单的日历推断（周一到周五）"""
    start = date(2005, 1, 1)
    end = date.today() + timedelta(days=30)
    days = []
    d = start
    while d <= end:
        if d.weekday() < 5:
            days.append(d)
        d += timedelta(days=1)
    return {d: True for d in days}, days

def is_trading_day(d=None):
    if d is None:
        d = date.today()
    if isinstance(d, str):
        d = pd.Timestamp(d).date()
    cal, _ = build_trading_calendar()
    return d in cal

def get_previous_trading_day(d=None):
    if d is None:
        d = date.today()
    if isinstance(d, str):
        d = pd.Timestamp(d).date()
    cal, days = build_trading_calendar()
    sorted_days = sorted(days)
    if d in cal:
        idx = sorted_days.index(d)
        return sorted_days[idx - 1] if idx > 0 else d
    # 找最近的交易日
    for i in range(1, 10):
        test = d - timedelta(days=i)
        if test in cal:
            return test
    return d - timedelta(days=1)

def get_trade_days(end_date=None, count=5):
    """获取最近的N个交易日"""
    cal, days = build_trading_calendar()
    sorted_days = sorted(days)
    
    if end_date is None:
        end_date = date.today()
    if isinstance(end_date, str):
        end_date = pd.Timestamp(end_date).date()
    if isinstance(end_date, pd.Timestamp):
        end_date = end_date.date()
    
    filtered = [d for d in sorted_days if d <= end_date]
    return filtered[-count:] if len(filtered) >= count else filtered


# 启动时构建日历
if __name__ == '__main__':
    cal, days = build_trading_calendar()
    print(f"交易日历: {len(days)} 天")
    print(f"最新5个: {days[-5:]}")
    print(f"今天 {'是' if is_trading_day() else '不是'}交易日")
