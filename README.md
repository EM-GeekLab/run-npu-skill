# run-npu-skill

[RunNPU](https://github.com/EM-GeekLab) 昇腾算力平台的命令行 `runnpu` 与配套 Agent Skill 的**发布仓**。

- **Releases**：各平台 CLI 二进制（Linux / macOS / Windows × amd64 / arm64，Linux 为静态链接）、
  `checksums.txt`、Skill 包（`runnpu-skill_<版本>.zip`）与安装脚本。
- **main 分支**：与最新 Release 配套的 Skill（`skills/runnpu/`），供 `npx skills add` 一类工具直接安装。

> 本仓库由 `run-npu-control-panel` 的 CI 在打 tag 时自动同步，**不在这里改东西、不接受 PR**。
> 问题与建议请提到 RunNPU 的主仓库。

## 安装

Linux / macOS：

```bash
curl -fsSL https://github.com/EM-GeekLab/run-npu-skill/releases/latest/download/install.sh | sh
```

Windows（PowerShell）：

```powershell
irm https://github.com/EM-GeekLab/run-npu-skill/releases/latest/download/install.ps1 | iex
```

脚本把 CLI 装到 `~/.local/bin`（Windows：`%LOCALAPPDATA%\runnpu\bin`），Skill 装到 `~/.claude/skills/runnpu`，
并按 `checksums.txt` 校验。常用参数：`--version vX.Y.Z` 钉版本、`--no-skill` 只装 CLI、
`--project` Skill 只装进当前项目（Windows 对应 `-Version` / `-NoSkill` / `-Project`）。

只要 Skill（已有 `runnpu` 时）：

```bash
npx skills add EM-GeekLab/run-npu-skill          # 最新 Release 配套的版本
npx skills add https://github.com/EM-GeekLab/run-npu-skill/releases/download/vX.Y.Z/runnpu-skill_X.Y.Z.zip
```

ModelScope 技能中心：`modelscope skills add @<owner>/runnpu`（条目地址以技能中心页面为准）。

## 版本

**CLI、Skill 与 RunNPU 控制台按同一版本号发布。** Skill 教的参数只保证与同版本二进制一致，
二进制只保证与同版本或更新的控制台兼容；升级时三者一起换。`runnpu status` 会显示控制台版本，
`runnpu --version` 显示 CLI 版本，`skills/runnpu/SKILL.md` 末尾的注释标着 Skill 版本。

离线交付的集群到不了 GitHub：控制台自身提供与其版本一致的安装包，以那份为准。

## 登录

```bash
runnpu login --server http://console.<你的地址> -u you@example.com   # token 落 ~/.config/runnpu/config.yaml
```

或用环境变量（CI / 无状态场景）：`RUNNPU_SERVER` + `RUNNPU_TOKEN`（控制台「个人设置 → 访问密钥」签发）。
验证：`runnpu status`、`runnpu me`。
