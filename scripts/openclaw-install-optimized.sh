#!/usr/bin/env bash
set -Eeuo pipefail

# OpenClaw Installer (optimized for Linux/WSL)
# Goals:
# - clear, real-time logs (no silent -qq steps)
# - explicit step boundaries
# - retry + timeout for network-heavy operations
# - resumable/idempotent behavior where possible

OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
FORCE_IPV4="${FORCE_IPV4:-1}"
NPM_REGISTRY="${NPM_REGISTRY:-}"
SKIP_BUILD_TOOLS="${SKIP_BUILD_TOOLS:-0}"

log()  { printf "\033[36m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[32m[ OK ]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[31m[ERR ]\033[0m %s\n" "$*"; }

on_error() {
  local exit_code=$?
  err "Failed at line $1 (exit=${exit_code})."
  err "If this is network-related, retry with FORCE_IPV4=1 and/or set NPM_REGISTRY."
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

sudo_run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    run "$@"
  else
    run sudo "$@"
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
  log "Installing prerequisites..."
  apt_update
  apt_install ca-certificates curl gnupg
  ok "Prerequisites ready"
}

install_build_tools() {
  if [[ "$SKIP_BUILD_TOOLS" == "1" ]]; then
    warn "Skipping build tools as requested"
    return
  fi
  log "Installing build tools (make/g++/cmake/python3)..."
  apt_install build-essential python3 make g++ cmake
  ok "Build tools ready"
}

install_node22() {
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge 22 ]]; then
      ok "Node already satisfies requirement: $(node -v)"
      return
    fi
    warn "Existing Node is too old: $(node -v 2>/dev/null || echo unknown)"
  fi

  log "Configuring NodeSource (Node 22)..."
  local tmp
  tmp="$(mktemp)"
  curl -fsSL --retry 3 --retry-delay 1 --retry-connrefused https://deb.nodesource.com/setup_22.x -o "$tmp"
  sudo_run bash "$tmp"
  rm -f "$tmp"

  log "Installing nodejs..."
  apt_install nodejs

  ok "Node installed: $(node -v)"
  ok "npm installed:  $(npm -v)"
}

configure_npm_registry_if_needed() {
  if [[ -n "$NPM_REGISTRY" ]]; then
    run npm config set registry "$NPM_REGISTRY"
    ok "npm registry set to: $NPM_REGISTRY"
  fi
}

install_openclaw() {
  local spec="openclaw"
  if [[ "$OPENCLAW_VERSION" != "latest" ]]; then
    spec="openclaw@${OPENCLAW_VERSION}"
  fi

  log "Installing ${spec} globally via npm..."
  # verbose enough for debugging, not overwhelmingly noisy
  sudo_run npm install -g "$spec" --loglevel notice --no-fund --no-audit
  ok "Installed: ${spec}"

  if command -v openclaw >/dev/null 2>&1; then
    ok "openclaw available: $(openclaw --version || true)"
  else
    warn "openclaw not found on PATH yet. Try: hash -r && which openclaw"
  fi
}

print_summary() {
  echo
  ok "Done. Summary:"
  echo "  - Node:     $(node -v 2>/dev/null || echo missing)"
  echo "  - npm:      $(npm -v 2>/dev/null || echo missing)"
  echo "  - openclaw: $(openclaw --version 2>/dev/null || echo not found on PATH)"
  echo
  echo "Tips:"
  echo "  - If npm is slow in CN: NPM_REGISTRY=https://registry.npmmirror.com bash $0"
  echo "  - If apt is flaky:      FORCE_IPV4=1 bash $0"
}

main() {
  need_cmd curl
  need_cmd bash

  log "OpenClaw optimized installer (Linux/WSL)"
  network_probe
  install_prereqs
  install_build_tools
  install_node22
  configure_npm_registry_if_needed
  install_openclaw
  print_summary
}

main "$@"
