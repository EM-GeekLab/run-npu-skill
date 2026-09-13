---
name: runnpu
description: 通过 runnpu CLI 操作 RunNPU 昇腾算力平台——查看总览 / 节点 / 集群，管理项目、配额与成员，创建、排查、删除四类工作负载（开发环境、训练环境、训练任务、推理服务），使用工作负载模板与资产，挂载数据源与数据卷，读日志、事件、指标与 YAML，管理用户 / Access Key / 系统设置 / 审计。凡是用户要"在 RunNPU 上做某事"或询问平台 / 集群 / 负载现状时使用。
---

# RunNPU CLI Skill

RunNPU 是面向昇腾 NPU 的算力管理平台。本 Skill 通过 `runnpu` 命令行完成一切操作——**不要自己拼 HTTP 请求**，
CLI 已经封装了认证、错误格式和输出格式；未封装的端点用 `runnpu api <METHOD> <路径>`。

深入主题按需读同目录文件：`references/workload-types.md`（四类负载全参数）、
`references/templates-assets.md`（模板与资产的全部命令 + `--from-template` 的合并规则）、
`references/data-sources.md`(挂载与数据卷)、`references/troubleshooting.md`（排查树 + 已知集群行为）、
`references/training-runs.md`（**用户丢来训练工程说「帮我跑起来」时必读**：工程搬运、密钥注入、
后台运行、loss 监控与收敛判断、CUDA→NPU 迁移炸点）、
`references/admin.md`（项目 / 配额 / 用户管理）。`examples/` 里是可直接照抄的完整场景。

## 前置：确认 CLI 可用与已登录

```bash
runnpu status            # 平台版本、是否初始化、集群连通
runnpu me                # 当前身份与有效权限（决定能做什么）
```

- `runnpu` 不存在（command not found）时先装，Linux / macOS 一行：
  `curl -fsSL https://github.com/EM-GeekLab/run-npu-skill/releases/latest/download/install.sh | sh -s -- --no-skill`
  （Windows：`irm https://github.com/EM-GeekLab/run-npu-skill/releases/latest/download/install.ps1 | iex`）。
  离线环境到不了 GitHub，问用户要控制台提供的安装包。CLI 与本 Skill 同版本发布，
  `runnpu --version` 应与本文件末尾的版本注释一致，不一致时去掉 `--no-skill` 重装一次把两者对齐。

- 未登录时报 `unauthenticated`。二选一：交互式 `runnpu login --server <URL> -u <email>`；
  非交互设 `RUNNPU_SERVER` + `RUNNPU_TOKEN`（管理员在「个人设置 → 访问密钥」签发）。
- **绝不要**把密码或 token 写进命令行参数回显给用户，也不要写入任何文件。

## 输出约定（对解析很重要）

- 非终端（被程序调用）下所有命令输出 **JSON**；给人看表格加 `-o table`。
- 错误走 **stderr**：`{"error":"<code>","status":<http>,"message":"…","details":[…]}`，退出码 1；参数错误 2。
  常见 code：`unauthenticated` / `forbidden` / `not_found` / `validation_failed`（看 `details` 字段级原因）/ `cluster_error`。
- 列表响应 `{"items":[…]}`，分页 `next_cursor` / `total`；**默认只取一页**（`--limit N`，默认 50），
  回答"有多少 / 全部"先加 `--all`（自动翻页），否则按 `total` 说明只看了一页。
- 时间 RFC3339；容量单位在字段名里（`_gib` / `_bytes` / `_millis`）。

## 核心概念（回答问题前先对好口径）

- **项目**是唯一组织层（没有部门）。配额、成员、策略都挂项目上。
- **负载类型（四类都可用）**：`workspace`（开发环境，可抢占）/ `training-env`（训练环境，不可抢占）/
  `training-job`（训练任务，跑完即止，可多机）/ `inference`（推理服务，Deployment + 端口）。
  开发/训练环境的区分轴是**可抢占性**，不是单机多机。
