#!/usr/bin/env bash
# 场景：部署 vLLM 推理服务（权重在项目 PVC 里），nodePort 对外，实测端点可用。
set -euo pipefail

PROJECT=main
NAME=qwen-svc
# 权重 PVC 必须带 npu.run/project-id=<项目slug> 标签（否则挂载被拒为"不存在"）
WEIGHTS_PVC=model-weights

runnpu workload create --project "$PROJECT" --name "$NAME" --type inference \
  --image m.daocloud.io/quay.io/ascend/vllm-ascend:v0.22.1rc1 --xpu 1 --security baseline \
  --mount "pvc:/models,name=$WEIGHTS_PVC,ro" \
  --command bash --command -c \
  --arg "python -m vllm.entrypoints.openai.api_server --model /models/qwen --served-model-name qwen --port 8000" \
  --port http:8000,expose=nodePort --replicas 1 --wait

# nodePort 在工具观测里；ready 可能误报 false（run-npu#553），以实测为准
NP=$(runnpu workload get "$PROJECT/$NAME" | python3 -c '
import json,sys
for t in json.load(sys.stdin)["summary"].get("tools") or []:
    if t.get("node_port"): print(t["node_port"]); break')
NODE_IP=$(runnpu node list | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["ip"])' 2>/dev/null || echo "<节点IP>")
echo "端点：http://$NODE_IP:$NP/v1"
curl -s --max-time 10 "http://$NODE_IP:$NP/v1/models" | head -c 300 || echo "（模型加载中，稍后重试）"
