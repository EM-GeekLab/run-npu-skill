# runnpu CLI + Agent Skill 安装脚本（Windows PowerShell）。
#   irm https://github.com/EM-GeekLab/run-npu-skill/releases/latest/download/install.ps1 | iex
#   钉版本 / 只装 CLI / Skill 装到当前项目：先下载再带参数运行
#   .\install.ps1 -Version v1.2.3 [-NoSkill] [-Project] [-BinDir C:\tools]
# 不需要管理员权限：CLI → %LOCALAPPDATA%\runnpu\bin（并加入用户 PATH），Skill → %USERPROFILE%\.claude\skills\runnpu。
param(
  [string]$Version = "",
  [switch]$NoSkill,
  [switch]$Project,
  [string]$BinDir = ""
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = "EM-GeekLab/run-npu-skill"

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
  "AMD64" { "amd64" }
  "ARM64" { "arm64" }
  default { throw "不支持的架构：$($env:PROCESSOR_ARCHITECTURE)" }
}
if (-not $Version) {
  $Version = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest").tag_name
}
if (-not $Version.StartsWith("v")) { $Version = "v$Version" }
$ver = $Version.TrimStart("v")
$base = "https://github.com/$repo/releases/download/$Version"
if (-not $BinDir) { $BinDir = if ($env:RUNNPU_BIN_DIR) { $env:RUNNPU_BIN_DIR } else { Join-Path $env:LOCALAPPDATA "runnpu\bin" } }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("runnpu-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $cli = "runnpu_${ver}_windows_${arch}.zip"
  Write-Host "==> 下载 $cli"
  Invoke-WebRequest "$base/$cli" -OutFile (Join-Path $tmp $cli)
  Invoke-WebRequest "$base/checksums.txt" -OutFile (Join-Path $tmp "checksums.txt")
  $want = (Get-Content (Join-Path $tmp "checksums.txt") | Where-Object { $_ -match "\s$([regex]::Escape($cli))$" }) -split "\s+" | Select-Object -First 1
  $got = (Get-FileHash (Join-Path $tmp $cli) -Algorithm SHA256).Hash.ToLower()
  if (-not $want -or $want -ne $got) { throw "校验失败：$cli 的 sha256 与 checksums.txt 不符" }
  Expand-Archive (Join-Path $tmp $cli) -DestinationPath (Join-Path $tmp "cli") -Force
  New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
  Copy-Item (Join-Path $tmp "cli\runnpu.exe") (Join-Path $BinDir "runnpu.exe") -Force
  Write-Host "CLI   -> $BinDir\runnpu.exe ($Version)"

  if (-not $NoSkill) {
    $skill = "runnpu-skill_${ver}.zip"
    $skillDir = if ($Project) { Join-Path (Get-Location) ".claude\skills\runnpu" } else { Join-Path $env:USERPROFILE ".claude\skills\runnpu" }
    Write-Host "==> 下载 $skill"
    Invoke-WebRequest "$base/$skill" -OutFile (Join-Path $tmp $skill)
    if (Test-Path $skillDir) { Remove-Item $skillDir -Recurse -Force }
    Expand-Archive (Join-Path $tmp $skill) -DestinationPath $skillDir -Force
    Write-Host "Skill -> $skillDir\ (SKILL.md + references\ + examples\)"
  }

  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if (($userPath -split ";") -notcontains $BinDir) {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$BinDir", "User")
    Write-Host ""
    Write-Host "已把 $BinDir 加入用户 PATH，重新打开终端后生效。"
  }
  Write-Host ""
  Write-Host "接下来登录（token 存到 %APPDATA%\runnpu\config.yaml）："
  Write-Host "  runnpu login --server <控制台地址> -u <邮箱>"
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
