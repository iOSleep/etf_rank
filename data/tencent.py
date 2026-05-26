"""
腾讯财经 API - 实时行情 + 名称查询
直连 HTTP，速度快，不封IP。
"""

import urllib.request

def _prefix(code):
    """给代码加上交易所前缀"""
    code = code.strip()
    if code.startswith(('6', '9', '5')):
        return f"sh{code}"
    elif code.startswith('8'):
        return f"bj{code}"
    else:
        return f"sz{code}"


def _parse_nav_fields(vals):
    """从腾讯API返回的vals中提取净值/IOPV/溢价率字段。
    
    腾讯行情API对基金/ETF返回扩展字段，尾部结构（以CNY为锚点）：
      CNY-5: 溢价率%     CNY-4: 单位净值  CNY-3: 累计增长率
      CNY-2: 净值涨跌幅%  CNY-1: 前日净值   CNY: "CNY"
      CNY+1: 标志        CNY+2: 状态字符串  CNY+3: IOPV

    Returns: dict or None
    """
    n = len(vals)
    if n < 80:
        return None
    # 去掉末尾可能的引号
    while n > 0 and vals[n-1] == '"':
        n -= 1
    if n < 60:
        return None

    # 找到CNY锚点位置（从后往前找）
    cny_idx = -1
    for i in range(n - 1, max(0, n - 20), -1):
        if 'CNY' in str(vals[i]):
            cny_idx = i
            break
    if cny_idx < 7:
        return None

    def _sf(idx):
        s = vals[idx] if 0 <= idx < n else ''
        s = s.strip()
        try:
            return float(s) if s else None
        except ValueError:
            return None

    premium_pct = _sf(cny_idx - 5)   # 溢价率%
    unit_nav    = _sf(cny_idx - 4)    # 单位净值
    nav_chg_pct = _sf(cny_idx - 2)    # 净值涨跌幅%
    prev_nav    = _sf(cny_idx - 1)    # 前日净值
    iopv        = _sf(cny_idx + 3)    # IOPV (部分ETF有)
    current_price = float(vals[3]) if vals[3] else 0

    # 计算溢价率
    premium_rate = None
    if premium_pct is not None:
        premium_rate = premium_pct / 100.0
    if premium_rate is None and unit_nav and unit_nav > 0 and current_price > 0:
        premium_rate = (current_price - unit_nav) / unit_nav
    elif premium_rate is None and iopv and iopv > 0 and current_price > 0:
        premium_rate = (current_price - iopv) / iopv

    return {
        'unit_nav':       unit_nav,
        'prev_nav':       prev_nav,
        'iopv':           iopv,
        'premium_rate':   premium_rate,
        'premium_pct':    premium_pct,
        'nav_change_pct': nav_chg_pct,
    }


def tencent_quote(codes: list[str]) -> dict[str, dict]:
    """
    批量获取腾讯财经实时行情。
    
    Args:
        codes: 纯数字代码列表，如 ["518880", "159915"]
    
    Returns:
        {code: {name, price, last_close, open, high, low, ...}}
    """
    # 清理后缀并加前缀
    clean_codes = []
    for c in codes:
        c = c.replace('.XSHG', '').replace('.XSHE', '').replace('.BJ', '').strip()
        clean_codes.append(c)
    
    prefixed = [_prefix(c) for c in clean_codes]
    
    url = "https://qt.gtimg.cn/q=" + ",".join(prefixed)
    req = urllib.request.Request(url)
    req.add_header("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")
    
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        data = resp.read().decode("gbk")
    except Exception as e:
        print(f"⚠️ 腾讯API请求失败: {e}")
        return {}
    
    result = {}
    for line in data.strip().split(";"):
        if not line.strip() or "=" not in line or '"' not in line:
            continue
        try:
            key = line.split("=")[0].split("_")[-1]
            vals = line.split('"')[1].split("~")
            if len(vals) < 53:
                continue
            code = key[2:]  # 去掉 sh/sz 前缀
            entry = {
                "name":         vals[1],
                "price":        float(vals[3]) if vals[3] else 0,
                "last_close":   float(vals[4]) if vals[4] else 0,
                "open":         float(vals[5]) if vals[5] else 0,
                "high":         float(vals[33]) if vals[33] else 0,
                "low":          float(vals[34]) if vals[34] else 0,
                "volume":       float(vals[36]) if vals[36] else 0,
                "amount_wan":   float(vals[37]) if vals[37] else 0,
                "turnover_pct": float(vals[38]) if vals[38] else 0,
                "pe_ttm":       float(vals[39]) if vals[39] else 0,
                "mcap_yi":      float(vals[44]) if vals[44] else 0,
                "pb":           float(vals[46]) if vals[46] else 0,
            }
            # 顺便解析净值/IOPV/溢价率（ETF特有字段）
            nav = _parse_nav_fields(vals)
            if nav:
                entry.update(nav)
            result[code] = entry
        except (IndexError, ValueError):
            continue
    
    return result


