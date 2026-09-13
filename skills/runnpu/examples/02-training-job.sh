#!/usr/bin/env bash
# 场景：提交一个单机训练任务，带重试与超时，完成后自动清理；轮询到终态并交付结果。
set -euo pipefail

PROJECT=main
NAME=train-demo

runnpu workload create --project "$PROJECT" --name "$NAME" --type training-job \
  --image m.daocloud.io/quay.io/ascend/vllm-ascend:v0.22.1rc1 --xpu 1 --security baseline \
  --mount datavolume:/data,name=dv-main-trainset,ro \
  --mount newvolume:/output,pool=shared-cephfs,size=20Gi,persistency=project \
  --command bash --command -c --arg "python /data/train.py --out /output" \
  --backoff-limit 2 --active-deadline-seconds 7200 --ttl-after-finished 86400

# 训练可能超过 --wait 的 10 分钟上限，所以自己轮询
while :; do
  st=$(runnpu workload get "$PROJECT/$NAME" | python3 -c 'import json,sys; print(json.load(sys.stdin)["summary"]["status"])')
  case "$st" in completed|failed|rejected|stopped) break;; esac
  sleep 30
done
echo "终态：$st"
runnpu workload get "$PROJECT/$NAME" | python3 -c '
import json,sys; d=json.load(sys.stdin)
p=d.get("progress") or {}
print("succeeded:",p.get("succeeded"),"failed:",p.get("failed"),"retries:",p.get("retries_used"))'
[ "$st" = failed ] && runnpu workload logs "$PROJECT/$NAME" --tail 100
