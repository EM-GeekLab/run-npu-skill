#!/usr/bin/env bash
# 场景：分卡（vNPU）——单张卡切 25% 算力 + 16GiB 显存。
# 只支持单卡切分：--xpu 必须为 1（ADR-0030 §6.3 起 CRD 不支持多卡分卡）。
set -euo pipefail

runnpu workload create --project main --name frac-demo --type workspace \
  --image m.daocloud.io/quay.io/ascend/vllm-ascend:v0.22.1rc1 --security baseline \
  --xpu 1 --xpu-core 25 --xpu-memory-mib 16384 \
  --command bash --command -c --arg "sleep infinity" --wait

# 配额按份额扣：1 × 25 核 = 0.25 卡当量
runnpu project quota get main | python3 -c '
import json,sys; d=json.load(sys.stdin)
for u in d.get("cluster",{}).get("usage",[]) or []: print(u)'
