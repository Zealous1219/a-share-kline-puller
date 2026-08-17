# index_technicals — 指数日 K 数据（BaoStock 补拉）

## 数据来源

- **接口**：BaoStock `query_history_k_data_plus`
- **参数**：`adjustflag="2"`（前复权），`frequency="d"`，日期范围 `1990-01-01` ~ `2026-12-31`
- **用途**：补拉 Wind `get_index_kline` 无法覆盖的 340 只深市指数（399106+、399231+ 等）
- **拉取原因**：Wind `get_index_kline` 对深市指数覆盖率仅 33%（167/507），剩余 340 只返回空数据

## 与 `index/` 的关系

| 目录 | 数据源 | 数量 | 状态 |
|------|--------|------|------|
| `index/` | Wind `get_index_kline` | 167 只（上证指数系列） | 已完成 |
| `index_technicals/` | BaoStock | 340 只（深市指数系列） | 已完成 |

两个目录数据源不同，但字段格式完全一致（`date,code,open,high,low,close,volume,turnover,changehandrate,avprice`），可直接合并使用，无需二次转换。

BaoStock 字段映射如下：

| CSV 字段 | BaoStock 字段 | 说明 |
|---|---|---|
| `volume` | `volume` | 原始成交量，不做处理 |
| `turnover` | `amount` | 原始成交额，单位为元，不换算 |
| `changehandrate` | `turn` | 原始换手率，不乘除 100 |
| `avprice` | 无可靠来源 | 始终留空，不用成交额/成交量推算 |

BaoStock 前复权结果与 Wind 前复权一致（已通过 399234.SZ 交叉验证，60 交易日价量 0% 差异）。

## 历史背景

最初计划通过 Wind `get_index_technicals`（NL 自然语言接口）补拉，实测发现该接口返回格式不固定且未实际调用，最终改用 BaoStock 免费 API。BaoStock 覆盖 100% 深市指数，无频率限制，数据质量已验证。

## 拉取脚本

`pull_index_baostock.py`（项目根目录），支持：

- 内置重连逻辑（WinError 10054 自动 logout + login）
- 内置 rate limiting（每只间隔 1.5s）
- 输出到本目录，自动更新 `拉取进度.json`

```bash
python pull_index_baostock.py      # 拉取全部待补拉
python pull_index_baostock.py 50   # 拉取指定数量
```
