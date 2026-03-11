# OpenClaw Max-Compatibility Installer / OpenClaw 高兼容安装器

Universal OpenClaw installer for **Windows / WSL2 / macOS / Linux** with CN+Global presets, mirror fallback, proxy auto-detection, and check-only diagnostics.

面向 **Windows / WSL2 / macOS / Linux** 的 OpenClaw 高兼容安装方案，支持国内/海外预设、镜像回退、代理自动检测、只检查不改动模式。

---

## About (GitHub Description 推荐)

**EN**
Universal OpenClaw installer for Windows/WSL2/macOS/Linux with CN+Global profiles, proxy auto-detect, mirror fallback, and safe check-only diagnostics.

**中文**
面向 Windows/WSL2/macOS/Linux 的 OpenClaw 通用安装器，支持国内/海外预设、代理自动检测、镜像回退与安全检查模式。

---

## Supported Scenarios / 适用场景

- CN Windows users (PowerShell) / 国内 Windows 用户（PowerShell）
- CN Windows + WSL2 users (v2ray/clash/custom port) / 国内 WSL2（10808/7897/自定义）
- CN macOS users (Apple Silicon + Intel) / 国内 macOS（ARM + Intel）
- CN Linux users / 国内 Linux 用户
- Global Win/macOS/Linux users / 海外 Win/macOS/Linux 用户

---

## Scripts / 脚本

- Linux / WSL2 / macOS: `scripts/openclaw-install-optimized.sh`
- Windows PowerShell: `scripts/openclaw-install-optimized.ps1`

---

## One-line Install / 一键安装

### Linux / WSL2 / macOS

```bash
# Auto profile (recommended)
# 自动模式（推荐）
curl -fsSL https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh | bash

# China profile (CN network defaults)
# 国内网络推荐
curl -fsSL https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh | PROFILE=cn bash

# Global profile (overseas)
# 海外网络推荐
curl -fsSL https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh | PROFILE=global bash

# Check-only (no system changes)
# 仅检查，不改系统
curl -fsSL https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh | CHECK_ONLY=1 bash
```

### Windows PowerShell (Run as Administrator)

```powershell
# Download then run (recommended)
# 下载后执行（推荐）
iwr https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.ps1 -OutFile .\openclaw-install-optimized.ps1
powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile cn

# Global profile
powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile global

# Check-only
powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -CheckOnly
```

> If your shell blocks script execution, use an elevated PowerShell and keep `-ExecutionPolicy Bypass`.
> 如果系统限制脚本执行，请使用管理员 PowerShell 并保留 `-ExecutionPolicy Bypass`。

---

## Proxy Auto Detection / 代理自动检测

### WSL2

Auto probes:
- `127.0.0.1`
- Windows host IP from `/etc/resolv.conf`

Default ports:
- `10808` (common v2ray)
- `7897` (common Clash Verge)

Custom ports:

```bash
WSL_PROXY_PORT_CANDIDATES=10808,7897,8888 PROFILE=cn bash scripts/openclaw-install-optimized.sh
```

### Windows

PowerShell script tries:
1. WinHTTP proxy (`netsh winhttp show proxy`)
2. local ports (`10808,7897` by default)

---

## Mirror Strategy / 镜像策略

### npm mirrors (tested)

- Official: `https://registry.npmjs.org`
- Backup 1: `https://registry.npmmirror.com`
- Backup 2: `https://mirrors.tencent.com/npm`
- Backup 3: `https://repo.huaweicloud.com/repository/npm`

### NodeSource setup mirrors (Linux)

- Official: `https://deb.nodesource.com/setup_22.x`
- Backup: `https://mirrors.ustc.edu.cn/nodesource/deb/setup_22.x`

### Homebrew-related endpoints (macOS)

- Official install script: `https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`
- Bottle mirror option (CN): TUNA bottle domain

---

## Foreign resources used during install / 安装过程访问的海外资源

Depending on platform and selected mirror, installer may access:

- `openclaw.ai`
- `registry.npmjs.org`
- `deb.nodesource.com`
- `raw.githubusercontent.com`
- `github.com` (some npm transitive dependency fetch scenarios)

When mirrors are selected, most dependency traffic can stay on CN mirrors.

---

## Check-Only Mode / 安全检查模式

```bash
CHECK_ONLY=1 PROFILE=auto bash scripts/openclaw-install-optimized.sh
```

It reports:
- OS / proxy / Node / npm / OpenClaw
- network reachability for major endpoints
- Node fetch path sanity

---

## Post Install / 安装后

```bash
openclaw onboard --install-daemon
openclaw gateway status
openclaw models status
```

---

## Fork Auto Sync (GitHub Actions) / Fork 自动同步

Workflow file:
- `.github/workflows/sync-upstream.yml`

Use in GitHub:
1. Actions → `Sync Fork Upstream`
2. `Run workflow`
3. then cron auto-sync keeps running

---

## Security Note / 安全说明

- Repo excludes local memory/state files.
- `MEMORY.md` and `memory/` are ignored to reduce sensitive data leakage risk.

- 仓库不包含本地记忆和状态文件。
- 已忽略 `MEMORY.md` 与 `memory/`，降低敏感信息泄露风险。
