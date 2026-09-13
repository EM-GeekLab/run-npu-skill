#!/bin/sh
# runnpu CLI + Agent Skill 安装脚本（Linux / macOS；Windows 用 install.ps1）。
#   curl -fsSL https://github.com/EM-GeekLab/run-npu-skill/releases/latest/download/install.sh | sh
#   ... | sh -s -- --version v1.2.3     钉某个版本（要与你的 RunNPU 控制台版本一致）
#   ... | sh -s -- --no-skill           只装 CLI
#   ... | sh -s -- --project            Skill 装到当前目录 .claude/skills/runnpu（只对本项目生效）
#   RUNNPU_BIN_DIR=/usr/local/bin ...   改 CLI 安装位置（默认 ~/.local/bin）
# 二进制与 Skill 来自同一个 Release，版本一致；下载后按 checksums.txt 校验。
set -eu

REPO=EM-GeekLab/run-npu-skill
VERSION=""
WITH_SKILL=1
PROJECT=0
BIN_DIR="${RUNNPU_BIN_DIR:-$HOME/.local/bin}"

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --version=*) VERSION="${1#--version=}" ;;
    --no-skill) WITH_SKILL=0 ;;
    --project) PROJECT=1 ;;
    --bin-dir) BIN_DIR="$2"; shift ;;
    -h|--help) sed -n '2,9p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
  shift
done

os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$os" in
  linux|darwin) ;;
  *) echo "不支持的系统：$os（Windows 请用 install.ps1）" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "不支持的架构：$(uname -m)" >&2; exit 1 ;;
esac

if [ -z "$VERSION" ]; then
  # 跟随 /releases/latest 的重定向拿到 tag，不走 API、不受速率限制
  VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")
  VERSION=${VERSION##*/}
fi
case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
ver=${VERSION#v}
base="https://github.com/$REPO/releases/download/$VERSION"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cli="runnpu_${ver}_${os}_${arch}.tar.gz"
echo "==> 下载 $cli"
curl -fsSL -o "$tmp/$cli" "$base/$cli"
curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt"
want=$(grep " $cli\$" "$tmp/checksums.txt" | cut -d' ' -f1)
if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$tmp/$cli" | cut -d' ' -f1)
else
  got=$(shasum -a 256 "$tmp/$cli" | cut -d' ' -f1)
fi
if [ -z "$want" ] || [ "$want" != "$got" ]; then
  echo "校验失败：$cli 的 sha256 与 checksums.txt 不符" >&2; exit 1
fi
tar -xzf "$tmp/$cli" -C "$tmp" runnpu
mkdir -p "$BIN_DIR"
install -m 0755 "$tmp/runnpu" "$BIN_DIR/runnpu"
echo "CLI   → $BIN_DIR/runnpu（$("$BIN_DIR/runnpu" --version 2>/dev/null || echo "$VERSION")）"

if [ "$WITH_SKILL" = 1 ]; then
  skill="runnpu-skill_${ver}.tar.gz"
  if [ "$PROJECT" = 1 ]; then skill_dir="$PWD/.claude/skills/runnpu"; else skill_dir="$HOME/.claude/skills/runnpu"; fi
  echo "==> 下载 $skill"
  curl -fsSL -o "$tmp/$skill" "$base/$skill"
  rm -rf "$skill_dir"
  mkdir -p "$skill_dir"
  tar -xzf "$tmp/$skill" -C "$skill_dir"
  echo "Skill → $skill_dir/（SKILL.md + references/ + examples/）"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo
     echo "注意：$BIN_DIR 不在 PATH 里，Skill 会找不到 runnpu。把它加进去，例如："
     echo "  fish：     fish_add_path $BIN_DIR"
     echo "  bash/zsh： echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.profile" ;;
esac
echo
echo "接下来登录（token 存到 ~/.config/runnpu/config.yaml）："
echo "  runnpu login --server <控制台地址> -u <邮箱>"
