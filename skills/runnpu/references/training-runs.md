# 训练类负载的平台侧事实（RunNPU / 昇腾）

> 训练**方法论**（跑通链路的纪律、看曲线诊断、自动超参研究、长程与并行）不在本文件——
> 见 `training-research` skill（训练模式会话里可用）。本文件只放**换个平台就作废**的事实：
> 这个平台怎么传文件、这套镜像有什么炸点、这个集群实测过什么。

## 1. 工程进集群（本平台的通道）

- **先起一个带 SSH 的训练环境**。SSH 与安全级、与 root **无关**（helper 是注入的原生二进制，
  PID 1 非 root 时保持当前身份；run-npu#595 起 restricted 也支持，旧版 operator 才会以
  `SshRootInitUnavailable` 拒绝）——`restricted` 下照样能开，**不要为了拿 SSH 把负载降到 baseline**。
  SSH 会话身份继承容器主进程，传上去的文件属主与容器内进程一致。
  root 镜像在 restricted 下要 `--run-as-uid`，那是安全级自身的要求，别和 SSH 绑一起。
- ⚠️ **torch-npu 官方镜像做 training-env 必须带 `--arg sleep --arg infinity`**（平台已知问题：
  该镜像 entrypoint 无命令时空参立退，PID 1 数秒退出 → 容器每 1-2 分钟重启，SSH 只在残存窗口
  时好时坏，极易误判成网络/平台故障）。用 args、**不要用 `--command`**——保留 entrypoint 的
  CANN 环境装配，SSH helper 的 env 快照才有内容。training-job 有真实训练命令，不受此影响。
- 手工上传路径（无 `training_upload` 工具时，如算力管理模式）：连接参数**别自己拼**——
  `runnpu workload endpoints <p>/<n>` 给出拼好的命令，结构化值（脚本用）在
  `runnpu workload get <p>/<n> -o json` 的 `.ssh.{username,host,port}`。登录用户名固定是
  `<负载名>.<命名空间>`（SSHPiper 路由标识；注意命名空间带 `proj-` 前缀，不是项目 slug 本身，
  更不是平台用户名），如 `scp -P 32222 -r ./工程 job1.proj-main@<入口IP>:/workspace/`；
  平台 SFTP 已验证可用。能力边界：exec / 交互 shell / sftp / 本地转发 `-L`/`-D` 都支持，
  **远端监听 `-R` 未实现**。
- 备选 exec 管道（无 SSH 时）：`tar czf - . | runnpu workload exec <p>/<n>` 里接
  `tar xzf - -C /workspace`（stdin 必须以 `exit` 结尾）；只传代码，数据集级流量不过控制面。
- 数据集进数据卷 / 工作盘（`--mount` / `--workspace-gib`），一次落盘、代码单独同步。

## 2. 容器内运行（本部署实测）

- 依赖安装走平台注入的 pip 镜像（负载 env 里已有）；装 opencv 报 libGL 缺失 →
  改 `opencv-python-headless`，不要 apt 补一堆图形库。
- **pip 装到 `--target /workspace/pylibs`** 并 `export PYTHONPATH=/workspace/pylibs`：
  容器层随重启丢失，/workspace 工作盘持久——否则重启一次就要重装一遍。
- 本集群到 PyPI 的出口带宽实测只有几十 KiB/s：大依赖预置进数据卷/工作盘。
- 平台日志通道：`runnpu workload logs <p>/<n> --tail`（监控双信号源里的信号源 B）。

## 3. 两个"看起来成功了"的假象（本平台实测踩过，2026-09-02）

- **job 秒级 completed + 跟踪平台无 run**：大概率是**覆盖了镜像 entrypoint**
  （`--command bash -c …`）丢掉 CANN 环境装配 → torch_npu 不可用 → 设备探测降级 CPU
  秒跑完、PYTHONPATH 也可能没带上。提交 training-job 时**保留 entrypoint、用 args 传命令**
  （与 training-env 的 sleep infinity 同一个原理）；手动按模板 payload 拼 job 时，
  模板里的 `LD_LIBRARY_PATH` 救援 env 必须原样带上。正常 NPU 训练首个 step 要编译算子
  （分钟级），秒级完成先怀疑设备降级，别急着重提。
- **卡够 ≠ 调度得上**：`CardInsufficientMemory` 事件 + 有空闲卡数，通常是**分卡（vNPU）碎片化**
  ——平台外 Pod 按显存切片占卡，凑不出整卡。查逐卡占用（node metrics / overview 逐卡网格），
  必要时先停自己占整卡的 env 给 job 让路（先 job 后 env，反过来 env 会把唯一整卡占住）。

## 4. 昇腾特有炸点（详见 troubleshooting.md「镜像兼容性」）

- 官方 torch-npu 镜像的 LD 冲突：预置模板已带救援 `LD_LIBRARY_PATH`，自拼镜像时照抄那条 env。
- CUDA 工程迁移三件套：`import torch, torch_npu` + `from torch_npu.contrib import transfer_to_npu`
  必须在训练框架 import **之前**；AMP 自检会探 CUDA，训练参数要显式关掉（如 ultralytics `amp=False`）；
  dataloader `workers` 从小起步。
- 容器内 `npu-smi` 报 libruntime 错链时的前缀写法也在 troubleshooting.md。
