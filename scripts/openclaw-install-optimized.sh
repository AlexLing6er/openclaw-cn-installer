#!/usr/bin/env bash
set -Eeuo pipefail

# OpenClaw Universal Installer (WSL2 Ubuntu/Debian + macOS + Linux VPS)
# Goals:
# - one script for common environments
# - dynamic proxy detection for WSL2 + macOS
# - keep Linux VPS path simple/safe (no forced proxy magic)
# - better retries/timeouts + diagnostics

OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
FORCE_IPV4="${FORCE_IPV4:-1}"
NPM_REGISTRY="${NPM_REGISTRY:-}"
SKIP_BUILD_TOOLS="${SKIP_BUILD_TOOLS:-0}"
USE_SUDO_NPM="${USE_SUDO_NPM:-1}"
PRINT_ONLY="${PRINT_ONLY:-0}"
INSTALL_CHANNEL_PLUGINS="${INSTALL_CHANNEL_PLUGINS:-1}"
CHECK_ONLY="${CHECK_ONLY:-0}"                       # diagnostics-only, no install changes
PROFILE="${PROFILE:-auto}"                          # auto|cn|global

# New universal toggles
AUTO_PROXY="${AUTO_PROXY:-1}"                       # auto-detect proxy on WSL2/macOS
WSL_PROXY_PORT_CANDIDATES="${WSL_PROXY_PORT_CANDIDATES:-10808,7897}" # v2ray/clash verge common ports
WSL_DETECT_HOST_PROXY="${WSL_DETECT_HOST_PROXY:-1}" # probe Windows host IP from resolv.conf
MACOS_DETECT_PROXY="${MACOS_DETECT_PROXY:-1}"       # read macOS system proxy via scutil/networksetup
NODE_USE_ENV_PROXY="${NODE_USE_ENV_PROXY:-1}"       # fix Node/undici not reading proxy by default
DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

log()  { printf "\033[36m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m[ OK ]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[31m[ERR ]\033[0m %s\n" "$*"; }

OS_KIND=""
PKG_KIND=""
IS_WSL=0

usage() {
  cat <<'EOF'
Usage:
  bash openclaw-install-optimized.sh

Env options (base):
  OPENCLAW_VERSION=latest|x.y.z     (default: latest)
  FORCE_IPV4=1|0                    (default: 1)
  NPM_REGISTRY=https://...          (optional)
  SKIP_BUILD_TOOLS=1                (optional)
  USE_SUDO_NPM=1|0                  (default: 1)
  PRINT_ONLY=1                      (only print plan)
  INSTALL_CHANNEL_PLUGINS=1|0       (default: 1)
  CHECK_ONLY=1                      (diagnostics only, no install)
  PROFILE=auto|cn|global            (default: auto)

Env options (universal/proxy):
  AUTO_PROXY=1|0                    (default: 1)
  NODE_USE_ENV_PROXY=1|0            (default: 1)
  WSL_PROXY_PORT_CANDIDATES=10808,7897 (default)
  WSL_DETECT_HOST_PROXY=1|0         (default: 1)
  MACOS_DETECT_PROXY=1|0            (default: 1)

Examples:
  # China-friendly defaults
  PROFILE=cn bash openclaw-install-optimized.sh

  # Global defaults (no proxy unless already configured)
  PROFILE=global bash openclaw-install-optimized.sh

  # WSL2/macOS auto-proxy
  AUTO_PROXY=1 bash openclaw-install-optimized.sh

  # Linux VPS (usually no proxy; keep simple)
  AUTO_PROXY=0 FORCE_IPV4=1 bash openclaw-install-optimized.sh

  # Existing device health/check mode
  CHECK_ONLY=1 PROFILE=auto bash openclaw-install-optimized.sh
EOF
}

on_error() {
  local exit_code=$?
  err "Failed at line $1 (exit=${exit_code})."
  err "Diagnostics:"
  err "  - OS_KIND=${OS_KIND:-unknown}, PKG_KIND=${PKG_KIND:-unknown}, IS_WSL=${IS_WSL}"
  err "  - node=$(node -v 2>/dev/null || echo missing), npm=$(npm -v 2>/dev/null || echo missing)"
  err "  - HTTP_PROXY=${HTTP_PROXY:-${http_proxy:-<empty>}}"
  err "  - HTTPS_PROXY=${HTTPS_PROXY:-${https_proxy:-<empty>}}"
  err "Hints: AUTO_PROXY=1, FORCE_IPV4=1, set NPM_REGISTRY, or USE_SUDO_NPM=0."
  exit "$exit_code"
}
trap 'on_error ${LINENO}' ERR

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }
}

