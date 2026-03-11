# OpenClaw CN/Global Universal Installer

Universal OpenClaw installer for **WSL2 / macOS / Linux** with **CN/global profiles**, dynamic proxy detection, and safe check-only diagnostics.

面向 **WSL2 / macOS / Linux** 的 OpenClaw 通用安装脚本，支持 **国内/海外环境配置**、代理自动检测，以及只检查不改动的诊断模式。

## Features / 特性

- `PROFILE=cn|global|auto` presets / 环境预设
- WSL2 proxy auto-detect (`10808,7897`) / WSL2 代理自动探测
- macOS system proxy detection / macOS 系统代理自动读取
- `NODE_USE_ENV_PROXY=1` compatibility for Node fetch / 修复 Node 代理兼容问题
- `CHECK_ONLY=1` diagnostics mode / 只检查不安装

## Quick Start / 快速开始

```bash
# CN-friendly defaults
PROFILE=cn bash scripts/openclaw-install-optimized.sh

# Global defaults
PROFILE=global bash scripts/openclaw-install-optimized.sh

# Check only (no changes)
CHECK_ONLY=1 PROFILE=auto bash scripts/openclaw-install-optimized.sh
```

## One-line install from GitHub / GitHub 一键安装

```bash
# Auto profile (recommended for most users)
# 自动模式（大多数用户推荐）
curl -fsSL https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh | bash

# China profile (CN network defaults)
# 国内网络推荐（中国环境默认）
curl -fsSL https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh | PROFILE=cn bash

# Global profile (overseas users)
# 海外网络推荐
curl -fsSL https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh | PROFILE=global bash

# Check only (no system changes)
# 仅检查，不改系统
curl -fsSL https://raw.githubusercontent.com/AlexLing6er/openclaw-cn-installer/main/scripts/openclaw-install-optimized.sh | CHECK_ONLY=1 bash
```

## Common options / 常用参数

- `AUTO_PROXY=1|0`
- `WSL_PROXY_PORT_CANDIDATES=10808,7897`
- `FORCE_IPV4=1|0`
- `NPM_REGISTRY=https://registry.npmmirror.com`
- `USE_SUDO_NPM=1|0`
- `INSTALL_CHANNEL_PLUGINS=1|0`

## Security note / 安全说明

- This repo does **not** include local memory/state files.
- `MEMORY.md` and `memory/` are ignored by `.gitignore` to avoid sensitive data leaks.

- 仓库不包含本地记忆和状态文件。
- 已通过 `.gitignore` 忽略 `MEMORY.md` 与 `memory/`，避免敏感信息泄露。
