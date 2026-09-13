#!/usr/bin/env bash
# 场景：负载不 running，按决策树定位（只读，随便跑）。
set -euo pipefail
W=${1:?用法: 05-troubleshoot.sh <project>/<name>}

echo "== 1. 状态与原因"
runnpu workload get "$W" | python3 -c '
import json,sys; d=json.load(sys.stdin)["summary"]
print(d["status"], "-", (d.get("reason") or {}).get("text",""))'

echo "== 2. 事件（调度/准入/镜像拉取）"
runnpu workload events "$W" | python3 -c '
import json,sys
for e in json.load(sys.stdin)["items"][:10]: print(e.get("time",""), e.get("reason",""), e.get("message","")[:100])'

echo "== 3. 容器日志尾部（CrashLoop 时看 symbol lookup error → 镜像 LD 问题，见 troubleshooting.md）"
runnpu workload logs "$W" --tail 30 2>/dev/null || echo "（还没有容器日志）"