run() {
  log "$*"
  "$@"
}

have_sudo() {
  command -v sudo >/dev/null 2>&1
}

sudo_run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    run "$@"
  else
    have_sudo || { err "sudo is required for this operation"; exit 1; }
    run sudo "$@"
  fi
}

detect_platform() {
  case "$(uname -s)" in
    Linux)
      OS_KIND="linux"
      if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=1
        ok "WSL detected"
      else
        log "Native Linux detected"
      fi
      if command -v apt-get >/dev/null 2>&1; then
        PKG_KIND="apt"
      else
        PKG_KIND="none"
      fi
      ;;
    Darwin)
      OS_KIND="macos"
      PKG_KIND="brew"
      log "macOS detected"
      ;;
    *)
      err "Unsupported OS: $(uname -s). Supported: Linux (WSL/native), macOS"
      exit 1
      ;;
  esac
}

set_proxy_exports() {
  local proxy_url="$1"
  export HTTP_PROXY="$proxy_url"
  export HTTPS_PROXY="$proxy_url"
  export ALL_PROXY="$proxy_url"
  export http_proxy="$proxy_url"
  export https_proxy="$proxy_url"
  export all_proxy="$proxy_url"
  export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost}"
  export no_proxy="${no_proxy:-127.0.0.1,localhost}"
  ok "Proxy exported: $proxy_url"
}

tcp_probe() {
  local host="$1" port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -zw2 "$host" "$port" >/dev/null 2>&1
  else
    (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
  fi
}

wsl_auto_proxy() {
  [[ "$IS_WSL" -eq 1 ]] || return 0
  [[ "$AUTO_PROXY" == "1" && "$WSL_DETECT_HOST_PROXY" == "1" ]] || return 0

  # Keep existing proxy if already reachable.
  local cur_proxy hostport cur_host cur_port
  cur_proxy="${HTTPS_PROXY:-${https_proxy:-}}"
  if [[ -n "$cur_proxy" ]]; then
    hostport="${cur_proxy#*://}"
    hostport="${hostport%%/*}"
    cur_host="${hostport%%:*}"
    cur_port="${hostport##*:}"
    if [[ -n "$cur_host" && -n "$cur_port" ]] && tcp_probe "$cur_host" "$cur_port"; then
      ok "Existing proxy is reachable in WSL: ${cur_proxy}"
      return 0
    fi
  fi

  local win_ip
  win_ip="$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"

  local hosts=()
  hosts+=("127.0.0.1")
  [[ -n "$win_ip" ]] && hosts+=("$win_ip")

  local ports_csv="$WSL_PROXY_PORT_CANDIDATES"
  local IFS=','
  local ports=($ports_csv)

  local h p
  for h in "${hosts[@]}"; do
    for p in "${ports[@]}"; do
      p="${p// /}"
      [[ -n "$p" ]] || continue
      if tcp_probe "$h" "$p"; then
        set_proxy_exports "http://${h}:${p}"
        return 0
      fi
    done
  done

  warn "No reachable WSL proxy found (hosts=${hosts[*]}, ports=${WSL_PROXY_PORT_CANDIDATES}); keeping existing proxy env"
}

macos_active_network_service() {
  networksetup -listnetworkserviceorder 2>/dev/null \
    | awk -F'\) ' '/Hardware Port/ {print $2}' \
    | sed 's/ (Device:.*//' \
    | grep -v '^$' \
    | head -n 1
}

macos_auto_proxy() {
  [[ "$OS_KIND" == "macos" ]] || return 0
  [[ "$AUTO_PROXY" == "1" && "$MACOS_DETECT_PROXY" == "1" ]] || return 0

  local service host port enabled
  service="$(macos_active_network_service || true)"
  [[ -n "$service" ]] || { warn "Cannot detect active macOS network service"; return 0; }

  # HTTPS proxy first (preferred for npm/openclaw endpoints)
  enabled="$(networksetup -getsecurewebproxy "$service" 2>/dev/null | awk '/Enabled:/ {print $2}')"
  if [[ "$enabled" == "Yes" ]]; then
    host="$(networksetup -getsecurewebproxy "$service" 2>/dev/null | awk '/Server:/ {print $2}')"
    port="$(networksetup -getsecurewebproxy "$service" 2>/dev/null | awk '/Port:/ {print $2}')"
    if [[ -n "$host" && -n "$port" ]]; then
      set_proxy_exports "http://${host}:${port}"
      return 0
    fi
  fi

  # Fallback to HTTP proxy
  enabled="$(networksetup -getwebproxy "$service" 2>/dev/null | awk '/Enabled:/ {print $2}')"
  if [[ "$enabled" == "Yes" ]]; then
    host="$(networksetup -getwebproxy "$service" 2>/dev/null | awk '/Server:/ {print $2}')"
    port="$(networksetup -getwebproxy "$service" 2>/dev/null | awk '/Port:/ {print $2}')"
    if [[ -n "$host" && -n "$port" ]]; then
      set_proxy_exports "http://${host}:${port}"
      return 0
    fi
  fi

  log "No macOS system proxy enabled on service: ${service}"
}

apply_profile_defaults() {
  case "$PROFILE" in
    cn)
      AUTO_PROXY="1"
      FORCE_IPV4="1"
      NODE_USE_ENV_PROXY="1"
      if [[ -z "$NPM_REGISTRY" ]]; then
        NPM_REGISTRY="https://registry.npmmirror.com"
      fi
      ;;
    global)
      if [[ -z "${HTTP_PROXY:-${http_proxy:-}}" && -z "${HTTPS_PROXY:-${https_proxy:-}}" ]]; then
        AUTO_PROXY="0"
      fi
      ;;
    auto)
      # keep user-provided env as-is
      ;;
    *)
      warn "Unknown PROFILE=${PROFILE}, fallback to auto"
      PROFILE="auto"
      ;;
  esac
}

