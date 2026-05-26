#!/usr/bin/env python3
"""
GitHub Actions 入口：跑评分 → 生成 HTML
"""
import os, sys, json, datetime, time

# 确保当前目录在 path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import run  # 这就是七星研究-日志_本地版.py

def _is_trading_time():
    """9:40-15:10 北京时间, 周一至周五"""
    now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
    if now.weekday() >= 5:
        return False
    t = now.hour * 60 + now.minute
    return 9*60+40 <= t <= 15*60+10

def gen_html(results, targets, today, elapsed):
    """生成手机友好的排名页面"""
    passed = sorted([r for r in results if r.get('filter_reason') is None], key=lambda r: r.get('score', -999), reverse=True)
    failed = sorted([r for r in results if r.get('filter_reason') is not None], key=lambda r: r.get('score', -999), reverse=True)
    
    def pct(v):
        if v is None: return '-'
        return ('+' if v >= 0 else '') + f'{v*100:.2f}%'
    
    def fmt_code(c):
        return c.replace('.XSHG','').replace('.XSHE','')

    rows_html = ''
    for i, r in enumerate(passed):
        ann_cls = "pos" if r.get("annual",0) > 0 else "neg"
        rows_html += f'''
        <div class="card pass">
            <div class="top">
                <span class="rank">{'🥇' if i==0 else '🥈' if i==1 else '🥉' if i==2 else '#'+str(i+1)}</span>
                <div class="name"><b>{r['name']}</b><span class="code">{fmt_code(r['etf'])}</span></div>
                <span class="status green">得分 {r["score"]:.4f}</span>
            </div>
            <div class="metrics">
                <span>年化 <b class="{ann_cls}">{pct(r.get("annual"))}</b></span>
                <span>R² <b>{r.get("r2",0):.4f}</b></span>
            </div>
        </div>'''

    for r in failed:
        reason = r.get('filter_reason', '未知')
        # 提取简短标签
        tag = '过滤'
        if '溢价率' in reason: tag = '溢价率'
        elif '盈利保护' in reason: tag = '盈利保护'
        elif '成交量' in reason: tag = '成交量'
        elif '短期动量' in reason: tag = '短期动量'
        elif '跌幅' in reason: tag = '跌幅'
        elif '数据不足' in reason: tag = '数据不足'
        elif '得分' in reason: tag = '得分'
        
        sc = r.get('score')
        score_str = f'得分 {sc:.4f}' if sc is not None else ''
        
        rows_html += f'''
        <div class="card fail">
            <div class="top">
                <span class="rank">⏭</span>
                <div class="name"><b>{r.get('name','?')}</b><span class="code">{fmt_code(r.get('etf',''))}</span></div>
                <div class="status red">{tag}</div>
            </div>
            <div class="metrics">
                <span>{score_str}</span>
                <span>{reason}</span>
            </div>
        </div>'''

    # 信号
    signal_html = ''
    if targets:
        t = targets[0]
        signal_html = f'''
        <div class="signal">
            🎯 今日推荐：<b>{t['name']}</b> ({fmt_code(t['etf'])})
        </div>'''

    html = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>七星高照ETF行情</title>
<style>
* {{margin:0;padding:0;box-sizing:border-box}}
body {{font-family:-apple-system,sans-serif;background:#f5f5f5;color:#1a1a1a;max-width:480px;margin:0 auto;padding:8px}}
h1 {{font-size:18px;text-align:center;padding:8px 0 2px}}
.ts {{text-align:center;color:#999;font-size:11px;margin-bottom:8px}}
.stat {{display:flex;justify-content:center;gap:16px;font-size:12px;margin-bottom:6px}}
.stat .g {{color:#16a34a}} .stat .r {{color:#dc2626}}
.signal {{background:#fef3c7;border-radius:8px;padding:8px 12px;text-align:center;font-size:13px;margin-bottom:8px}}
.card {{background:#fff;border-radius:8px;padding:8px 10px;margin-bottom:4px;box-shadow:0 1px 2px rgba(0,0,0,0.04)}}
.card.pass {{border-left:3px solid #16a34a}}
.card.fail {{border-left:3px solid #dc2626;opacity:0.8}}
.top {{display:flex;align-items:center;gap:6px}}
.rank {{font-size:16px;min-width:24px;text-align:center}}
.name {{flex:1;min-width:0}} .name b {{font-size:13px}} .code {{font-size:10px;color:#999}}
.status {{font-size:10px;padding:2px 8px;border-radius:12px;font-weight:600}}
.green {{background:#dcfce7;color:#16a34a}}
.red {{background:#fee2e2;color:#dc2626}}
.metrics {{display:flex;flex-wrap:wrap;gap:10px;margin-top:6px;font-size:11px;color:#666}}
.metrics b {{color:#1a1a1a}} .pos {{color:#16a34a}} .neg {{color:#dc2626}}
.footer {{text-align:center;color:#bbb;font-size:10px;padding:16px 0 32px}}
</style>
</head>
<body>
<h1>⭐ 七星高照ETF行情</h1>
<p class="ts">更新时间：{datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).strftime('%Y-%m-%d %H:%M')} | ⏱ {elapsed}s</p>
<div class="stat"><span>共 {len(results)} 只</span><span class="g">✅ 通过 {len(passed)}</span><span class="r">⛔ 过滤 {len(failed)}</span></div>
{signal_html}
{rows_html}
<div class="footer">基于加权动量因子 · 每日自动更新 · GitHub Actions</div>
</body>
</html>'''
    return html

if __name__ == '__main__':
    today = datetime.date.today()
    t0 = time.time()
    
    print(f'=== 七星高照 {today} ===')
    
    # 非交易时段跳过
    if not _is_trading_time():
        print('⏸ 非交易时段(9:40-15:10)，跳过')
        raise SystemExit(0)

    # 跑评分
    results, targets, all_items = run.run_etf_rank(today=today, auto_save=False, quiet=True, force_refresh=False)
    
    elapsed = time.time() - t0
    
    # 生成 HTML
    html = gen_html(all_items, targets, today, f'{elapsed:.1f}')
    os.makedirs('output', exist_ok=True)
    with open('output/index.html', 'w', encoding='utf-8') as f:
        f.write(html)
    
    print(f'\n📄 HTML 已生成: output/index.html')
