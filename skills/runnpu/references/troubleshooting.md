# 排查决策树与已知集群行为

## 决策树

```
runnpu workload get <p>/<n>  → status + reason.text 先读完
│
├─ rejected            → 终态，不会自愈。reason.text 说明原因：
│   ├─ QuotaGrantNotFound   → 项目配额没落到集群（建项目太快 / 集群配额被占满）。
│   │                         runnpu project quota get <slug> 看 cluster 段；配额恢复后**删掉重建**负载
│   ├─ PersistentVolumeClaimNotFound → pvc 挂载缺 npu.run/project-id 标签（见 data-sources），或真不存在
│   ├─ QuotaResourceUnauthorized / AcceleratorPoolUnavailable → 池没在项目配额里 / 池发现不可用
│   └─ 其它 reason 原样转述，别猜
├─ queued              → 配额不够在排队：runnpu project quota get 看 used vs guaranteed（+limit 可借）
├─ pending / admitted 很久 → runnpu workload events：
│   ├─ Pulling image…       → 大镜像拉取，等；--wait 超时 ≠ 失败
│   ├─ FilteringFailed / 0 nodes fit → 卡不够或分卡份额放不下
│   └─ 无事件               → runnpu workload yaml 看 CR conditions
├─ running 但工具/端口不通 → 下面「入口就绪」
├─ CrashLoopBackOff    → runnpu workload logs：
│   ├─ symbol lookup error（libdrvdsmi/libruntime）→ 下面「镜像兼容性」
│   └─ 其它应用错误原样转述
└─ Terminating 很久    → 下面「删除卡住」
```

## 镜像兼容性（昇腾镜像 + HAMi 注入）

平台用 HAMi 软切时会向**每个进程**注入 preload 库，它要求容器的 `LD_LIBRARY_PATH` 能同时解析到
CANN `libruntime.so` 和与宿主驱动一致的 dsmi/hal 链。已知结论：

- ✅ `vllm-ascend` 镜像（平台预置列表里的）：路径顺序兼容，直接用；
- ❌ **ascendhub 官方 `torch-npu` 镜像**：烘死的 LD 路径与注入冲突，容器里 **bash 都起不来**
  （`symbol lookup error: libdrvdsmi_host.so: drvSetDeviceInfo`，CrashLoopBackOff）。
  **救援配方**（创建时加一个 env，实测 Running + npu-smi + torch_npu 全通）：

  ```
  --env "LD_LIBRARY_PATH=/usr/local/Ascend/driver/lib64/driver:/usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64:/usr/local/Ascend/ascend-toolkit/latest/lib64"
  ```

  要点：宿主驱动目录在前，镜像 toolkit 目录兜 `libruntime.so`；**只留驱动路径会缺 libruntime.so 照样炸**。
  其它镜像炸在同一错误时，同思路调整（驱动在前 + 该镜像的 CANN lib64 在后）。
- ❌ busybox/alpine 等非 glibc 镜像与注入不兼容，连通性验证用 `ubuntu:24.04`。
- 容器内 `npu-smi` 报 `libruntime.so: cannot open` 是另一回事（宿主二进制错链镜像 CANN）：
  exec 时前缀 `LD_LIBRARY_PATH=/usr/local/Ascend/driver/lib64:…/driver:…/common npu-smi info` 即可。

## 入口就绪的口径

- 工具 `url` 只在 ready 且有权限时返回；`internal_url` 是集群内地址（浏览器打不开）。
- `node_port` 是**分配观测**：不含节点地址、不代表可达、可能在 ready=false 时就有。访问 = `http://<任一节点IP>:<node_port>`。
- **nodePort 工具的 ready 有已知误报**（run-npu#553：EndpointUnavailable 但实际可达）：
  Pod Running 后直接 `curl --max-time 5 http://<节点IP>:<node_port>/` 实测，别等 ready。

## 删除卡住（run-npu#549）

带**工具 Service / 受管卷 / 项目持久卷**的负载删除后可能长期 Terminating（operator teardown 对已删对象
的 404 处理缺陷）。表现：`kubectl` 里 RunWorkload 带 deletionTimestamp 不消失、PVC 卡 Terminating。

- **不要**反复 delete、不要循环 --force；
- 如实告知用户是已知上游问题，需等待修复或运维用 finalizer 手段清理（运维操作，不在本 Skill 权限内做）；
- 项目删除因此失败时（`has_running_workloads` / 卡 Terminating）同理。

训练任务删除后残留的 Completed Pod（ownerReferences 为空）是另一个已知无害残留（run-npu#551）。

## 配额相关

- 建项目后配额（QuotaGrant）落集群有延迟且可能被拒（集群卡总量被其它项目占满时）：
  建完先 `runnpu project quota get <slug>` 确认 `cluster` 段非空再建负载。
- `queued` 时算账：单位是卡；分卡按份额折算（25 核 = 0.25 卡）；`limit` 是可借增量，借用的部分可被抢占。
- `runnpu project repair <slug> --action resync` 可触发配额重新物化（管理员）。

## 指标与日志

- `metrics.available=false` / 值为 null = 数据源未接入（Prometheus 的 NPU 指标、ClickHouse 日志可能没部署），
  说"未接入"，不是 0，原因在 `metrics.reason`。
- `runnpu workload logs` 是容器 stdout；`events` 是 K8s Event + CR 条件（最近 1 小时）。
