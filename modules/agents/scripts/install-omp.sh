#!/usr/bin/env sh
# Ordered, idempotent OMP binary installer.
# Provider order: healthy omp → ZeroBrew (zb|zerobrew) → Homebrew can1357/tap/omp
# → curl -fsSL https://omp.sh/install | sh
# Does not write OMP settings, credentials, agents, MCP, prompts, or dotfiles.
set -eu

OMP_INSTALL_OFFICIAL_URL="${OMP_INSTALL_OFFICIAL_URL:-https://omp.sh/install}"
PROVIDER_LOG="${OMP_INSTALL_PROVIDER_LOG:-}"

log_provider() {
  _msg="$1"
  if [ -n "$PROVIDER_LOG" ]; then
    printf '%s\n' "$_msg" >>"$PROVIDER_LOG"
  fi
  printf '%s\n' "$_msg" >&2
}

omp_healthy() {
  command -v omp >/dev/null 2>&1 && omp --version >/dev/null 2>&1
}

# Append known install locations so a pre-existing earlier PATH entry
# (including test shims) keeps priority; still discover brew/official installs.
refresh_path() {
  for _dir in \
    "$HOME/.local/bin" \
    "$HOME/.omp/bin" \
    /opt/homebrew/bin \
    /usr/local/bin
  do
    case ":$PATH:" in
      *":$_dir:"*) ;;
      *)
        if [ -d "$_dir" ]; then
          PATH="$PATH:$_dir"
          export PATH
        fi
        ;;
    esac
  done
}

if omp_healthy; then
  log_provider "provider=existing version=$(omp --version 2>/dev/null | head -n1 || echo ok)"
  exit 0
fi

# ZeroBrew: zb preferred, else zerobrew
_zb=""
if command -v zb >/dev/null 2>&1; then
  _zb="$(command -v zb)"
elif command -v zerobrew >/dev/null 2>&1; then
  _zb="$(command -v zerobrew)"
fi

if [ -n "$_zb" ]; then
  log_provider "provider=zerobrew path=$_zb"
  if "$_zb" install omp; then
    refresh_path
    if omp_healthy; then
      log_provider "provider=zerobrew version=$(omp --version 2>/dev/null | head -n1 || echo ok)"
      exit 0
    fi
  fi
fi

_brew=""
if command -v brew >/dev/null 2>&1; then
  _brew="$(command -v brew)"
fi

if [ -n "$_brew" ]; then
  log_provider "provider=homebrew path=$_brew"
  if "$_brew" install can1357/tap/omp; then
    refresh_path
    if omp_healthy; then
      log_provider "provider=homebrew version=$(omp --version 2>/dev/null | head -n1 || echo ok)"
      exit 0
    fi
  fi
fi

if command -v curl >/dev/null 2>&1; then
  log_provider "provider=curl url=$OMP_INSTALL_OFFICIAL_URL"
  # Avoid `curl | sh` masking curl failures (no pipefail in POSIX sh).
  _curl_script="$(mktemp "${TMPDIR:-/tmp}/omp-install.XXXXXX")"
  if curl -fsSL "$OMP_INSTALL_OFFICIAL_URL" -o "$_curl_script" \
    && [ -s "$_curl_script" ] \
    && sh "$_curl_script"
  then
    rm -f "$_curl_script"
    refresh_path
    if omp_healthy; then
      log_provider "provider=curl version=$(omp --version 2>/dev/null | head -n1 || echo ok)"
      exit 0
    fi
  else
    rm -f "$_curl_script"
  fi
fi

log_provider "provider=none error=omp install failed"
exit 1
