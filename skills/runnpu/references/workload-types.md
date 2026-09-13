# 四类负载：参数矩阵与生命周期


|      | workspace 开发环境                           | training-env 训练环境 | training-job 训练任务                                                                                              | inference 推理服务                                  |
| ---- | ---------------------------------------- | ----------------- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 形态   | 常驻交互（Sandbox）                            | 常驻交互（Sandbox）     | 跑完即止（Job / 多机 JobSet）                                                                                          | 常驻服务（Deployment）                                |
| 可抢占  | ✅（闲时可被回收）                                | ❌                 | 由优先级决定                                                                                                         | ❌                                               |
| 工具   | `--jupyter` `--code-server` `--ssh`      | 同左                | 无                                                                                                              | `--port`（对外端口）                                  |
| 专属参数 | `--idle/max-lifetime`（暂无 CLI flag，走 api） | 同左                | `--nodes` `--completions` `--parallelism` `--backoff-limit` `--active-deadline-seconds` `--ttl-after-finished` | `--port` `--replicas`（探针/伸缩/滚动策略走 `runnpu api`） |
| 终态   | stopped / failed                         | 同左                | **completed** / failed                                                                                         | 无自然终态                                           |


## 通用参数

- `--xpu N`：整卡卡数 0..8（0 = 纯 CPU）。**分卡**：`--xpu-core 1..100` + `--xpu-memory-mib M` 成对给出，
且 `--xpu` 必须为 1——**只支持单卡切分**，多卡分卡上游不支持（要多张卡就整卡申请，或建多个负载）。
只给一半会被 422 拒（服务端不猜另一半）。
- `--security restricted|baseline`：restricted 强制非 root（root 镜像必须给 `--run-as-uid`）。但注意多数昇腾官方镜像（root 运行）仍需要 baseline——那是镜像自身身份的要求，不是 SSH 的。
- `--pool`：省略取项目第一个池；`runnpu cluster get` 查池名。
- `--command` / `--arg` 可重复按序拼接：`--command bash --command -c --arg "…"`。

## training-job 细节

- 单机（`--nodes 1`，默认）：`--completions`（目标完成次数）、`--parallelism`（并行 Pod 数）可用；
- 多机（`--nodes ≥ 2`）：**没有** completions/parallelism（规模由节点数决定，传了 422）；
`--backoff-limit` 变成整组重启次数；`--active-deadline-seconds` 创建后不可变。
- `--ttl-after-finished 0` 表示完成立即删；省略 = 不自动删（完成的负载保留，占记录不占卡）。
- 进度看 `runnpu workload get`：`progress` 里 `succeeded / failed / retries_used`，多机另有 `ready_replicas`。
- 已知小残留：任务完成后被删除时，Completed Pod 可能残留在 namespace（上游 run-npu#551，无害）。

## inference 细节

- `--port [名字:]<端口>[,expose=…][,node-port=N]` 可重复（≤8）；名字是 DNS label ≤15（要拼进入口 host），省略为 `http`。
- `expose`：`clusterIP`（默认，仅集群内）/ `nodePort`（30000..32767，`node-port=` 可指定，否则集群分配）/
`loadBalancer`（需集群有 LB）/ `externalUrl`（需平台配了入口域名）。
- 推理端点一律 `access: public`——平台登录态挡不住 API 客户端，**鉴权由服务自身负责**（vLLM 加 `--api-key` 之类）。
- `--replicas N` 副本数；探针（readiness/liveness）、autoscaling、max_surge/max_unavailable 目前 CLI 不表达，
需要时 `runnpu api POST /workloads` 直接给 `service` 对象（字段见 api/openapi.yaml 的 ServiceSpecInput）。
- 状态语义：`running` = Deployment 副本就绪；工具 `ready` 是**入口观测**，nodePort 场景有已知误报
（run-npu#553：EndpointUnavailable 但端口实际可达）——以实测 `curl <节点IP>:<nodePort>` 为准。
- 服务视图字段：`runnpu workload get` 的 `service` 段有 replicas / ready_replicas / available_replicas。

## 不可修改的字段（想改 = 重建负载）

类型、项目、规格（xpu/core/memoryMiB）、数据源整段、SSH 开关、多机节点数、
batch 的 backoff/deadline、镜像与命令（可改的只有：暂停/恢复、部分运行时参数）。
用户要"改配置"时先对照这张表，别许诺做不到的事。