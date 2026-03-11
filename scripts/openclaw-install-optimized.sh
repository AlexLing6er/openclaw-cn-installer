#!/usr/bin/env bash
set -Eeuo pipefail

# OpenClaw Universal Installer (Linux / WSL2 / macOS)
# - CN + Global profiles
# - WSL2 proxy auto-detect (10808/7897/custom)
# - mirror fallback for npm + NodeSource script
# - check-only mode for safe diagnostics

OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
PROFILE="${PROFILE:-auto}"                  # auto|cn|global
CHECK_ONLY="${CHECK_ONLY:-0}"               # 1 => diagnostics only
AUTO_PROXY="${AUTO_PROXY:-1}"
NODE_USE_ENV_PROXY="${NODE_USE_ENV_PROXY:-1}"
FORCE_IPV4="${FORCE_IPV4:-1}"
USE_SUDO_NPM="${USE_SUDO_NPM:-1}"
SKIP_BUILD_TOOLS="${SKIP_BUILD_TOOLS:-0}"
INSTALL_CHANNEL_PLUGINS="${INSTALL_CHANNEL_PLUGINS:-0}"
WSL_PROXY_PORT_CANDIDATES="${WSL_PROXY_PORT_CANDIDATES:-10808,7897}"
NPM_REGISTRY="${NPM_REGISTRY:-}"
DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

OS_KIND=""
IS_WSL=0
ROUTE="UNKNOWN"
REGION_HINT="UNKNOWN"
SELECTED_NODE_SETUP_URL=""

log(){ printf "\033[36m[INFO]\033[0m %s\n" "$*"; }
ok(){ printf "\033[32m[ OK ]\033[0m %s\n" "$*"; }
warn(){ printf "\033[33m[WARN]\033[0m %s\n" "$*"; }
err(){ printf "\033[31m[ERR ]\033[0m %s\n" "$*"; }

show_credit(){
  printf "\n\033[35m%s\033[0m\n" "========================================"
  printf "\033[35m%s\033[0m\n" "By Douhao / 作者：逗号"
  printf "\033[35m%s\033[0m\n" "Blog / 博客: https://www.youdiandou.store"
  printf "\033[35m%s\033[0m\n\n" "========================================"
}

usage(){
  cat <<'EOF'
Usage:
  bash scripts/openclaw-install-optimized.sh

Profiles:
  PROFILE=cn      China-friendly defaults (proxy on, mirror on, IPv4 on)
  PROFILE=global  Global defaults (no forced proxy)
  PROFILE=auto    Keep current environment

Common:
  CHECK_ONLY=1                    Diagnostics only
  WSL_PROXY_PORT_CANDIDATES=10808,7897,8888
  NPM_REGISTRY=https://registry.npmmirror.com
  FORCE_IPV4=1

Examples:
  PROFILE=cn bash scripts/openclaw-install-optimized.sh
  PROFILE=global bash scripts/openclaw-install-optimized.sh
  CHECK_ONLY=1 PROFILE=auto bash scripts/openclaw-install-optimized.sh
EOF
}

trap 'err "Failed at line ${LINENO}."' ERR

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }; }

sudo_run(){
  if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

curl_common(){
  local args=(--proto '=https' --tlsv1.2 --connect-timeout 12 --max-time 90 --retry 3 --retry-delay 1 --retry-connrefused)
  [[ "$FORCE_IPV4" == "1" ]] && args=(-4 "${args[@]}")
  printf '%s\n' "${args[@]}"
}

detect_platform(){
  case "$(uname -s)" in
    Linux)
      OS_KIND="linux"
      grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1 || true
      ;;
    Darwin)
      OS_KIND="macos"
      ;;
    *)
      err "Unsupported OS: $(uname -s)"
      exit 1
      ;;
  esac
}

apply_profile_defaults(){
  case "$PROFILE" in
    cn)
      AUTO_PROXY=1
      NODE_USE_ENV_PROXY=1
      FORCE_IPV4=1
      [[ -z "$NPM_REGISTRY" ]] && NPM_REGISTRY="https://registry.npmmirror.com"
      ;;
    global)
      [[ -z "${HTTP_PROXY:-${http_proxy:-}}" ]] && AUTO_PROXY=0
      ;;
    auto) ;;
    *) warn "Unknown PROFILE=$PROFILE, fallback auto"; PROFILE=auto ;;
  esac
}