ensure_proxy_behavior_for_node() {
  if [[ "$NODE_USE_ENV_PROXY" == "1" ]]; then
    export NODE_USE_ENV_PROXY=1
    log "NODE_USE_ENV_PROXY=1 enabled"
  fi
}

curl_base_args() {
  local args=(--proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 3 --retry-delay 1 --retry-connrefused)
  if [[ "$FORCE_IPV4" == "1" ]]; then
    args=(-4 "${args[@]}")
  fi
  printf '%s\n' "${args[@]}"
}

curl_dl() {
  local url="$1" out="$2"
  mapfile -t _cargs < <(curl_base_args)
  run curl -fsSL "${_cargs[@]}" "$url" -o "$out"
}

network_probe() {
  log "Checking network endpoints..."
  local urls=(
    "https://openclaw.ai/install.sh"
    "https://deb.nodesource.com/setup_22.x"
    "https://registry.npmjs.org/openclaw"
  )

  mapfile -t _cargs < <(curl_base_args)
  local u
  for u in "${urls[@]}"; do
    if curl -I "${_cargs[@]}" --max-time 20 "$u" >/dev/null 2>&1; then
      ok "Reachable: $u"
    else
      warn "Unreachable now: $u"
    fi
  done
}

run_check_only() {
  log "Running compatibility checks only (no install changes)"
  echo "  - OS:       ${OS_KIND} (wsl=${IS_WSL})"
  echo "  - PKG:      ${PKG_KIND}"
  echo "  - Proxy:    ${HTTPS_PROXY:-${https_proxy:-<not set>}}"
  echo "  - Node:     $(node -v 2>/dev/null || echo missing)"
  echo "  - npm:      $(npm -v 2>/dev/null || echo missing)"
  echo "  - openclaw: $(openclaw --version 2>/dev/null || echo not installed)"

  network_probe

  if command -v node >/dev/null 2>&1; then
    if node -e "fetch('https://auth.openai.com/oauth/authorize').then(r=>console.log('node-fetch-ok',r.status)).catch(e=>{console.error('node-fetch-fail',e.message);process.exit(1)})"; then
      ok "Node fetch path to OpenAI auth is working"
    else
      warn "Node fetch path to OpenAI auth failed (likely proxy/cert issue)"
    fi
  else
    warn "Node not installed yet; skip Node fetch probe"
  fi

  if command -v openclaw >/dev/null 2>&1; then
    log "OpenClaw quick checks"
    openclaw --version || true
    openclaw models status --plain || true
  fi

  ok "Check-only mode complete"
}

