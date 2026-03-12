# OpenClaw One-Click Installer (CN + Global)

By Douhao / 作者：逗号  
Blog / 博客: https://www.youdiandou.store

---

## 你只需要这两块

## Linux / macOS / WSL2 运行什么？

```bash
curl -fsSL "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh" | PROFILE=auto bash
/usr/local/bin/openclaw onboard --install-daemon || openclaw onboard --install-daemon
openclaw --version
```

---

## Windows 运行什么？

> 建议使用**管理员 PowerShell**执行。

### PowerShell（推荐）

```powershell
curl.exe -L "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.ps1" -o .\openclaw-install-optimized.ps1
powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile auto -InstallMethod auto
openclaw onboard --install-daemon
openclaw --version
```

> 如果提示 `openclaw` 找不到，请先关闭并重新打开 PowerShell 再执行。

### CMD（备用）

```cmd
powershell -ExecutionPolicy Bypass -Command "curl.exe -L https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.ps1 -o openclaw-install-optimized.ps1 && powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile auto -InstallMethod auto"
openclaw onboard --install-daemon
openclaw --version
```

---

## 其他（需要时再看）

### 网络不稳 / GitHub 不通

1) 改用 jsDelivr：

```bash
# Linux/macOS/WSL2
curl -fsSL "https://cdn.jsdelivr.net/gh/AlexLing6er/openclaw-cn-installer@main/scripts/openclaw-install-optimized.sh" | PROFILE=auto bash
```

```powershell
# Windows
curl.exe -L "https://cdn.jsdelivr.net/gh/AlexLing6er/openclaw-cn-installer@main/scripts/openclaw-install-optimized.ps1" -o .\openclaw-install-optimized.ps1
powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile auto -InstallMethod auto
```

2) 再不行走官方：

```powershell
iwr -useb https://openclaw.ai/install.ps1 | iex
openclaw onboard --install-daemon
```

### 安装常用插件（可选）

```bash
# 飞书
openclaw plugins install @m1heng-clawd/feishu

# 企业微信
openclaw plugins install @wecom/wecom-openclaw-plugin

# 钉钉
openclaw plugins install @dingtalk-real-ai/dingtalk-connector
```

### 更新 OpenClaw（推荐）

#### Linux / macOS / WSL2
```bash
npm i -g openclaw
openclaw --version
```

#### Windows (PowerShell)
```powershell
npm i -g openclaw
openclaw --version
```

### 卸载 OpenClaw

#### Linux / macOS / WSL2
```bash
npm uninstall -g openclaw
which openclaw || echo "openclaw removed"
```

#### Windows (PowerShell)
```powershell
npm uninstall -g openclaw
where openclaw
```

### 路由逻辑（自动）
- 开代理：优先官方源
- 没代理 + 国外：优先官方源
- 没代理 + 国内：优先镜像源

### Linux 兼容补充
- 脚本会检测 CMake 版本；若低于 3.19（如 Ubuntu 20.04 常见 3.16），会尝试自动升级以避免 `node-llama-cpp` 构建失败。
- 脚本会自动安装 `git`（避免 npm 依赖拉取时 `spawn git ENOENT`）。
- 安装后会自动修正 npm prefix 的 PATH；若 shell 仍未刷新，重新登录或执行 `source ~/.bashrc`。

### 安全说明
- 脚本目标是安装 OpenClaw，不改防火墙/SSH/系统关键服务。
- 默认会执行安全清理（`CLEANUP=1`）：清理 npm 缓存 + 系统包缓存，减少磁盘占用并保持兼容性。
- 默认**不会**执行 `apt autoremove`（避免误删非本脚本安装的软件/内核）。如需启用，设置 `CLEANUP_AUTOREMOVE=1`。
- 如需关闭清理：设置 `CLEANUP=0`。
- 如果只想先看不改动（Linux/macOS/WSL2）：

```bash
curl -fsSL "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh" | CHECK_ONLY=1 PROFILE=auto bash
```