- **配额单位是卡（张数）**：`guaranteed` 保底张数、`limit` 额外可借张数。集群内部记账用核当量
  （100 核 = 1 卡），分卡负载按份额扣（25 核 = 0.25 卡）；`cards_equivalent_used` 是实际占用卡当量。
- **分卡（vNPU）**：`--xpu 1 --xpu-core C --xpu-memory-mib M` = 单张卡切 C%（1..100）算力 + M MiB 显存。只支持单卡切分：`--xpu` 必须为 1（多卡请按整卡申请）。
  两个字段必须成对；整卡就都不给。创建后不可改规格。
- **负载状态**：`submitting → pending/queued → admitted → running`；终态 `completed / stopped / failed / rejected`；
  `cleanup_blocked` / 长期 Terminating 见 troubleshooting（已知上游问题，**不要反复删**）。
- 指标为 `null` 或 `metrics.available=false` = **数据源未接入**（不是 0），转述时说"未接入"，原因在 `metrics.reason`。

## 创建负载前：先查模板与资产

用户要创建负载时，**第一步是查模板，不是从零拼参数**——模板是平台/管理员存好的整张创建表单，
往往带着踩过坑才知道的预设（如昇腾官方镜像必需的 LD_LIBRARY_PATH 覆写、就绪探针延迟）：

```bash
runnpu template list --type training-env      # ★ 开头的是系统预置；-q 按名称/描述/镜像搜
runnpu template get <名称>                     # 看 payload 里都预设了什么
runnpu asset list --kind environment          # 资产：environment / compute / data-source / credential
```

**有匹配的模板就用 `--from-template`，不要自己读 payload 再手拼参数**：

```bash
runnpu workload create --project main --name nb6 --from-template <名称> --xpu 2 --wait
```

- 合并规则由 CLI 保证：模板 payload 作基底，**只有你在命令行上显式写了的字段才覆盖它**
  （`--xpu 0`、`--jupyter=false` 这种「显式的零值」也算数）；`--mount` 与模板预设的数据源取并集，
  挂载点冲突会直接报错。**模板里的 env / 探针等预设不会丢**——那正是模板存在的理由。
- 模板类型不可覆盖：`--type` 与模板类型不一致会报错，换模板而不是改类型。
- 模板标记的 `pending_fields`（待填字段）要问用户，别编；提交后服务端 422 会把缺的字段指出来。
- 如果 CLI 报「模板里有本版本不认识的字段」，说明服务端比 CLI 新——升级 CLI，
  或退回 `runnpu api POST /workloads -d '<payload + project_id + name>'`。
- **资产是单个配置段的值拷贝**：environment（镜像+env）/ compute（池+卡数）按段并入；
  credential / data-source 资产在挂载里按名引用（如 `--mount s3:...,credential=<资产名>`）。
- 列表为空或确实不匹配再手拼参数；用户自带全量参数时以用户为准，但提一句「有现成模板 X」。

## 常用流程

**用户给了一个训练工程（文件夹/仓库）要「跑起来」** → 先读 `references/training-runs.md`
再动手（搬运方式、密钥注入、后台运行、loss 监控的判断经验都在那）。

### 看现状

```bash
runnpu overview                      # KPI、项目资源分布、存储池、排队/闲置负载
runnpu node list / runnpu node get 910b2       # 物理卡健康与占用，逐卡到负载
runnpu cluster get                   # 组件健康（Operator/Kueue/HAMi/Prometheus…）、算力池、存储池
runnpu workload list [--project X] [--type training-job] [--status running] [--all]
runnpu workload list --deleted       # 删除历史（谁删的、何时）
```

### 创建开发环境并拿到入口

```bash
runnpu workload create --project main --name nb5 --type workspace \
  --image m.daocloud.io/quay.io/ascend/vllm-ascend:v0.22.1rc1 \
  --xpu 1 --security baseline --jupyter --workspace-pool shared-cephfs --workspace-gib 50 --wait
runnpu workload get main/nb5         # tools[].url 是 Jupyter 地址（平台登录态直达，无需 token）
```

