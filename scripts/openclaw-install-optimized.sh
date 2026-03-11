#!/usr/bin/env bash
set -Eeuo pipefail

# OpenClaw Installer (optimized for Linux/WSL)
# Improvements vs upstream installer:
# - clear, real-time logs (no silent -qq apt steps)
# - explicit step boundaries + endpoint probes
# - retry/timeout for network-heavy operations
# - better error messages and safer defaults for WSL/CN networks
# - optional user-scope npm install (no sudo npm)

OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
FORCE_IPV4="${FORCE_IPV4:-1}"
NPM_REGISTRY="${NPM_REGISTRY:-}"
SKIP_BUILD_TOOLS="${SKIP_BUILD_TOOLS:-0}"
USE_SUDO_NPM="${USE_SUDO_NPM:-1}"
PRINT_ONLY="${PRINT_ONLY:-0}"

log()  { printf "\033[36m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m[ OK ]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[31m[ERR ]\033[0m %s\n" "$*"; }

usage() {
  cat <<'EOF'
Usage:
  bash openclaw-install-optimized.sh

Env options:
  OPENCLAW_VERSION=latest|x.y.z     (default: latest)
  FORCE_IPV4=1|0                    (default: 1)
  NPM_REGISTRY=https://...          (optional)
  SKIP_BUILD_TOOLS=1                (optional)
  USE_SUDO_NPM=1|0                  (default: 1)
  PRINT_ONLY=1                      (only print plan)

Examples:
  NPM_REGISTRY=https://registry.npmmirror.com FORCE_IPV4=1 bash openclaw-install-optimized.sh
  USE_SUDO_NPM=0 bash openclaw-install-optimized.sh
EOF
}

on_error() {
  local exit_code=$?
  err "Failed at line $1 (exit=${exit_code})."
  err "Hints: FORCE_IPV4=1, set NPM_REGISTRY, or rerun with USE_SUDO_NPM=0."
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
    have_sudo || { err "sudo is required for apt operations"; exit 1; }
    run sudo "$@"
  fi
}

check_platform() {
  [[ "${OSTYPE:-}" == linux* ]] || { err "This script targets Linux/WSL only."; exit 1; }
  command -v apt-get >/dev/null 2>&1 || { err "Only apt-based distros are supported in this script."; exit 1; }
  if grep -qi microsoft /proc/version 2>/dev/null; then
    ok "WSL detected"
  else
    log "Native Linux detected"
  fi
}

apt_update() {
  if [[ "$FORCE_IPV4" == "1" ]]; then
    sudo_run apt-get -o Acquire::ForceIPv4=true update
  else
    sudo_run apt-get update
  fi
}

apt_install() {
  if [[ "$FORCE_IPV4" == "1" ]]; then
    sudo_run apt-get -o Acquire::ForceIPv4=true install -y "$@"
  else
    sudo_run apt-get install -y "$@"
  fi
}

curl_dl() {
  local url="$1" out="$2"
  run curl -fsSL --connect-timeout 15 --max-time 180 --retry 3 --retry-delay 1 --retry-connrefused "$url" -o "$out"
}

network_probe() {
  log "Checking network endpoints..."
  local urls=(
    "https://openclaw.ai/install.sh"
    "https://deb.nodesource.com/setup_22.x"
    "https://registry.npmjs.org/openclaw"
  )
  local u
  for u in "${urls[@]}"; do
    if curl -I --connect-timeout 10 --max-time 20 "$u" >/dev/null 2>&1; then
      ok "Reachable: $u"
    else
      warn "Unreachable now: $u"
    fi
  done
}

install_prereqs() {
  log "[1/5] Installing prerequisites..."
  apt_update
  apt_install ca-certificates curl gnupg
  ok "Prerequisites ready"
}

install_build_tools() {
  if [[ "$SKIP_BUILD_TOOLS" == "1" ]]; then
    warn "[2/5] Skipping build tools as requested"
    return
  fi
  log "[2/5] Installing build tools (make/g++/cmake/python3)..."
  apt_install build-essential python3 make g++ cmake
  ok "Build tools ready"
}

node_major() {
  node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0
}

install_node22() {
  log "[3/5] Ensuring Node.js >= 22..."

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

configure_npm_registry_if_needed() {
  log "[4/5] Configuring npm (optional)..."
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
    warn "Add this line to ~/.bashrc, then open a new shell:"
    echo "export PATH=\"$npm_global_dir/bin:\$PATH\""
    export PATH="$npm_global_dir/bin:$PATH"
  fi
}

install_openclaw() {
  log "[5/5] Installing OpenClaw via npm..."
  local spec="openclaw"
  if [[ "$OPENCLAW_VERSION" != "latest" ]]; then
    spec="openclaw@${OPENCLAW_VERSION}"
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

print_summary() {
  echo
  ok "Done. Summary:"
  echo "  - Node:     $(node -v 2>/dev/null || echo missing)"
  echo "  - npm:      $(npm -v 2>/dev/null || echo missing)"
  echo "  - openclaw: $(openclaw --version 2>/dev/null || echo not found on PATH)"
  echo
  echo "Recommended usage (WSL/CN):"
  echo "  NPM_REGISTRY=https://registry.npmmirror.com FORCE_IPV4=1 bash $0"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  need_cmd bash
  need_cmd curl
  check_platform

  log "OpenClaw optimized installer (Linux/WSL)"
  log "Plan: version=${OPENCLAW_VERSION}, force_ipv4=${FORCE_IPV4}, sudo_npm=${USE_SUDO_NPM}"
  if [[ "$PRINT_ONLY" == "1" ]]; then
    usage
    exit 0
  fi

  network_probe
  install_prereqs
  install_build_tools
  install_node22
  configure_npm_registry_if_needed
  install_openclaw
  print_summary
}

main "$@"