apt_update() {
  sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" -o DPkg::Lock::Timeout=60 update
}

apt_install() {
  sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" -o DPkg::Lock::Timeout=60 install -y "$@"
}

install_prereqs_linux() {
  [[ "$PKG_KIND" == "apt" ]] || return 0
  log "[1/6] Installing prerequisites (Linux/apt)..."
  apt_update
  apt_install ca-certificates curl gnupg netcat-openbsd
  ok "Prerequisites ready"
}

install_prereqs_macos() {
  [[ "$OS_KIND" == "macos" ]] || return 0
  log "[1/6] Checking prerequisites (macOS)..."
  need_cmd curl
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew not found. Install from https://brew.sh then re-run for managed Node install."
  fi
  ok "Prerequisites checked"
}

install_build_tools() {
  if [[ "$SKIP_BUILD_TOOLS" == "1" ]]; then
    warn "[2/6] Skipping build tools as requested"
    return
  fi

  if [[ "$PKG_KIND" == "apt" ]]; then
    log "[2/6] Installing build tools (apt)..."
    apt_install build-essential python3 make g++ cmake
    ok "Build tools ready"
  elif [[ "$OS_KIND" == "macos" ]]; then
    log "[2/6] Checking Xcode CLI tools (macOS)..."
    if xcode-select -p >/dev/null 2>&1; then
      ok "Xcode Command Line Tools already installed"
    else
      warn "Xcode CLT not found. Installing..."
      xcode-select --install || true
      warn "If macOS popup appears, finish install then rerun script."
    fi
  fi
}

node_major() {
  node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0
}

install_node22_linux_apt() {
  log "[3/6] Ensuring Node.js >= 22 (Linux/apt)..."

  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node_major)"
    if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge 22 ]]; then
      ok "Node already satisfies requirement: $(node -v)"
      ok "npm version: $(npm -v 2>/dev/null || echo missing)"
      return
    fi
    warn "Existing Node is too old: $(node -v 2>/dev/null || echo unknown)"
  fi

  local tmp
  tmp="$(mktemp)"
  log "Configuring NodeSource (Node 22 repo)..."
  curl_dl "https://deb.nodesource.com/setup_22.x" "$tmp"
  sudo_run bash "$tmp"
  rm -f "$tmp"

  log "Installing nodejs package..."
  apt_install nodejs

  ok "Node installed: $(node -v)"
  ok "npm installed:  $(npm -v)"
}

install_node22_macos() {
  log "[3/6] Ensuring Node.js >= 22 (macOS)..."

  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node_major)"
    if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge 22 ]]; then
      ok "Node already satisfies requirement: $(node -v)"
      ok "npm version: $(npm -v 2>/dev/null || echo missing)"
      return
    fi
    warn "Existing Node is too old: $(node -v 2>/dev/null || echo unknown)"
  fi

  if command -v brew >/dev/null 2>&1; then
    run brew install node@22 || run brew upgrade node@22 || true
    # Prefer brewed node@22 if not linked globally
    if [[ -d "/opt/homebrew/opt/node@22/bin" ]]; then
      export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
    elif [[ -d "/usr/local/opt/node@22/bin" ]]; then
      export PATH="/usr/local/opt/node@22/bin:$PATH"
    fi
  else
    err "Homebrew not found, and Node <22. Install brew or Node 22 manually first."
    exit 1
  fi

  ok "Node installed/updated: $(node -v)"
  ok "npm installed:          $(npm -v)"
}

install_node22() {
  if [[ "$PKG_KIND" == "apt" ]]; then
    install_node22_linux_apt
  elif [[ "$OS_KIND" == "macos" ]]; then
    install_node22_macos
  else
    err "No supported package path for this OS"
    exit 1
  fi
}

configure_npm_registry_if_needed() {
  log "[4/6] Configuring npm (optional)..."
  if [[ -n "$NPM_REGISTRY" ]]; then
    run npm config set registry "$NPM_REGISTRY"
    ok "npm registry set to: $NPM_REGISTRY"
  else
    log "NPM_REGISTRY not set; using default registry"
  fi
}