proxy_export(){
  local p="$1"
  export HTTP_PROXY="$p" HTTPS_PROXY="$p" ALL_PROXY="$p"
  export http_proxy="$p" https_proxy="$p" all_proxy="$p"
  export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost}" no_proxy="${no_proxy:-127.0.0.1,localhost}"
  ok "Proxy set: $p"
}

tcp_probe(){
  local host="$1" port="$2"
  if command -v nc >/dev/null 2>&1; then nc -zw2 "$host" "$port" >/dev/null 2>&1
  else (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; fi
}

wsl_proxy_autodetect(){
  [[ "$IS_WSL" -eq 1 && "$AUTO_PROXY" == "1" ]] || return 0

  local cur="${HTTPS_PROXY:-${https_proxy:-}}"
  if [[ -n "$cur" ]]; then
    local hp="${cur#*://}"; hp="${hp%%/*}"
    local h="${hp%%:*}" p="${hp##*:}"
    if [[ -n "$h" && -n "$p" ]] && tcp_probe "$h" "$p"; then ok "Existing proxy reachable: $cur"; return 0; fi
  fi

  local win_ip="$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
  local hosts=("127.0.0.1")
  [[ -n "$win_ip" ]] && hosts+=("$win_ip")

  local IFS=','; read -r -a ports <<< "$WSL_PROXY_PORT_CANDIDATES"
  local h p
  for h in "${hosts[@]}"; do
    for p in "${ports[@]}"; do
      p="${p// /}"
      [[ -n "$p" ]] || continue
      if tcp_probe "$h" "$p"; then proxy_export "http://${h}:${p}"; return 0; fi
    done
  done
  warn "No WSL proxy found at hosts=[${hosts[*]}] ports=$WSL_PROXY_PORT_CANDIDATES"
}

macos_proxy_autodetect(){
  [[ "$OS_KIND" == "macos" && "$AUTO_PROXY" == "1" ]] || return 0
  command -v networksetup >/dev/null 2>&1 || return 0
  local svc
  svc="$(networksetup -listnetworkserviceorder | awk -F') ' '/Hardware Port/{print $2}' | sed 's/ (Device:.*//' | head -n1)"
  [[ -n "$svc" ]] || return 0
  local en host port
  en="$(networksetup -getsecurewebproxy "$svc" 2>/dev/null | awk '/Enabled:/{print $2}')"
  if [[ "$en" == "Yes" ]]; then
    host="$(networksetup -getsecurewebproxy "$svc" | awk '/Server:/{print $2}')"
    port="$(networksetup -getsecurewebproxy "$svc" | awk '/Port:/{print $2}')"
    [[ -n "$host" && -n "$port" ]] && proxy_export "http://${host}:${port}" && return 0
  fi
  en="$(networksetup -getwebproxy "$svc" 2>/dev/null | awk '/Enabled:/{print $2}')"
  if [[ "$en" == "Yes" ]]; then
    host="$(networksetup -getwebproxy "$svc" | awk '/Server:/{print $2}')"
    port="$(networksetup -getwebproxy "$svc" | awk '/Port:/{print $2}')"
    [[ -n "$host" && -n "$port" ]] && proxy_export "http://${host}:${port}" && return 0
  fi
}

set_node_proxy_switch(){
  [[ "$NODE_USE_ENV_PROXY" == "1" ]] && export NODE_USE_ENV_PROXY=1 && log "NODE_USE_ENV_PROXY=1"
}

detect_region_hint(){
  local r=""
  mapfile -t cargs < <(curl_common)

  r="$(curl -fsSL "${cargs[@]}" --max-time 6 https://ipapi.co/country 2>/dev/null | tr -d '\r\n ' || true)"
  if [[ -z "$r" || ${#r} -gt 3 ]]; then
    r="$(curl -fsSL "${cargs[@]}" --max-time 6 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n ' || true)"
  fi

  case "$r" in
    CN|cn) REGION_HINT="CN" ;;
    "") REGION_HINT="UNKNOWN" ;;
    *) REGION_HINT="NON_CN" ;;
  esac
}

decide_route(){
  local has_proxy="0"
  [[ -n "${HTTPS_PROXY:-${https_proxy:-}}" ]] && has_proxy="1"

  local official_ok="0" cn_ok="0"
  mapfile -t cargs < <(curl_common)
  curl -I "${cargs[@]}" --max-time 10 "https://registry.npmjs.org/openclaw" >/dev/null 2>&1 && official_ok="1"
  curl -I "${cargs[@]}" --max-time 10 "https://registry.npmmirror.com/openclaw" >/dev/null 2>&1 && cn_ok="1"

  if [[ "$PROFILE" == "cn" ]]; then
    ROUTE="CN_MIRROR"
    return 0
  fi
  if [[ "$PROFILE" == "global" ]]; then
    ROUTE="GLOBAL_DIRECT"
    return 0
  fi

  # Auto policy required by user:
  # 1) proxy on -> official first
  # 2) no proxy + outside CN -> official first
  # 3) no proxy + in CN -> CN mirrors first
  if [[ "$has_proxy" == "1" ]]; then
    ROUTE="PROXY_OFFICIAL"
    return 0
  fi

  detect_region_hint
  if [[ "$REGION_HINT" == "CN" ]]; then
    ROUTE="CN_MIRROR"
  elif [[ "$REGION_HINT" == "NON_CN" ]]; then
    ROUTE="GLOBAL_DIRECT"
  else
    # Unknown region: prefer official if reachable, else CN mirror
    if [[ "$official_ok" == "1" ]]; then ROUTE="GLOBAL_DIRECT"; else ROUTE="CN_MIRROR"; fi
  fi
}

print_decision(){
  echo "=== INSTALL DECISION ==="
  echo "DetectedOS=$OS_KIND"
  echo "DetectedEnv=$([[ "$IS_WSL" -eq 1 ]] && echo WSL2 || echo "$OS_KIND")"
  echo "Profile=$PROFILE"
  echo "Route=$ROUTE"
  echo "RegionHint=$REGION_HINT"
  echo "Proxy=${HTTPS_PROXY:-${https_proxy:-<none>}}"
  echo "NpmRegistry=${NPM_REGISTRY:-<auto>}"
  echo "NodeSetup=${SELECTED_NODE_SETUP_URL:-<auto>}"
  echo "========================"
}

select_first_reachable(){
  local outvar="$1"; shift
  local u
  mapfile -t cargs < <(curl_common)
  for u in "$@"; do
    if curl -I "${cargs[@]}" --max-time 20 "$u" >/dev/null 2>&1; then
      printf -v "$outvar" '%s' "$u"
      return 0
    fi
  done
  return 1
}

select_fastest_reachable(){
  local outvar="$1"; shift
  local best_url="" best_ms=999999 ms u
  mapfile -t cargs < <(curl_common)

  for u in "$@"; do
    ms="$(curl -I "${cargs[@]}" --max-time 12 -o /dev/null -s -w '%{time_total}' "$u" 2>/dev/null || true)"
    [[ -z "$ms" ]] && continue
    ms="${ms%%.*}${ms#*.}"   # rough numeric without dot for compare
    ms="${ms:0:6}"
    [[ -z "$ms" ]] && continue
    if [[ "$ms" =~ ^[0-9]+$ ]] && (( 10#$ms < best_ms )); then
      best_ms=$((10#$ms))
      best_url="$u"
    fi
  done

  if [[ -n "$best_url" ]]; then
    printf -v "$outvar" '%s' "$best_url"
    return 0
  fi
  return 1
}

network_report(){
  log "Network resource check"
  local endpoints=(
    "https://openclaw.ai/install.sh"
    "https://openclaw.ai/install.ps1"
    "https://registry.npmjs.org/openclaw"
    "https://registry.npmmirror.com/openclaw"
    "https://mirrors.tencent.com/npm/openclaw"
    "https://repo.huaweicloud.com/repository/npm/openclaw"
    "https://deb.nodesource.com/setup_22.x"
    "https://mirrors.ustc.edu.cn/nodesource/deb/setup_22.x"
    "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/"
    "https://mirrors.aliyun.com/homebrew/"
  )
  mapfile -t cargs < <(curl_common)
  local u
  for u in "${endpoints[@]}"; do
    if curl -I "${cargs[@]}" --max-time 15 "$u" >/dev/null 2>&1; then ok "reachable: $u"; else warn "unreachable: $u"; fi
  done
}

install_prereqs_linux(){
  [[ "$OS_KIND" == "linux" ]] || return 0

  if command -v apt-get >/dev/null 2>&1; then
    sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" -o DPkg::Lock::Timeout=60 update
    sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" -o DPkg::Lock::Timeout=60 install -y ca-certificates curl gnupg netcat-openbsd
    if [[ "$SKIP_BUILD_TOOLS" != "1" ]]; then
      sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" install -y build-essential python3 make g++ cmake
    fi
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    sudo_run bash -c 'dnf install -y ca-certificates curl nmap-ncat || dnf install -y ca-certificates curl netcat'
    [[ "$SKIP_BUILD_TOOLS" != "1" ]] && sudo_run dnf groupinstall -y "Development Tools" || true
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    sudo_run bash -c 'yum install -y ca-certificates curl nmap-ncat || yum install -y ca-certificates curl nc'
    [[ "$SKIP_BUILD_TOOLS" != "1" ]] && sudo_run yum groupinstall -y "Development Tools" || true
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    sudo_run pacman -Sy --noconfirm ca-certificates curl gnu-netcat
    [[ "$SKIP_BUILD_TOOLS" != "1" ]] && sudo_run pacman -Sy --noconfirm base-devel python cmake || true
    return 0
  fi

  if command -v zypper >/dev/null 2>&1; then
    sudo_run zypper --non-interactive install ca-certificates curl netcat-openbsd
    [[ "$SKIP_BUILD_TOOLS" != "1" ]] && sudo_run zypper --non-interactive install -t pattern devel_basis || true
    return 0
  fi

  warn "Unknown Linux package manager. Please ensure curl/node/npm are installed manually."
}

install_prereqs_macos(){
  [[ "$OS_KIND" == "macos" ]] || return 0
  need_cmd curl
}

ensure_cmake_compat_linux(){
  [[ "$OS_KIND" == "linux" ]] || return 0
  command -v cmake >/dev/null 2>&1 || return 0

  local cur="$(cmake --version 2>/dev/null | awk 'NR==1{print $3}')"
  [[ -n "$cur" ]] || return 0

  if dpkg --compare-versions "$cur" ge "3.19"; then
    ok "CMake OK: $cur"
    return 0
  fi

  warn "CMake is too old: $cur (<3.19). Trying upgrade for compatibility..."

  # Ubuntu 20.04 (focal) often ships 3.16.x; add Kitware repo for newer CMake.
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" && "${VERSION_CODENAME:-}" == "focal" ]]; then
      sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" install -y software-properties-common gpg wget ca-certificates
      if [[ ! -f /usr/share/keyrings/kitware-archive-keyring.gpg ]]; then
        run bash -c "wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor > /usr/share/keyrings/kitware-archive-keyring.gpg"
      fi
      echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ focal main" | sudo_run tee /etc/apt/sources.list.d/kitware.list >/dev/null
      sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" update
      sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" install -y cmake
    fi
  fi

  cur="$(cmake --version 2>/dev/null | awk 'NR==1{print $3}')"
  if [[ -n "$cur" ]] && dpkg --compare-versions "$cur" ge "3.19"; then
    ok "CMake upgraded: $cur"
  else
    warn "CMake is still <3.19; npm install may fail on node-llama-cpp builds"
  fi
}

ensure_node22_linux(){
  [[ "$OS_KIND" == "linux" ]] || return 0
  if command -v node >/dev/null 2>&1 && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]]; then ok "Node OK: $(node -v)"; return 0; fi

  if ! command -v apt-get >/dev/null 2>&1; then
    err "Node 22+ is required. Auto install currently supports Debian/Ubuntu (apt)."
    err "Please install Node 22+ manually (for example via nvm or distro package manager), then rerun."
    exit 1
  fi

  local setup_url
  if [[ "$ROUTE" == "CN_MIRROR" ]]; then
    select_first_reachable setup_url \
      "https://mirrors.ustc.edu.cn/nodesource/deb/setup_22.x" \
      "https://deb.nodesource.com/setup_22.x"
  else
    select_first_reachable setup_url \
      "https://deb.nodesource.com/setup_22.x" \
      "https://mirrors.ustc.edu.cn/nodesource/deb/setup_22.x"
  fi

  [[ -n "${setup_url:-}" ]] || { err "No reachable NodeSource setup mirror"; exit 1; }
  SELECTED_NODE_SETUP_URL="$setup_url"
  log "Using Node setup: $setup_url"
  local tmp; tmp="$(mktemp)"
  mapfile -t cargs < <(curl_common)
  curl -fsSL "${cargs[@]}" "$setup_url" -o "$tmp"
  sudo_run bash "$tmp"
  rm -f "$tmp"
  sudo_run apt-get -o Acquire::ForceIPv4="$FORCE_IPV4" install -y nodejs
  command -v node >/dev/null 2>&1 || { err "Node install finished but node command not found"; exit 1; }
  ok "Node installed: $(node -v)"
}

ensure_node22_macos(){
  [[ "$OS_KIND" == "macos" ]] || return 0
  if command -v node >/dev/null 2>&1 && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]]; then ok "Node OK: $(node -v)"; return 0; fi
  command -v brew >/dev/null 2>&1 || { err "Please install Homebrew first: https://brew.sh"; exit 1; }

  # CN-friendly brew mirrors (optional, non-destructive)
  if [[ "$PROFILE" == "cn" ]]; then
    export HOMEBREW_BOTTLE_DOMAIN="${HOMEBREW_BOTTLE_DOMAIN:-https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles}"
    log "HOMEBREW_BOTTLE_DOMAIN=$HOMEBREW_BOTTLE_DOMAIN"
  fi

  brew install node@22 || brew upgrade node@22 || true
  if [[ -d /opt/homebrew/opt/node@22/bin ]]; then export PATH="/opt/homebrew/opt/node@22/bin:$PATH"; fi
  if [[ -d /usr/local/opt/node@22/bin ]]; then export PATH="/usr/local/opt/node@22/bin:$PATH"; fi

  command -v node >/dev/null 2>&1 || { err "Node install finished but node command not found in PATH"; exit 1; }
  [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]] || { err "Node version is still <22: $(node -v)"; exit 1; }
  ok "Node installed: $(node -v)"
}