- `--wait` 阻塞到 `running / failed / rejected`（最多 10 分钟；**大镜像首次拉取可能超过它**，超时后用
  `runnpu workload get` 继续看，不代表失败）。
- 受管工作盘（`--workspace-*`）非 root 也可写（平台以 GID 20000 + ACL 初始化卷根）。
- SSH：加 `--ssh`（注入用户已登记公钥）即可，**与安全级无关**——restricted / baseline 都支持
  （run-npu#595 起放行；旧版 operator 才会以 `SshRootInitUnavailable` 拒绝 restricted+SSH）。
  SSH 登录后的身份 = 容器主进程的身份（restricted 下就是你 `--run-as-uid` 指定的非 root 用户）。
  连接命令用 `runnpu workload endpoints` 拿：
  登录用户名是 `<负载名>.<命名空间>`（SSHPiper 路由标识，API `ssh.username`），不是平台用户名。
- restricted 下 root 镜像要 `--run-as-uid`（安全级本身的要求，与 SSH 无关）。
- `runnpu workload exec main/nb5` 连入终端（交互式；管道喂 stdin 必须以 `exit` 结尾）。

### 训练任务（跑完即止）

```bash
runnpu workload create --project main --name job1 --type training-job --image img:tag --xpu 2 \
  --command bash --command -c --arg "python train.py" \
  --backoff-limit 2 --active-deadline-seconds 7200 --ttl-after-finished 86400 --wait
# 多机：--nodes N（N ≥ 2，没有中间值）；多机没有 --completions/--parallelism（规模由节点数决定）
runnpu workload get main/job1        # status=completed 后 batch 进度在 progress 里（succeeded/failed/retries）
```

### 推理服务（部署完记得给用户访问地址，见下一节）

```bash
runnpu workload create --project main --name svc1 --type inference \
  --image m.daocloud.io/quay.io/ascend/vllm-ascend:v0.22.1rc1 --xpu 1 --security baseline \
  --command bash --command -c \
  --arg "python -m vllm.entrypoints.openai.api_server --model /models/qwen --served-model-name qwen --port 8000" \
  --mount pvc:/models,name=model-weights,ro \
  --port http:8000,expose=nodePort --replicas 1 --wait
runnpu workload get main/svc1        # 工具行显示 nodePort=3xxxx；访问 http://<任一节点IP>:<nodePort>
```

三个必须想清楚的点：

1. **不给 `--port` 的推理服务不对外，等于白建**。`expose=clusterIP` 只在集群内可达；对外用 `nodePort`。
2. **模型权重从哪来是真正的卡点**：镜像里没有权重。挂 PVC / NFS / 数据卷进来，或问用户有没有内网镜像源——
   私有化环境**别默认能连 HuggingFace**。用户说"部署一个 X 模型"时先问权重来源，这比拼命令重要。
3. **`ready=false (EndpointUnavailable)` 不代表不可达**（已知上游观测缺陷 run-npu#553）：`node_port` 已分配、
   Pod Running 时端口通常已可用，用 `curl http://<节点IP>:<nodePort>/` 实测判断，别等 ready 翻真。

### 部署完了怎么访问（用户问得最多的下一个问题）

```bash
runnpu workload endpoints main/svc1     # 一条命令给出所有入口 + 现在能不能用
```

三条路径，按可用性排：

1. **泛域名入口**（`--jupyter` / `--code-server` / `--port …,expose=externalUrl`）：`url` 非空即可点，
   平台登录态直达，不用再输 token；
2. **NodePort**（`--port name:端口,expose=nodePort`）：`endpoints` 会给出 `http://<节点地址>:<端口>` 直接访问。
   ⚠️ **`workload get` 里这条的 `ready` 会长期是 false**——Operator 只认节点 ExternalIP，私有化集群没有
   （上游 run-npu#553）。端口是真的通的，**别因为 ready=false 就告诉用户"没起来"**，以 `endpoints` 的判断为准；
