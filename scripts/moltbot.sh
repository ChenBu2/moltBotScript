#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

VERSION="2026-01-29"
PORT="${PORT:-18789}"
MODE="${MODE:-native}"
CHANNEL="${CHANNEL:-stable}"
COLOR=true

_bold() { printf "\033[1m%s\033[0m" "$1"; }
_green() { printf "\033[32m%s\033[0m" "$1"; }
_yellow() { printf "\033[33m%s\033[0m" "$1"; }
_red() { printf "\033[31m%s\033[0m" "$1"; }

log() { printf "[moltbot] %s\n" "$1"; }
info() { $COLOR && log "$(_green "$1")" || log "$1"; }
warn() { $COLOR && log "$(_yellow "$1")" || log "$1"; }
err() { $COLOR && log "$(_red "$1")" || log "$1"; }

usage() {
  cat <<'EOF'
Usage: moltbot.sh [--mode native|docker] [--channel stable|beta|dev] [--port 18789]
  --mode     Install + start using native Node (default) or Docker
  --channel  Use npm channel when installing globally (stable|beta|dev)
  --port     Gateway port (default: 18789)
Environment:
  MODE, CHANNEL, PORT can be set via env vars.
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode) MODE="${2:-native}"; shift 2 ;;
      --channel) CHANNEL="${2:-stable}"; shift 2 ;;
      --port) PORT="${2:-18789}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $1"; shift ;;
    esac
  done
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }; }
os_name() { uname -s 2>/dev/null || echo unknown; }
is_macos() { [ "$(os_name)" = "Darwin" ]; }
is_linux() { [ "$(os_name)" = "Linux" ]; }

node_version_ok() {
  if ! command -v node >/dev/null 2>&1; then return 1; fi
  local v; v="$(node -v 2>/dev/null | sed 's/^v//')"
  local major="${v%%.*}"
  [ -n "$major" ] && [ "$major" -ge 22 ]
}

ensure_node() {
  if node_version_ok; then info "Node $(node -v) OK (>=22)"; return 0; fi
  warn "Node >=22 not found. Attempting install..."
  if is_macos && command -v brew >/dev/null 2>&1; then
    info "Installing Node via Homebrew"
    brew install node@22 || brew install node
  elif is_linux && command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y curl ca-certificates gnupg
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  elif is_linux && command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y nodejs
  elif is_linux && command -v yum >/dev/null 2>&1; then
    sudo yum install -y nodejs
  else
    warn "Falling back to nvm install"
    if ! command -v curl >/dev/null 2>&1; then require_cmd wget; fi
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # shellcheck disable=SC1090
    . "$HOME/.nvm/nvm.sh"
    nvm install 22
  fi
  if ! node_version_ok; then err "Node install failed or version <22"; exit 1; fi
}

ensure_corepack() {
  if command -v corepack >/dev/null 2>&1; then
    corepack enable || true
    corepack prepare pnpm@latest --activate || true
  else
    warn "Corepack not available; installing pnpm globally via npm"
    if command -v npm >/dev/null 2>&1; then npm i -g pnpm@latest; else err "npm missing"; exit 1; fi
  fi
}

has_repo() { [ -f "package.json" ] && [ -f "pnpm-workspace.yaml" ]; }

load_env() {
  if [ -f ".env" ]; then
    info "Loading .env"
    set -a
    # shellcheck disable=SC1091
    . ".env"
    set +a
  fi
}

install_native_global() {
  ensure_corepack
  if command -v pnpm >/dev/null 2>&1; then
    info "Installing moltbot globally via pnpm (${CHANNEL})"
    pnpm add -g "moltbot@${CHANNEL}" || pnpm add -g moltbot@latest
  elif command -v npm >/dev/null 2>&1; then
    info "Installing moltbot globally via npm (${CHANNEL})"
    npm i -g "moltbot@${CHANNEL}" || npm i -g moltbot@latest
  else
    err "No npm/pnpm found"; exit 1
  fi
}

install_native_source() {
  ensure_corepack
  require_cmd pnpm
  info "Installing from source (pnpm install)"
  pnpm install
  info "Building UI (pnpm ui:build)"
  pnpm ui:build || true
  info "Building project (pnpm build)"
  pnpm build
}

start_gateway_native() {
  require_cmd moltbot
  info "Running onboarding wizard (installing daemon)"
  moltbot onboard --install-daemon || true
  info "Starting Gateway on port ${PORT}"
  nohup moltbot gateway --port "${PORT}" --verbose >/tmp/moltbot-gateway.log 2>&1 &
  info "Gateway log: /tmp/moltbot-gateway.log"
}

start_gateway_source() {
  info "Running onboarding wizard via pnpm (TypeScript)"
  pnpm moltbot onboard --install-daemon || true
  info "Starting Gateway (pnpm gateway:watch)"
  nohup pnpm gateway:watch >/tmp/moltbot-gateway.log 2>&1 &
  info "Gateway log: /tmp/moltbot-gateway.log"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    info "Docker found"
  else
    err "Docker is not installed"; exit 1
  fi
  if [ -f "./docker-setup.sh" ]; then
    info "Running docker-setup.sh"
    bash ./docker-setup.sh
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
  else
    info "Using docker compose plugin"
    docker compose up -d
  fi
}

main() {
  parse_args "$@"
  info "Moltbot one-click deploy/start (${MODE})"
  load_env
  ensure_node

  if [ "${MODE}" = "docker" ]; then
    install_docker
    info "Docker deployment started."
    exit 0
  fi

  if has_repo; then
    info "Detected moltbot repository (source build)"
    install_native_source
    start_gateway_source
  else
    info "Global install (no repo detected)"
    install_native_global
    start_gateway_native
  fi

  info "Done. Visit Control UI via WebChat or CLI."
  info "Try: moltbot message send --to <phone> --message \"Hello\""
}

main "$@"