configure_npm_registry(){
  if [[ -z "$NPM_REGISTRY" ]]; then
    local chosen=""
    local official="https://registry.npmjs.org/openclaw"
    local m1="https://registry.npmmirror.com/openclaw"
    local m2="https://mirrors.tencent.com/npm/openclaw"
    local m3="https://repo.huaweicloud.com/repository/npm/openclaw"

    # Simple policy:
    # - official-preferred routes: use official first, fallback to fastest mirror
    # - CN route: use fastest CN mirror, fallback official
    if [[ "$ROUTE" == "PROXY_OFFICIAL" || "$ROUTE" == "GLOBAL_DIRECT" ]]; then
      if select_first_reachable chosen "$official"; then
        :
      else
        select_fastest_reachable chosen "$m1" "$m2" "$m3" "$official" || true
      fi
    else
      if ! select_fastest_reachable chosen "$m1" "$m2" "$m3"; then
        select_first_reachable chosen "$official" || true
      fi
    fi

    case "$chosen" in
      *npmmirror*) NPM_REGISTRY="https://registry.npmmirror.com" ;;
      *tencent*) NPM_REGISTRY="https://mirrors.tencent.com/npm" ;;
      *huaweicloud*) NPM_REGISTRY="https://repo.huaweicloud.com/repository/npm" ;;
      *) NPM_REGISTRY="https://registry.npmjs.org" ;;
    esac
  fi
  npm config set registry "$NPM_REGISTRY"
  ok "npm registry: $NPM_REGISTRY"
}

