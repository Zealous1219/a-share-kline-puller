# A 股日 K 数据拉取系统

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.x+-3776AB?logo=python&logoColor=white)
![Wind API](https://img.shields.io/badge/Wind%20API-dual--source-FF6F00)
![BaoStock](https://img.shields.io/badge/BaoStock-supplement-4CAF50)
![License](https://img.shields.io/badge/license-MIT-blue)

> Wind API 主源 + BaoStock 补源双架构，PowerShell 脚本集，含 19 字段进度追踪、原子写入与断点续跑。

基于 Wind API + BaoStock 双源架构的 A 股日 K（前复权）数据批量拉取系统，构建稳定的 stock-data pipeline。覆盖沪深主板、创业板、科创板、中小板、STAR、ETF 和指数，为量化金融（quantitative-finance）分析提供长期可用的历史数据。具备 19 字段进度追踪、原子写入、断点续跑、租约锁与自动备份，适合长期大规模数据采集。

## Features

- **双源架构**：Wind API 主源 + BaoStock 补源，解决 Wind 深市指数覆盖不全
- **全量覆盖**：沪深主板/创业板/科创板/中小板/STAR/ETF/指数（不含退市股和北交所）
- **工程级容错**：19 字段进度追踪、原子写入、断点续跑、租约锁、自动备份
- **多设备协同**：updatedBy 字段追溯来源设备，支持多设备分批拉取
- **PowerShell 5.1 兼容**：UTF-8 with BOM 处理中文路径，原生 .NET IO 绕开 PS 5.1 限制
- **审核队列**：自动标记 `needsManualReview` 条目，分级处理 short_history / no_data_candidate

---

## 环境要求

- Windows + PowerShell 5.1
- Node.js（用于 JSON 数据处理）
- Python 3.x + baostock（指数补拉用，`pip install baostock`）
- [Wind AIFin 平台](https://aifinmarket.wind.com.cn/) 账号、Wind MCP Skill 和 API key。Skill 必须安装在项目根目录下的 `.agents\skills\wind-mcp-skill\`，脚本会从 `.agents\skills\wind-mcp-skill\scripts\cli.mjs` 调用它。

---

## 目录结构

```
项目根目录\
├── pull_batch.ps1                      # 主拉取脚本
├── convert_kline.ps1                   # Wind JSON → CSV 转换（内部调用）
├── pull_index_baostock.py              # BaoStock 指数补拉脚本（Python）
├── review_queue.ps1                    # 审核队列扫描
├── 拉取进度.json                        # 进度追踪（v1.3 schema，自动生成）
├── 拉取进度.json.sample                # 进度文件结构示例（首次使用参考）
├── 拉取进度.review_queue.json          # 审核队列输出（自动生成）
├── 拉取进度.review_queue.json.sample  # 审核队列结构示例
├── .keys.json.sample                    # API key 格式示例（git tracked）
├── .keys.json                          # API key（gitignored）
├── .gitignore
├── lists/
│   └── stock_list.csv                  # 源股票列表（category, symbol）
├── A-shares/                           # A 股 CSV（数据目录，仅保留结构）
├── etf/                                # ETF CSV（数据目录，仅保留结构）
├── index/                              # 指数 CSV（Wind 拉取的上证指数系列，仅保留结构）
├── index_technicals/                   # 指数 CSV（BaoStock 补拉的深市指数系列，仅保留结构）
├── batch_log/                          # 每日拉取日志（自动生成）
├── _backup/                            # 自动备份（进度文件 + 脚本版本）
├── _tmp/                               # 临时文件
├── _archive/                           # 旧分析脚本归档
└── .agents/                            # Wind MCP Skill（需自行安装）
```

> **注**：`_backup/`、`_tmp/`、`batch_log/`、`_archive/` 目录在首次运行时脚本自动创建，`git clone` 后不会立即显示。

---

## 数据格式规范

### CSV 文件

- 文件名：`{exchange}_{code}.csv`（小写），如 `sh_600519.csv`
- 文件内 code：`{exchange}.{code}`，如 `sh.600519`
- 字段顺序：`date,code,open,high,low,close,volume,turnover,changehandrate,avprice`
- 日期格式：`yyyy/M/d`（无前导零），如 `2026/6/8`
- 行序：Wind/BaoStock 正常返回通常按日期升序；转换器保留接口返回顺序，不额外排序
- 编码：UTF-8 无 BOM
- 行尾：LF（Unix 风格）
- `volume`：原始数据，未做任何处理
- `turnover`：原始成交额，单位为元；保留 Wind 原始元值，不换算
- `changehandrate`：原始换手率；保留 Wind 原始值，不乘除 100
- `avprice`：原始均价；保留 Wind 原始值，不重新计算

```csv
date,code,open,high,low,close,volume,turnover,changehandrate,avprice
2024/6/3,sh.600000,9.90,10.30,9.70,10.10,1000,123456.789,1.23,10.25
```

### Wind API 参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `aftype` | `0` | 前复权 |
| `period` | `10` | 日 K |
| 日期范围 | `19900101` - `20261231` | 覆盖全部历史 |

### 股票来源

`lists/stock_list.csv` 包含 7 个类别：

| 类别 | 说明 | 交易所前缀 |
|------|------|-----------|
| `sh_main` | 沪市主板 | `sh.` / `SH` |
| `sz_main` | 深市主板 | `sz.` / `SZ` |
| `chinext` | 创业板 | `sz.` / `SZ` |
| `star` | 科创板 | `sh.` / `SH` |
| `sme` | 中小板 | `sz.` / `SZ` |
| `etf` | ETF / LOF | `sh.` / `sz.` |
| `index` | 指数 | `sh.` / `sz.` |

---

## 脚本说明

### `pull_batch.ps1`（核心）

批量拉取脚本，负责从 Wind API / BaoStock 获取日 K 数据并写入 `拉取进度.json`。每次调用按以下流程执行：

1. 启动校验（9 项）：keys 文件、进度文件、磁盘空间、今日计数、锁定状态等
2. 锁定目标条目（status → `claimed`，写入 `leaseUntil`）
3. 逐只拉取：spawn Node.js 子进程调用 Wind API → `convert_kline.ps1` 转换 → 原子写入 CSV
4. 更新进度（成功/失败标记、行数、日期范围）
5. 生成自检报告

参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `-Category` | 是 | 类别名：sh_main/sz_main/chinext/star/sme/etf/index |
| `-Count` | 是 | 本批拉取数量 |
| `-StartFrom` | 否 | 从指定 code 开始（用于断点续跑） |
| `-KeyId` | 否 | API key ID，缺省用 `.keys.json` 的 `defaultKeyId` |
| `-DailyQuota` | 否 | 当日 Wind 调用计数提示上限，默认 `1000`；仅用于提示，不会阻止请求 |
| `-ForceReclaim` | 否 | 强制接管卡死的锁 |

### `convert_kline.ps1`（内部调用）

接收 Wind API 返回的 JSON 数据，解析后写入 CSV。由 `pull_batch.ps1` 在子进程中自动调用，一般不直接使用。

### `review_queue.ps1`

扫描 `拉取进度.json` 中 `needsManualReview=true` 的条目，输出到 `拉取进度.review_queue.json`。

### `pull_index_baostock.py`（指数补拉）

Python 脚本，通过 BaoStock 免费 API 补拉 Wind 无法覆盖的深市指数。支持：

- 内置重连逻辑（连接断开时自动 logout + login）
- 内置 rate limiting（每只间隔 1.5s，避免服务端限制）
- 输出到 `index_technicals/`，自动更新 `拉取进度.json`

```bash
# 拉取全部待补拉指数
python pull_index_baostock.py

# 拉取指定数量
python pull_index_baostock.py 50
```

### 其他脚本

阶段 1 遗留的三个修复脚本（`fix_progress_top.ps1`、`fix_progress_totals.ps1`、`patch_csv_code.ps1`）已归档至 `_archive/`，不再需要。

---

## Quickstart

### 场景 A：首次配置

1. 前往 [Wind AIFin 平台](https://aifinmarket.wind.com.cn/) 注册账号并获取 API key。安装 Wind MCP Skill 到以下固定路径：

   ```text
   <项目根目录>\.agents\skills\wind-mcp-skill\
   ```

   `pull_batch.ps1` 需要在该目录下找到 `scripts\cli.mjs`；`.agents/` 被 Git 忽略，因此需要在每台使用设备上单独安装。

2. 创建本地 key 配置：

```powershell
Copy-Item .keys.json.sample .keys.json
notepad .keys.json
```

将 `value` 替换为真实 API key；`.keys.json` 已被 Git 忽略，不要提交到仓库。

3. （首次使用）先运行一次主脚本。若 `拉取进度.json` 不存在，脚本会自动从 `lists/stock_list.csv` 初始化；也可参考 `拉取进度.json.sample` 了解结构。

4. 确认股票列表存在：

```powershell
Get-Content .\lists\stock_list.csv | Select-Object -First 3
# 应输出：category,symbol  /  chinext,300001.SZ  /  chinext,300002.SZ
```

5. 测试单只拉取：

```powershell
.\pull_batch.ps1 -Category sh_main -Count 1
```

### 场景 B：日常批量拉取

```powershell
# 拉取 300 只创业板股票
.\pull_batch.ps1 -Category chinext -Count 300

# 拉取 300 只沪市主板
.\pull_batch.ps1 -Category sh_main -Count 300

# 单批失败后重跑（同一命令，自动跳过已完成条目）
.\pull_batch.ps1 -Category chinext -Count 200
```

### 场景 C：换 API key

`拉取进度.json` 结构无需改动，只需编辑 `.keys.json` 的 `value` 字段：

```json
{"version":"1.0","defaultKeyId":"main","keys":[{"id":"main","value":"your-new-api-key","note":"主 key"}]}
```

换完直接运行拉取命令即可。

### 场景 D：处理异常条目

```powershell
# 1. 生成审核队列
.\review_queue.ps1

# 2. 查看审核结果
Get-Content ".\拉取进度.review_queue.json" -Encoding UTF8

# 3. 释放卡死的锁（-ForceReclaim）
.\pull_batch.ps1 -Category chinext -Count 100 -ForceReclaim
```

如果某只股票被标记为 `abandoned` 需要恢复，编辑 `拉取进度.json`，将该条目 `status` 从 `"abandoned"` 改为 `"pending"`。

### 场景 E：查看进度与汇总

```powershell
# 统计各类别 success / pending / abandoned
node -e "const d=require('./拉取进度.json');const s=Object.values(d.stocks);const cat=s=>s.reduce((a,x)=>{const c=x.category;a[c]=a[c]||{t:0,ok:0,pend:0,abn:0};a[c].t++;if(x.status==='success')a[c].ok++;if(x.status==='pending')a[c].pend++;if(x.status==='abandoned')a[c].abn++;return a},{});const r=cat(s);Object.keys(r).forEach(k=>console.log(k+': total='+r[k].t+' success='+r[k].ok+' pending='+r[k].pend+' abandoned='+r[k].abn))"
```

### 场景 F：多设备同步

```powershell
# 在源设备上确认最新进度
# 将整个项目目录复制到目标设备
# 注意：拉取进度.json 中的 updatedBy 字段会标记来源设备名
```

### 场景 G：备份与恢复

批拉取运行前自动备份进度文件到 `_backup/progress/`。手动恢复：

```powershell
# 恢复指定备份
Copy-Item ".\_backup\progress\拉取进度.json.bak_pre_batch_*.json" ".\拉取进度.json"
```

### 场景 H：深市指数补拉（BaoStock）

先完成场景 A，并至少运行一次 `pull_batch.ps1` 生成 `拉取进度.json`。Wind 批量拉取结束后，Wind 无法覆盖的深市指数（399106+ 等）由 BaoStock 补拉。BaoStock 脚本还会读取 `.keys.json` 的设备/Key 标识，因此每台设备都需要先创建该文件：

```bash
# 拉取全部待补拉指数
python pull_index_baostock.py

# 拉取指定数量
python pull_index_baostock.py 50
```

---

## 进度追踪

### `拉取进度.json` v1.3

每条股票记录包含 19 个字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `code` | key | `<exchange>.<symbol>`，如 `sh.600519` |
| `category` | string | 所属类别 |
| `status` | string | `pending` / `claimed` / `in_progress` / `success` / `failed` / `abandoned` |
| `failCount` | int | 连续失败次数 |
| `rows` | int | CSV 行数（成功拉取后填入） |
| `file` | string | CSV 相对路径 |
| `windCode` | string | Wind 代码格式，如 `600519.SH` |
| `server` | string | 数据来源：Wind 服务端名称 / `baostock` |
| `updatedBy` | string | `<设备名>:<keyId>` |
| `updatedAt` | datetime | 最后更新时间 |
| `error` | string | 错误信息 |
| `firstDate` | string | CSV 首条数据日期 |
| `lastDate` | string | CSV 末条数据日期 |
| `leaseUntil` | datetime | 锁过期时间 |
| `heartbeatAt` | datetime | 最后心跳时间 |
| `claimedAt` | datetime | 锁定时间 |
| `claimedBy` | string | 锁定者 |
| `historyStatus` | string | 分级：`normal` / `short_history` / `no_data_candidate` / `failed` |
| `historyReason` | string | 分级原因 |
| `needsManualReview` | bool | 是否需要人工审核 |

### 状态流转

```
pending → claimed → in_progress → success （正常路径）
                                 → failed   （失败，重试）
                                 → abandoned（多次失败后人工标记）
```

### 三类分级

| 分级 | 含义 | 处理方式 |
|------|------|----------|
| `normal` | 数据正常 | 无需处理 |
| `short_history` | 上市不足 2 年 | 经第三方数据源交叉验证后，标记 `needsManualReview=false` 确认通过 |
| `no_data_candidate` | 上市后无日 K 数据 | 人工确认是否为退市/停牌 |

---

## 维护操作

### 磁盘空间

每只股票 CSV 约 280-300 KB。拉取前脚本会自动估算总空间并校验可用空间（低于 3 GB 报警）。

### 临时文件清理

`_tmp/` 目录下的 `temp_call.js` 由拉取脚本自动生成和清理。如遇异常退出导致残留，可手动删除。

### 日志

运行日志按日期写入 `batch_log/`，格式为 `yyyyMMdd.log`。

### 备份策略

- 每次批拉取前自动备份进度文件到 `_backup/progress/`
- 脚本版本更新时手动备份到 `_backup/scripts/`

---

## 常见问题

### API 配额耗尽

表现：连续多只返回 `isError:true, status:1, stderr:""`（无论哪个类别）。

解决：在 `.keys.json` 中换一个有效 key，重新运行。

### 断连后 in_progress 条目卡死

启动时脚本会自动提示存在卡死的锁，但不会自动回收。使用 `-ForceReclaim` 参数手动接管：

```powershell
.\pull_batch.ps1 -Category chinext -Count 300 -ForceReclaim
```

### abandoned 条目恢复

编辑 `拉取进度.json`，将该条目的 `status` 改为 `"pending"`、`failCount` 归零，重新拉取。

### PowerShell 5.1 兼容性

- 中文路径比较：用 `[System.IO.File]::Exists()` 替代 `Test-Path`
- 读文件：用 `[System.IO.File]::ReadAllText(..., [Text.Encoding]::UTF8)` 替代 `Get-Content`
- 写文件：用 `[System.IO.File]::WriteAllText(...)` 替代 `Out-File`
- `.ps1` 含 CJK 默认参数：必须保存为 UTF-8 with BOM，否则 PS 5.1 按 GBK 解析中文

### 多设备同步注意事项

- 不要在同步前在另一台设备上拉取
- `updatedBy` 字段自动标记设备名和 keyId，可用于追溯来源

### BaoStock 连接断开 (WinError 10054)

表现：指数补拉过程中报 `远程主机强迫关闭了一个现有的连接`，后续查询全部失败。

原因：BaoStock 服务端对单连接有请求次数限制（约 80-100 次后断连）。

解决：`pull_index_baostock.py` 已内置重连逻辑（自动 logout + login + 1.5s delay），无需手动处理。如仍频繁断连，可适当增大脚本中的 `time.sleep` 间隔。

### 深市指数 Wind 拉取返回空

表现：`get_index_kline` 对 399106+ 系列深市指数返回空数据。

原因：Wind API 对部分深市指数覆盖不全，属 Wind 端限制。

解决：改用 `python pull_index_baostock.py` 通过 BaoStock 补拉，输出到 `index_technicals/`。

### Sina Finance 对新上市 ETF 早期数据覆盖不全

表现：第三方验证时发现 Sina 返回的首日晚于实际上市日期（如 sh.516370 Sina 首日 2026/4/3，实际首日 2026/3/25）。

原因：Sina Finance 对新上市 ETF 的早期交易数据存在缺失，属第三方源缺陷。

解决：以 Wind / BaoStock 数据为准，Sina 仅作参考验证源。如遇此类差异，可交叉验证 yfinance 等其他数据源确认。
