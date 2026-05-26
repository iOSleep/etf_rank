# 七星高照 ETF 行情

手机浏览器打开，实时查看 ETF 动量评分排名。

## 工作原理

GitHub Actions 每个交易日 15:30 自动运行 Python 脚本，拉取行情数据计算得分，生成网页发布到 GitHub Pages。

## 查看地址

`https://你的用户名.github.io/etf_rank`

## 本地运行

```bash
pip install -r requirements.txt
python main.py
open output/index.html
```
