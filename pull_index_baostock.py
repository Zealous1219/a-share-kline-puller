import baostock as bs, json, os, sys, time
from datetime import datetime, timezone

PROGRESS_FILE = "D:/data/拉取进度.json"
OUTPUT_DIR = "D:/data/index_technicals"
KEY_FILE = "D:/data/.keys.json"
MAX_COUNT = int(sys.argv[1]) if len(sys.argv) > 1 else 0

def log(msg):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"{ts} {msg}", flush=True)

def query_with_retry(code, max_retries=5):
    for attempt in range(1, max_retries + 1):
        rs = bs.query_history_k_data_plus(
            code,
            "date,code,open,high,low,close,volume",
            start_date="1990-01-01", end_date="2026-12-31",
            frequency="d", adjustflag="2"
        )
        if rs.error_code == "0":
            return rs
        err = (rs.error_msg or "").lower()
        if any(kw in err for kw in ["connection", "closed", "10054", "timeout", "网络"]):
            log(f"  连接断开 ({rs.error_msg}), 重连中 (attempt {attempt}/{max_retries})")
            try:
                bs.logout()
            except Exception:
                pass
            time.sleep(3)
            lg = bs.login()
            if lg.error_code != "0":
                log(f"  重连失败: {lg.error_msg}")
                time.sleep(5)
                continue
            time.sleep(2)
        else:
            return rs
    return None

def main():
    # 1. 读取进度
    with open(PROGRESS_FILE, "r", encoding="utf-8") as f:
        progress = json.load(f)
    
    # 读取当前设备名
    with open(KEY_FILE, "r", encoding="utf-8") as f:
        keys = json.load(f)
    key_id = keys.get("defaultKeyId", "main")
    dev_name = os.environ.get("COMPUTERNAME", "UNKNOWN")
    
    # 2. 创建输出目录
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # 3. 找出 index 类失败/待拉的
    targets = [(k, v) for k, v in progress["stocks"].items()
               if v["category"] == "index" and v["status"] != "success"]
    if MAX_COUNT > 0:
        targets = targets[:MAX_COUNT]
    total = len(targets)
    log(f"待补拉 index: {total}")
    
    if total == 0:
        log("无需补拉")
        return
    
    # 3. 登录 baostock
    lg = bs.login()
    if lg.error_code != "0":
        log(f"BS login 失败: {lg.error_msg}")
        return
    log("BS login 成功")
    
    success = 0
    failed = 0
    skipped = 0
    now_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    
    for i, (code, info) in enumerate(targets):
        # 跳过 already done (并发安全)
        # 读取实时进度检查 (简单文本方式)
        
        wind_code = info.get("windCode", code)
        output_csv = f"{OUTPUT_DIR}/{code.replace('.', '_')}.csv"
        
        time.sleep(1.5)
        
        t0 = time.time()
        rs = query_with_retry(code)
        
        if rs is None:
            log(f"  [{i+1}/{total}] {code}: query error (after retries)")
            failed += 1
            continue
        
        rows = []
        while rs.next():
            rows.append(rs.get_row_data())
        
        if len(rows) == 0:
            log(f"  [{i+1}/{total}] {code}: 空数据")
            failed += 1
            continue
        
        # 转换 CSV: YYYY/M/D 格式, 无前导0, field order: date,code,open,high,low,close,volume
        csv_rows = []
        for r in rows:
            dt = r[0]  # YYYY-MM-DD
            # convert to YYYY/M/D
            parts = dt.split("-")
            date_fmt = f"{int(parts[0])}/{int(parts[1])}/{int(parts[2])}"
            internal_code = code
            # 跳过 OHLCV 全部为空的行
            if not r[5] or r[5].strip() == "":
                continue
            csv_rows.append(f"{date_fmt},{internal_code},{r[2]},{r[3]},{r[4]},{r[5]},{r[6]}")
        
        if len(csv_rows) == 0:
            log(f"  [{i+1}/{total}] {code}: 过滤后无有效数据")
            failed += 1
            continue
        
        # 写文件 (原子写: 先写 .tmp 再 rename)
        tmp_path = output_csv + ".tmp"
        csv_content = "date,code,open,high,low,close,volume\n" + "\n".join(csv_rows) + "\n"
        with open(tmp_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(csv_content)
        os.replace(tmp_path, output_csv)
        
        # 更新进度
        info["status"] = "success"
        info["file"] = f"index_technicals/{code.replace('.', '_')}.csv"
        info["rows"] = len(csv_rows)
        info["firstDate"] = csv_rows[0].split(",")[0]
        info["lastDate"] = csv_rows[-1].split(",")[0]
        info["updatedBy"] = f"{dev_name}:{key_id}"
        info["updatedAt"] = now_utc
        info["needsManualReview"] = False
        info["historyStatus"] = "normal"
        info["historyReason"] = None
        info["server"] = "baostock"
        
        success += 1
        elapsed = time.time() - t0
        log(f"  [{i+1}/{total}] {code}: {len(csv_rows)} rows ({elapsed:.1f}s)")
        
        # 每 20 只写一次进度
        if (i + 1) % 20 == 0 or i + 1 == total:
            with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
                json.dump(progress, f, ensure_ascii=False, indent=4)
            log(f"  进度已保存 ({success}/{total})")
    
    bs.logout()
    
    # 最终保存
    with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
        json.dump(progress, f, ensure_ascii=False, indent=4)
    
    log(f"\n=== 完成 ===")
    log(f"成功: {success}, 失败: {failed}, 跳过: {skipped}")

if __name__ == "__main__":
    t0_global = time.time()
    main()
    log(f"总耗时: {time.time()-t0_global:.0f}s")
