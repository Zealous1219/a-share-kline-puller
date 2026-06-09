# A 股日 K 数据拉取系统

基于 Wind API 的全量 A 股日 K（前复权）批量拉取工具集。覆盖沪深主板、创业板、科创板、中小板、STAR、ETF 和指数，不含退市股和北交所。

---

## 环境要求

- Windows + PowerShell 5.1
- Node.js（用于 JSON 数据处理）
- [Wind AIFin 平台](https://aifinmarket.wind.com.cn/) 账号（需开通 API 权限获取 key）

---

## 目录结构

```
D:\data\
├── pull_batch.ps1              # 主拉取脚本
├── convert_kline.ps1           # Wind JSON → CSV 转换（内部调用）
├── review_queue.ps1            # 审核队列扫描
├── fix_progress_top.ps1        # 进度文件结构修复（阶段1遗留）
├── fix_progress_totals.ps1     # 进度文件分类汇总修复（阶段1遗留）
├── patch_csv_code.ps1          # CSV code 格式修补（阶段1遗留）
├── 拉取进度.json                # 进度追踪（v1.3 schema）
├── 拉取进度.review_queue.json  # 审核队列输出
├── .keys.json                  # API key（gitignored）
├── .gitignore
├── lists/
│   └── stock_list.csv          # 源股票列表（category, symbol）
├── A-shares/                   # A 股 CSV（sh_main+sz_main+chinext+star+sme）
├── etf/                        # ETF CSV
├── index/                      # 指数 CSV
├── batch_log/                  # 每日拉取日志
├── _backup/
│   ├── baseline/               #   阶段1基线文件
│   ├── progress/               #   进度文件备份
│   └── scripts/                #   脚本历史版本
├── _tmp/                       # 临时文件（gitignored）
└── _archive/                   # 归档（旧分析脚本，gitignored）
```

---

## 数据格式规范

### CSV 文件

- 文件名：`{exchange}_{code}.csv`（小写），如 `sh_600519.csv`
- 文件内 code：`{exchange}.{code}`，如 `sh.600519`
- 字段顺序：`date, code, open, high, low, close, volume`
- 日期格式：`yyyy/M/d`（无前导零），如 `2026/6/8`
- 行序：按日期升序
- 编码：UTF-8 无 BOM
- 行尾：LF（Unix 风格）
- Volume 字段：原始数据，未做任何处理

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

批量拉取脚本，负责从 Wind API 获取日 K 数据并写入 `拉取进度.json`。每次调用按以下流程执行：

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
| `-ForceReclaim` | 否 | 强制接管卡死的锁 |

### `convert_kline.ps1`（内部调用）

接收 Wind API 返回的 JSON 数据，解析后写入 CSV。由 `pull_batch.ps1` 在子进程中自动调用，一般不直接使用。

### `review_queue.ps1`

扫描 `拉取进度.json` 中 `needsManualReview=true` 的条目，输出到 `拉取进度.review_queue.json`。

### 其他脚本

`fix_progress_top.ps1`、`fix_progress_totals.ps1`、`patch_csv_code.ps1` 为阶段 1 遗留的修补脚本，数据迁移完成后不再需要，保留作为参考。

---

## Quickstart

### 场景 A：首次配置

1. 前往 [Wind AIFin 平台](https://aifinmarket.wind.com.cn/) 注册账号并获取 API key
2. 创建本地 key 配置：

```powershell
# 编辑 D:\data\.keys.json，格式如下：
# {"version":"1.0","defaultKeyId":"main","keys":[{"id":"main","value":"ak_xxxxx","note":"主 key"}]}
```

3. 确认股票列表存在：

```powershell
Get-Content D:\data\lists\stock_list.csv | Select-Object -First 3
# 应输出：category,symbol  /  chinext,300001.SZ  /  chinext,300002.SZ
```

4. 测试单只拉取：

```powershell
& "D:\data\pull_batch.ps1" -Category sh_main -Count 1
```

### 场景 B：日常批量拉取

```powershell
# 拉取 300 只创业板股票
& "D:\data\pull_batch.ps1" -Category chinext -Count 300

# 拉取 300 只沪市主板
& "D:\data\pull_batch.ps1" -Category sh_main -Count 300

# 单批失败后重跑（同一命令，自动跳过已完成条目）
& "D:\data\pull_batch.ps1" -Category chinext -Count 200
```

### 场景 C：换 API key

`拉取进度.json` 结构无需改动，只需编辑 `.keys.json` 的 `value` 字段：

```json
{"version":"1.0","defaultKeyId":"main","keys":[{"id":"main","value":"ak_新key","note":"主 key"}]}
```

换完直接运行拉取命令即可。

### 场景 D：处理异常条目

```powershell
# 1. 生成审核队列
& "D:\data\review_queue.ps1"

# 2. 查看审核结果
Get-Content "D:\data\拉取进度.review_queue.json" -Encoding UTF8

# 3. 释放卡死的锁（-ForceReclaim）
& "D:\data\pull_batch.ps1" -Category chinext -Count 100 -ForceReclaim
```

如果某只股票被标记为 `abandoned` 需要恢复，编辑 `拉取进度.json`，将该条目 `status` 从 `"abandoned"` 改为 `"pending"`。

### 场景 E：查看进度与汇总

```powershell
# 统计各类别 success / pending / abandoned
node -e "const d=require('D:\\data\\拉取进度.json');const s=Object.values(d.stocks);const cat=s=>s.reduce((a,x)=>{const c=x.category;a[c]=a[c]||{t:0,ok:0,pend:0,abn:0};a[c].t++;if(x.status==='success')a[c].ok++;if(x.status==='pending')a[c].pend++;if(x.status==='abandoned')a[c].abn++;return a},{});const r=cat(s);Object.keys(r).forEach(k=>console.log(k+': total='+r[k].t+' success='+r[k].ok+' pending='+r[k].pend+' abandoned='+r[k].abn))"
```

### 场景 F：多设备同步

```powershell
# 在源设备上确认最新进度
# 将 D:\data\ 整个复制到目标设备的 D:\data\
# 注意：拉取进度.json 中的 updatedBy 字段会标记来源设备名
```

### 场景 G：备份与恢复

批拉取运行前自动备份进度文件到 `_backup/progress/`。手动恢复：

```powershell
# 恢复指定备份
Copy-Item "D:\data\_backup\progress\拉取进度.json.bak_pre_batch_20260608T192329Z.json" "D:\data\拉取进度.json"
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
| `server` | string | Wind 服务端名称 |
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
| `short_history` | 上市不足 2 年 | 人工确认是否可接受 |
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
& "D:\data\pull_batch.ps1" -Category chinext -Count 300 -ForceReclaim
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
