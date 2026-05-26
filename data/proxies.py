"""
代理配置：直接连接模式（使用 require_escalated 运行，可直接访问外网）。
East Money API 可直连，无需代理。
"""

import os

def get_proxies():
    """返回 None 表示直连"""
    return None

def make_direct_session():
    """创建直连 session"""
    import requests
    sess = requests.Session()
    sess.trust_env = False  # ignore any env proxies
    return sess

make_session = make_direct_session  # 别名