setup_user_npm_prefix() {
  local npm_global_dir="$HOME/.npm-global"
  mkdir -p "$npm_global_dir"
  run npm config set prefix "$npm_global_dir"

  if [[ ":$PATH:" != *":$npm_global_dir/bin:"* ]]; then
    warn "Add this line to your shell rc, then open a new shell:"
    echo "export PATH=\"$npm_global_dir/bin:\$PATH\""
    export PATH="$npm_global_dir/bin:$PATH"
  fi
}

install_openclaw() {
  log "[5/6] Installing OpenClaw via npm..."
  local spec="openclaw"
  if [[ "$OPENCLAW_VERSION" != "latest" ]]; then
    spec="openclaw@${OPENCLAW_VERSION}"
  fi

  # idempotent fast path
  if command -v openclaw >/dev/null 2>&1; then
    local cur
    cur="$(openclaw --version 2>/dev/null | awk '{print $2}' | sed 's/^v//' || true)"
    if [[ "$OPENCLAW_VERSION" == "latest" && -n "$cur" ]]; then
      log "openclaw already installed (${cur}); continuing with npm install to ensure latest"
    fi
  fi

  if [[ "$USE_SUDO_NPM" == "1" ]]; then
    sudo_run npm install -g "$spec" --loglevel notice --no-fund --no-audit
  else
    setup_user_npm_prefix
    run npm install -g "$spec" --loglevel notice --no-fund --no-audit
  fi

  ok "Installed: ${spec}"
  hash -r || true

  if command -v openclaw >/dev/null 2>&1; then
    ok "openclaw available: $(openclaw --version || true)"
  else
    warn "openclaw not found on PATH yet."
    warn "Try: hash -r && source ~/.bashrc && which openclaw"
  fi
}

install_plugins() {
  if [[ "$INSTALL_CHANNEL_PLUGINS" != "1" ]]; then
    warn "[6/6] Plugin install skipped (INSTALL_CHANNEL_PLUGINS=0)"
    return
  fi

  if ! command -v openclaw >/dev/null 2>&1; then
    warn "openclaw command not found; skip plugin installation"
    return
  fi

  log "[6/6] Installing channel plugins (Feishu/WeCom/DingTalk)..."
  local plugins=(
    "@m1heng-clawd/feishu"
    "@wecom/wecom-openclaw-plugin"
    "@dingtalk-real-ai/dingtalk-connector"
  )

  local p
  for p in "${plugins[@]}"; do
    if openclaw plugins install "$p"; then
      ok "Plugin installed: $p"
    else
      warn "Plugin install failed: $p"
    fi
  done
}

print_summary() {
  echo
  ok "Done. Summary:"
  echo "  - OS:       ${OS_KIND} (wsl=${IS_WSL})"
  echo "  - Node:     $(node -v 2>/dev/null || echo missing)"
  echo "  - npm:      $(npm -v 2>/dev/null || echo missing)"
  echo "  - openclaw: $(openclaw --version 2>/dev/null || echo not found on PATH)"
  echo "  - proxy:    ${HTTPS_PROXY:-${https_proxy:-<not set>}}"
  echo
  echo "Recommended usage:"
  echo "  # WSL2/macOS auto-proxy"
  echo "  AUTO_PROXY=1 NODE_USE_ENV_PROXY=1 bash $0"
  echo
  echo "  # Linux VPS simple path"
  echo "  AUTO_PROXY=0 FORCE_IPV4=1 bash $0"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  need_cmd bash
  need_cmd curl
  detect_platform
  apply_profile_defaults

  log "OpenClaw universal installer"
  log "Plan: profile=${PROFILE}, version=${OPENCLAW_VERSION}, force_ipv4=${FORCE_IPV4}, sudo_npm=${USE_SUDO_NPM}, auto_proxy=${AUTO_PROXY}, check_only=${CHECK_ONLY}"
  log "WSL proxy candidate ports: ${WSL_PROXY_PORT_CANDIDATES}"

  if [[ "$PRINT_ONLY" == "1" ]]; then
    usage
    exit 0
  fi

  ensure_proxy_behavior_for_node
  wsl_auto_proxy
  macos_auto_proxy

  if [[ "$CHECK_ONLY" == "1" ]]; then
    run_check_only
    exit 0
  fi

  network_probe
  install_prereqs_linux
  install_prereqs_macos
  install_build_tools
  install_node22
  configure_npm_registry_if_needed
  install_openclaw
  install_plugins
  print_summary
}

main "$@"