ensure_path_line(){
  local line="$1"
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.profile"; do
    touch "$rc"
    grep -Fqx "$line" "$rc" || echo "$line" >> "$rc"
  done
}

setup_user_prefix(){
  local d="$HOME/.npm-global"
  mkdir -p "$d"
  npm config set prefix "$d"
  export PATH="$d/bin:$PATH"
  ensure_path_line "export PATH=\"$HOME/.npm-global/bin:\$PATH\""
}

install_openclaw(){
  local spec="openclaw"
  [[ "$OPENCLAW_VERSION" != "latest" ]] && spec="openclaw@${OPENCLAW_VERSION}"

  if [[ "$USE_SUDO_NPM" == "1" ]]; then
    if ! sudo_run npm install -g "$spec" --no-fund --no-audit; then
      warn "sudo npm install failed; fallback to user npm prefix"
      setup_user_prefix
      npm install -g "$spec" --no-fund --no-audit
    fi
  else
    setup_user_prefix
    npm install -g "$spec" --no-fund --no-audit
  fi

  # PATH reconciliation for heterogeneous VPS environments
  local npm_prefix npm_bin
  npm_prefix="$(npm config get prefix 2>/dev/null || true)"
  npm_bin="${npm_prefix%/}/bin"
  [[ -d "$npm_bin" ]] && export PATH="$npm_bin:$PATH"
  hash -r || true

  if command -v openclaw >/dev/null 2>&1; then
    ok "openclaw: $(openclaw --version)"
    return 0
  fi

  # final fallback: symlink discovered binary into /usr/local/bin
  local oc
  oc="$(find "$HOME" /usr/local /usr -maxdepth 4 -type f -name openclaw 2>/dev/null | head -n1 || true)"
  if [[ -n "$oc" && -x "$oc" ]]; then
    sudo_run ln -sf "$oc" /usr/local/bin/openclaw
    hash -r || true
  fi

  command -v openclaw >/dev/null 2>&1 && ok "openclaw: $(openclaw --version)" || { err "openclaw not in PATH (prefix=$npm_prefix). Try: export PATH=\"$npm_bin:\$PATH\""; exit 1; }
}

