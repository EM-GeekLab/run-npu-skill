#!/usr/bin/env bash
# 场景：给用户建一个带 Jupyter + 持久工作盘的开发环境，交付入口 URL。
set -euo pipefail

PROJECT=main
NAME=nb-demo

# 1. 建负载：1 张整卡 + 50Gi 工作盘 + Jupyter；昇腾镜像 root 运行所以 baseline
runnpu workload create --project "$PROJECT" --name "$NAME" --type workspace \
  --image m.daocloud.io/quay.io/ascend/vllm-ascend:v0.22.1rc1 \
  --xpu 1 --security baseline --jupyter \
  --workspace-pool shared-cephfs --workspace-gib 50 \
  --wait

# 2. 拿入口（tools[].url 平台登录态直达；没 url 说明还没 ready 或没权限）
runnpu workload get "$PROJECT/$NAME" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for t in d["summary"].get("tools") or []:
    print(t["name"], "ready:", t["ready"], "url:", t.get("url","-"))'

# 3.（可选）验证卡真的可用
runnpu workload exec "$PROJECT/$NAME" <<'SH'
npu-smi info | head -8
exit
SH
