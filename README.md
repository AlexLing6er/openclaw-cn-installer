# OpenClaw One-Click Installer (CN + Global)

By Douhao / 作者：逗号  
Blog / 博客: https://www.youdiandou.store

---

## 你只需要这两块

## Linux / macOS / WSL2 运行什么？

```bash
curl -fsSL "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh" | PROFILE=auto bash
openclaw onboard --install-daemon
```

---

## Windows 运行什么？

### PowerShell（推荐）

```powershell
curl.exe -L "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.ps1" -o .\openclaw-install-optimized.ps1
powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile auto -InstallMethod auto
openclaw onboard --install-daemon
```

### CMD（备用）

```cmd
powershell -ExecutionPolicy Bypass -Command "curl.exe -L https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.ps1 -o openclaw-install-optimized.ps1 && powershell -ExecutionPolicy Bypass -File .\openclaw-install-optimized.ps1 -Profile auto -InstallMethod auto"
openclaw onboard --install-daemon
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

### 路由逻辑（自动）
- 开代理：优先官方源
- 没代理 + 国外：优先官方源
- 没代理 + 国内：优先镜像源

### 安全说明
- 脚本目标是安装 OpenClaw，不改防火墙/SSH/系统关键服务。
- 如果只想先看不改动（Linux/macOS/WSL2）：

```bash
curl -fsSL "https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh" | CHECK_ONLY=1 PROFILE=auto bash
```