install_plugins(){
  [[ "$INSTALL_CHANNEL_PLUGINS" == "1" ]] || return 0
  openclaw plugins install @m1heng-clawd/feishu || true
  openclaw plugins install @wecom/wecom-openclaw-plugin || true
  openclaw plugins install @dingtalk-real-ai/dingtalk-connector || true
}

check_only(){
  echo "OS=$OS_KIND WSL=$IS_WSL PROFILE=$PROFILE"
  echo "Proxy=${HTTPS_PROXY:-${https_proxy:-<none>}}"
  echo "Node=$(node -v 2>/dev/null || echo missing) npm=$(npm -v 2>/dev/null || echo missing)"
  echo "OpenClaw=$(openclaw --version 2>/dev/null || echo missing)"
  network_report
  if command -v node >/dev/null 2>&1; then
    node -e "fetch('https://auth.openai.com/oauth/authorize').then(r=>console.log('node-fetch-ok',r.status)).catch(e=>console.log('node-fetch-fail',e.message))"
  fi
}

main(){
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage && exit 0
  show_credit
  need_cmd bash; need_cmd curl

  detect_platform
  apply_profile_defaults
  set_node_proxy_switch
  wsl_proxy_autodetect
  macos_proxy_autodetect
  decide_route

  log "Plan: profile=$PROFILE check_only=$CHECK_ONLY os=$OS_KIND wsl=$IS_WSL route=$ROUTE"

  if [[ "$CHECK_ONLY" == "1" ]]; then print_decision; check_only; exit 0; fi

  print_decision
  network_report
  install_prereqs_linux
  install_prereqs_macos
  ensure_node22_linux
  ensure_node22_macos
  ensure_cmake_compat_linux
  configure_npm_registry
  install_openclaw
  install_plugins

  ok "Done"
  printf "\n\033[1;32m%s\033[0m\n" "========================================"
  printf "\033[1;32m%s\033[0m\n" "NEXT STEP / 下一步（必须执行）"
  printf "\033[1;33m%s\033[0m\n" "openclaw onboard --install-daemon"
  printf "\033[1;32m%s\033[0m\n\n" "========================================"
}

main "$@"
