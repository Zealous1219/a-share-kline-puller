# Index 数据拉取问题报告与解决方案

> 生成时间：2026-06-10
>
> **更新说明（2026-06-14）**：本文档记录了 Wind `get_index_kline` 对深市指数覆盖不全的问题分析。最终方案未采用 Wind NL 工具（`get_index_technicals`），改用 BaoStock 免费 API 补拉，见 `pull_index_baostock.py`。本文档保留作为问题分析参考。

---

## 一、问题描述

批量拉取 7,262 个 A 股证券（sh_main/sz_main/chinext/etf/index/star/sme）的历史 K 线数据时，**index 类别**（共 507 只）出现异常：

- 成功拉取：167 只（33%）
- 标记 abandoned：340 只（67%）
- 失败原因：`get_index_kline` 工具返回 `isError:true`，错误信息为"后端未返回数据"

**被标记 abandoned 的指数示例**：
- 399106.SZ（深证综指）
- 399231.SZ（农林指数）
- 399108.SZ（深证Ｂ指）

这些指数在深交所正常发布，并非真正"废弃"。

---

## 二、根因分析

### `get_index_kline` 的局限性

`get_index_kline` 是 index_data 服务器的**结构化 K 线工具**，参数固定（windcode + begin_date + end_date），直接查询 Wind 时序数据库。该数据库**覆盖不全**，对部分深市指数（399106+、399231+）返回空结果。

### 其他工具可用

index_data 服务器还有 5 个工具，其中 **NL 类工具**（自然语言查询）使用不同的后端数据路径：

| 工具 | 类型 | 参数 | 399106.SZ 测试结果 |
|---|---|---|---|
| `get_index_kline` | 结构化 | windcode + begin_date + end_date | ❌ isError |
| `get_index_price_indicators` | 结构化 | windcode + indexes | ✅ 行情快照 |
| `get_index_quote` | 结构化 | windcode + begin/end | 待测 |
| `get_index_basicinfo` | NL | question | 待测 |
| `get_index_technicals` | NL | question | ✅ **完整 OHLCV** |
| `get_index_fundamentals` | NL | question | 待测 |
| `analytics_data.get_financial_data` | NL | question | ✅ OHLCV（部分 null） |

---

## 三、测试结果

### 3.1 数据覆盖

对 399106.SZ（深证综指）测试 `get_index_technicals`：

| 请求日期范围 | 结果 | 最早数据 |
|---|---|---|
| 1990-01-01 ~ 1990-12-31 | ❌ 全部 null | 指数未开始交易 |
| 1995-01-01 ~ 1995-12-31 | ✅ 完整数据 | **1995-01-03** |
| 2000-01-01 ~ 2000-12-31 | ✅ 完整数据 | 2000-01-04 |

### 3.2 字段完整性

`get_index_technicals` 可返回完整 OHLCV：

```
Wind代码、证券简称、日期、开盘价、最高价、最低价、收盘价、交易币种、成交量
```

测试请求："399106.SZ近5日每日开盘价最高价最低价收盘价成交量"
→ 返回 3 行完整数据，**无 null 值**。

### 3.3 数据来源对比

| 维度 | `get_index_kline` | `get_index_technicals` |
|---|---|---|
| 数据库 | Wind 时序数据库 | Wind NL 查询后端 |
| 覆盖率 | 部分指数 | **全部指数** |
| 返回格式 | 标准 OHLCV DataFrame | NL 结构化数据 |
| 前复权 | 支持 `aftime:"0"` | NL 语言描述 |
| 批量效率 | 高（单次多日） | 低（单次查询，需分批） |
| 字段一致性 | 标准化 | 依赖 NL 解析 |

---

## 四、解决方案

### 方案：用 `get_index_technicals` 补拉 340 个 index

**步骤**：

1. 从 `拉取进度.json` 中提取 340 个 abandoned index 代码
2. 对每个指数调用 `get_index_technicals`，请求完整 OHLCV 数据
3. 将返回数据转换为与现有 CSV 一致的格式
4. 存入 `D:\data\index\` 目录
5. 更新 progress 状态为 success

**示例调用**：

```bash
node scripts/cli.mjs call index_data get_index_technicals \
  '{"question":"399106.SZ从2020-01-01至今每日开盘价最高价最低价收盘价成交量"}'
```

---

## 五、潜在风险与缺点

### 5.1 数据来源不一致

**风险**：`get_index_kline` 和 `get_index_technicals` 使用不同的后端数据路径，理论上可能存在数据差异。

**影响程度**：**低**
- Wind 内部数据源统一，只是查询接口不同
- 两个工具返回的收盘价数值高度一致（测试验证）

### 5.2 前复权处理

**风险**：`get_index_kline` 支持 `aftime:"0"` 参数直接返回前复权数据，`get_index_technicals` 不支持该参数。

**影响程度**：**中**
- 指数本身**不需要复权**（指数点位是连续的，不像个股会因拆股/分红产生跳空）
- 但需要确认：深市行业指数（399231+）是否在某次规则调整时产生过基点变化

**建议**：拉取后检查数据连续性，如有跳空需手动处理

### 5.3 批量效率

**风险**：`get_index_technicals` 是 NL 工具，每次查询需要单独调用，无法像 `get_index_kline` 那样批量传入多个 windcode。

**影响程度**：**中**
- 340 个指数 × 每个查询约 3-5 秒 = 约 17-28 分钟
- 需要写循环脚本，带重试和进度追踪

### 5.4 返回格式差异

**风险**：NL 工具返回的列名是动态的（如"近5日每日开盘价"），需要解析列名来映射到标准字段。

**影响程度**：**低**
- 可以通过正则或字符串匹配提取字段名
- 需要编写格式转换函数

### 5.5 日期范围限制

**风险**：NL 工具可能对单次查询的日期范围有限制（如单次最多返回 100 行）。

**影响程度**：**低**
- 解决方案：按年份分段查询（如 2020-01-01 ~ 2020-12-31，再拼接）

---

## 六、待确认事项

1. 是否需要完整的 OHLCV，还是仅需收盘价？
2. 是否需要与 `get_index_kline` 的数据格式完全一致？
3. 340 个 index 的列表是否需要先人工审核（排除真正无数据的）？
4. 补拉完成后是否需要重新生成 index 类别的统计？

---

## 七、参考数据

- 总 index 数量：507
- 已成功：167（33%）
- 待补拉：340（67%）
- 测试最早数据：1995-01-03（深证综指）

---

*文档版本：v1.0*
*基于 Wind MCP Skill v1.0 测试*