# ==================== 基金净值 / 溢价率 ====================

def get_fund_net_value(code, batch_result=None):
    """
    获取单只ETF的净值/IOPV/溢价率。
    
    如果已通过 tencent_quote 批量获取，可传入 batch_result 复用结果。
    """

    if batch_result is not None:
        clean = code.replace('.XSHG','').replace('.XSHE','').replace('.BJ','').strip()
        entry = batch_result.get(clean)
        if entry and 'unit_nav' in entry:
            return {
                'unit_nav':       entry.get('unit_nav'),
                'prev_nav':       entry.get('prev_nav'),
                'iopv':           entry.get('iopv'),
                'premium_rate':   entry.get('premium_rate'),
                'premium_pct':    entry.get('premium_pct'),
                'nav_change_pct': entry.get('nav_change_pct'),
                'price':          entry.get('price', 0),
            }
        # fallback: 批次结果中没有净值数据，走单个请求
    
    # 原有逻辑保持不变（逐个请求，供不被batch_result覆盖的场景使用）
    # 清理代码
    clean_code = code.replace('.XSHG', '').replace('.XSHE', '').replace('.BJ', '').strip()
    prefixed = _prefix(clean_code)
    
    url = f"https://qt.gtimg.cn/q={prefixed}"
    req = urllib.request.Request(url)
    req.add_header("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")
    
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        data = resp.read().decode("gbk")
    except Exception as e:
        print(f"⚠️ 腾讯基金净值API请求失败 {code}: {e}")
        return None
    
    try:
        line = data.strip().split(";")[0]
        vals = line.split('"')[1].split("~")
        if len(vals) < 80:
            return None
        
        n = len(vals)
        # 去掉末尾可能的引号
        while n > 0 and vals[n-1] == '"':
            n -= 1
        
        # 当前市价 (field 3)
        current_price = float(vals[3]) if vals[3] else 0
        
        # 找到CNY锚点位置
        cny_idx = -1
        for i in range(n - 1, max(0, n - 20), -1):
            if 'CNY' in str(vals[i]):
                cny_idx = i
                break
        
        if cny_idx < 7:
            return None  # 找不到CNY锚点，数据不完整
        
        def _safe_float(idx):
            s = vals[idx] if 0 <= idx < n else ''
            s = s.strip()
            try:
                return float(s) if s else None
            except ValueError:
                return None
        
        # 相对CNY提取字段
        premium_pct = _safe_float(cny_idx - 5)   # 溢价率%
        unit_nav    = _safe_float(cny_idx - 4)    # 单位净值
        nav_chg_pct = _safe_float(cny_idx - 2)    # 净值涨跌幅%
        prev_nav    = _safe_float(cny_idx - 1)    # 前日净值
        iopv        = _safe_float(cny_idx + 3)    # IOPV (部分ETF有)
        
        # 计算溢价率
        premium_rate = None
        
        # 优先使用API返回的溢价率
        if premium_pct is not None:
            premium_rate = premium_pct / 100.0  # 转小数
        
        # 如API没有溢价率，手动计算
        if premium_rate is None and unit_nav and unit_nav > 0 and current_price > 0:
            premium_rate = (current_price - unit_nav) / unit_nav
        elif premium_rate is None and iopv and iopv > 0 and current_price > 0:
            premium_rate = (current_price - iopv) / iopv
        
        return {
            'unit_nav':       unit_nav,
            'prev_nav':       prev_nav,
            'iopv':           iopv,
            'premium_rate':   premium_rate,
            'premium_pct':    premium_pct,
            'nav_change_pct': nav_chg_pct,
            'price':          current_price,
        }
    
    except (IndexError, ValueError) as e:
        print(f"⚠️ 腾讯基金净值API解析失败 {code}: {e}")
        return None
