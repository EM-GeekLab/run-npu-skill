# 训练/实验类任务经验（本地工程 → 集群跑通 → 盯指标）

用户丢来一个训练工程（文件夹/仓库）说「帮我跑起来」时的常规判断，按序：

## 0. 先读工程自述，再动平台

工程里的 README / CLAUDE.md / requirements.txt 是第一信息源——入口脚本、超参环境变量、
数据与权重是否已内置、框架适配是否做过，**工程说了的不要自己猜**。然后按 SKILL.md
「创建负载前」流程查模板（训练类通常有预置的 torch-npu 模板，LD 救援 env 已内置）。

## 1. 工程搬运（本地 → 容器）

- **首选 SSH/SFTP**：负载加 `--ssh` 即可，**与安全级无关**（run-npu#595 起 restricted 也支持；
  SSH 会话身份继承容器主进程，传上去的文件属主与容器内进程一致）。连接参数
  别自己拼——`runnpu workload endpoints <p>/<n>` 给出拼好的命令，结构化值（脚本用）在
  `runnpu workload get <p>/<n> -o json` 的 `.ssh.{username,host,port}`：登录用户名固定是
  `<负载名>.<命名空间>`（SSHPiper 路由标识，
  注意命名空间带 `proj-` 前缀，不是项目 slug 本身，更不是平台用户名），如
  `scp -P 32222 -r ./工程 job1.proj-main@<入口IP>:/workspace/`；平台 SFTP 已验证可用。
  能力边界：exec / 交互 shell / sftp / 本地转发 `-L`/`-D` 都支持，**远端监听 `-R` 未实现**。
- 备选 exec 管道（无 SSH 时）：`tar czf - . | runnpu workload exec <p>/<n>` 里接
  `tar xzf - -C /workspace`（stdin 必须以 `exit` 结尾）。
- 数据集大（GB 级）就别跟着代码反复传：数据进数据卷 / 工作盘一次，代码单独同步。

## 2. 运行

- 依赖安装走平台注入的 pip 镜像（负载 env 里已有）；装 opencv 报 libGL 缺失 →
  改 `opencv-python-headless`，不要 apt 补一堆图形库。
- **长训练必须放后台**：`nohup python train.py > train.log 2>&1 &`——exec/SSH 会话断开
  不能连累训练进程。
- **密钥注入原则**（SwanLab / W&B / S3 等）：创建负载时用 `--env KEY=...` 注入，值取自
  用户本地环境；**绝不**写进工程文件、不落盘、不在命令输出里回显。

## 3. 监控与健康判断（双信号源）

- 信号源 A：实验跟踪平台（SwanLab / W&B…）——在**本地**用同一个 key 经其 OpenAPI 拉指标
  （如 SwanLab 的 `swanlab.OpenApi` 实验指标接口），不用进容器。
- 信号源 B：`runnpu workload logs <p>/<n> --tail`——框架逐 epoch 的表格输出，A 断了用 B 兜底。
- 经验口径：loss 前几个 epoch 应明显下降；**NaN / 持续不降** → 停下检查 lr 与数据，别硬等；
  **长时间无输出** ≠ 卡死——NPU 首个 step 在编译算子，几分钟是正常的，logs 里有周期性输出即健康。
- 自动化闭环模式（用户要「自动训练」时）：起训练 → 定期拉 loss → 收敛平台期或发散则停止、
  调参（lr / epochs）、换 `RUN_NAME` 重跑一轮；每轮都要能在跟踪平台上按名字区分。

## 4. 昇腾特有炸点（详见 troubleshooting.md「镜像兼容性」）

- 官方 torch-npu 镜像的 LD 冲突：预置模板已带救援 `LD_LIBRARY_PATH`，自拼镜像时照抄那条 env。
- CUDA 工程迁移三件套：`import torch, torch_npu` + `from torch_npu.contrib import transfer_to_npu`
  必须在训练框架 import **之前**；AMP 自检会探 CUDA，训练参数要显式关掉（如 ultralytics `amp=False`）；
  dataloader `workers` 从小起步。
- 容器内 `npu-smi` 报 libruntime 错链时的前缀写法也在 troubleshooting.md。