3. **端口转发**（前两条都没有时的兜底，不依赖任何集群地址）：

   ```bash
   runnpu workload port-forward main/svc1 8000:8000   # 然后访问 http://127.0.0.1:8000
   runnpu workload port-forward main/nb5 2222:2222    # 转发 SSH 端口，本地再 ssh 进去
   ```

   它走控制面板的 WebSocket 隧道，只要 CLI 能连上平台就能用；Ctrl-C 结束。

`workload create --wait` 成功后会自动打印可用地址，不用再问一遍。

### 挂载数据（速查；细节与易错点见 references/data-sources.md）

```bash
--mount pvc:/models,name=weights,ro          # ⚠️ PVC 必须带 npu.run/project-id=<项目slug> 标签，否则报"不存在"
--mount datavolume:/data,name=<集群卷名>,ro   # 跨项目必须 ro；集群卷名用 runnpu datavolume list 查
--mount newvolume:/out,pool=shared-cephfs,size=20Gi[,persistency=project]
--mount nfs:/data,server=10.0.0.1,path=/export/ds
--mount emptydir:/scratch,size=1Gi
```

**数据源整段创建后不可修改**。用户说"再挂一个盘"= 重建负载，不是找修改命令。

### 排查一个负载（完整决策树见 references/troubleshooting.md）

```bash
runnpu workload get main/nb5          # 状态、reason.text、Pods、工具入口
runnpu workload events main/nb5       # 调度/准入/运行时事件
runnpu workload logs main/nb5 --tail 200      # -f 跟随
runnpu workload yaml main/nb5         # 实际 CR 含 status
```

顺序：`status`+`reason.text` → `events` → `logs`。`queued` 看项目配额；`admitted` 不 `running` 看事件里的
镜像拉取/调度；**容器 CrashLoop 且日志有 `symbol lookup error`** → 镜像 LD 与平台注入不兼容，
见 troubleshooting 的「镜像兼容性」一节（有一行 env 的救援配方）。

### 停止 / 删除

```bash
runnpu workload stop|start main/nb5
runnpu workload delete main/nb5 --yes      # 破坏性：先向用户确认
```

删除后负载可能停留 Terminating 数分钟乃至更久（上游 run-npu#549：带工具 Service / 受管卷的负载
teardown 卡住）——**不要反复删、不要 --force 循环**，如实告知用户需等待或运维介入。

### 项目与配额（管理员；全量见 references/admin.md）

```bash
runnpu project create --slug asr --name 语音识别 --pool ascend910b4 --guaranteed 4 --limit 4 \
  --storage-pool shared-cephfs --storage-gib 200
runnpu project quota get asr
runnpu project quota set asr --pool ascend910b4=8,4 --storage-pool shared-cephfs=500   # 整份替换语义！先 get 再 set
```

单位是**卡**。⚠️ 建项目后配额落到集群有秒级延迟且可能失败（集群配额被占满时被拒）：
建完项目**先 `runnpu project quota get <slug>` 确认 `cluster` 段有数据**再建负载，
否则负载可能拿到**终态** `rejected / QuotaGrantNotFound`（不会自愈，要删掉重建）。

## 行为准则

1. 只读命令直接执行；**创建/停止/删除/改配额/改成员/禁用用户先复述参数并取得用户确认**，
   删除、移除、吊销类必须用户明确同意后才加 `--yes`。一次性凭据（初始密码、token 明文）只转给用户，不复述到其它地方。
2. 引用负载一律 `<project-slug>/<name>`；项目可用 slug 或 ID。
3. 用户点名的东西（模型名/镜像 tag/池名）**可能不存在**：能核对的核对（池用 `runnpu cluster get`），
   核对不了的明说无法确认、要用户拍板，**绝不静默替换**。
4. 不猜状态含义：以 `status`、`reason.text`、`events` 为准；`metrics.available=false` 按"未接入"转述。
5. 结果给出用户能直接用的关键字段（名字、状态、入口 URL / nodePort、原因）；数字带单位与口径（卡 / 卡当量 / GiB）。

<!-- runnpu-skill v0.1.1：与 runnpu CLI 同版本发布，`runnpu --version` 应一致 -->
