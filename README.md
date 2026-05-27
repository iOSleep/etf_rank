# ⭐ 七星高照 ETF 轮动

基于加权动量因子的 A 股 ETF 轮动评分 App，40 只 ETF 每日排序，6 道过滤筛选最优标的。

## 功能

- **实时行情** — 腾讯 API 批量获取 40 只 ETF 的名称、现价、涨跌幅、净值/溢价率
- **动量评分** — 加权线性回归拟合对数价格，计算年化收益 × R² 得分
- **6 道过滤** — 盈利保护 → 溢价率 → 成交量 → 短期动量 → 得分范围 → 近 3 日跌幅
- **SQLite 缓存** — K 线增量更新，盘中不拉未收数据，秒开
- **日志面板** — 底部 Tab 查看所有网络请求和计算过程

## 技术栈

Flutter 3.44 · Dart 3.12 · Provider · sqflite · http · charset(GBK)

## 运行

```bash
# 真机
flutter run -d <device-id>

# 桌面调试
flutter run -d macos

# 打包
flutter build apk --debug
```

## 项目结构

```
lib/
├── main.dart                     # App 入口
├── models/                       # KlineRow, EtfResult
├── services/                     # api_service(腾讯+东财), cache_service(SQLite), log_service
├── engine/                       # config(ETF池+参数), momentum(加权回归), filters(6道), ranking(编排)
├── state/                        # ranking_store (ChangeNotifier)
└── ui/                           # home_page(排名+下拉刷新), log_page(日志Tab), widgets/
```
