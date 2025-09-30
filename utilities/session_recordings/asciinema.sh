#!/usr/bin/env bash
# asciinema installer/uninstaller (Linux + macOS)
# - Prefers official GitHub binary; falls back to pip
# - Linux: chooses gnu vs musl based on glibc
# - macOS: Rosetta-aware (installs native arm64 on Apple silicon)
set -euo pipefail

# ------------------ argument parsing ------------------
DEBUG_MODE=0
ACTION=""  # first non-flag becomes the action

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG_MODE=1 ;;
    -h|--help|help) ACTION="help" ;;
    install|uninstall|reinstall)
      if [[ -z "${ACTION:-}" || "${ACTION}" == "help" ]]; then ACTION="$arg"; fi
      ;;
    *)
      if [[ "$arg" == -* ]]; then
        echo "⚠️  Ignoring unknown option: $arg" >&2
      else
        if [[ -z "${ACTION:-}" || "${ACTION}" == "help" ]]; then ACTION="$arg"; fi
      fi
      ;;
  esac
done
ACTION="${ACTION:-install}"

# ------------------ debug setup ------------------
if [[ "${DEBUG_MODE}" -eq 1 || "${DEBUG:-0}" == "1" ]]; then
  export PS4='+ ${BASH_SOURCE:-$0}:${LINENO}:${FUNCNAME[0]:-main}: '
  set -x
fi

# ------------------ helpers ------------------
show_help() {
  cat <<'EOF'
Usage: ./asciinema.sh [install|uninstall|reinstall|help] [--debug]

Actions:
  install     Install the latest asciinema (default if no action given).
              • macOS: installs native arm64 on Apple silicon; x86_64 on Intel
              • Linux: prefers musl build if system glibc < 2.39; else gnu
              • Verifies the binary runs; falls back to pip if needed

  uninstall   Remove asciinema (binary or pip) and ~/.config/asciinema

  reinstall   Uninstall then install again (handy for upgrades)

  help        Show this help message

Options:
  --debug     Enable verbose tracing (or set DEBUG=1)

Examples:
  ./asciinema.sh                 # install
  ./asciinema.sh uninstall       # uninstall
  ./asciinema.sh reinstall       # uninstall + install
  DEBUG=1 ./asciinema.sh install # install with tracing
EOF
}

detect_arch() {
  local os="$1" uname_arch="$2" arch
  case "$uname_arch" in
    x86_64|amd64) arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
    *) echo "Unsupported architecture: $uname_arch" >&2; exit 1 ;;
  esac
  if [[ "$os" == "darwin" ]]; then
    if command -v sysctl >/dev/null 2>&1; then
      if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then
        if [[ "$uname_arch" == "x86_64" ]]; then
          echo "ℹ️ Apple silicon detected (Rosetta shell). Using native arm64 binary." >&2
          arch="aarch64"
        fi
      fi
    fi
  fi
  printf "%s" "$arch"
}

pick_linux_flavor() {
  # Decide gnu vs musl based on glibc version
  local want="gnu"
  if command -v ldd >/dev/null 2>&1; then
    local glibc
    glibc="$(ldd --version 2>&1 | awk 'NR==1{for(i=1;i<=NF;i++) if($i ~ /^([0-9]+\.)+[0-9]+$/){print $i; exit}}')"
    if [[ -n "$glibc" ]]; then
      if [[ "$(printf '%s\n%s\n' "$glibc" "2.39" | sort -V | head -n1)" != "2.39" ]]; then
        want="musl"   # glibc < 2.39 → pick musl
      fi
    else
      want="musl"
    fi
  else
    want="musl"
  fi
  printf "%s" "$want"
}

make_tmpdir() {
  local base="${TMPDIR:-/tmp}"
  local d
  d="$(mktemp -d "${base%/}/asciinema.XXXXXX")" || { echo "❌ could not create temp dir"; exit 1; }
  if ! touch "$d/.wtest" 2>/dev/null; then
    d="$(mktemp -d /var/tmp/asciinema.XXXXXX)" || { echo "❌ could not create temp dir (/var/tmp)"; exit 1; }
  fi
  rm -f "$d/.wtest"
  printf "%s" "$d"
}

fetch_latest_version() {
  local tmp json version
  tmp="$(make_tmpdir)"
  trap 'rm -rf "'"$tmp"'"' RETURN
  json="$tmp/latest.json"
  curl -fsSL https://api.github.com/repos/asciinema/asciinema/releases/latest -o "$json"
  version="$(awk -F'"' '/"tag_name":/ {print $4}' "$json" | head -n1)"
  if [[ -z "${version:-}" ]]; then
    echo "❌ Failed to parse latest version from GitHub API." >&2
    exit 1
  fi
  printf "%s" "$version"
}

pip_fallback() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user --upgrade asciinema
    local install_dir
    install_dir="$(python3 -m site --user-base)/bin"
    echo "🎉 Installed via pip."
    echo "👉 Ensure ${install_dir} is in your PATH (e.g., add: export PATH=\"${install_dir}:\$PATH\")"
    "${install_dir}/asciinema" --version || true
  else
    echo "❌ Python3 not found for pip fallback." >&2
    exit 1
  fi
}

install_asciinema() {
  local OS UNAME_ARCH ARCH LATEST_VERSION BIN FLAVOR URL TMP_DIR INSTALL_PATH
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  UNAME_ARCH="$(uname -m)"
  ARCH="$(detect_arch "$OS" "$UNAME_ARCH")"
  LATEST_VERSION="$(fetch_latest_version)"
  echo "➡️ Latest version: $LATEST_VERSION"

  if [[ "$OS" == "linux" ]]; then
    FLAVOR="$(pick_linux_flavor)" # gnu or musl
    BIN="asciinema-${ARCH}-unknown-linux-${FLAVOR}"
  elif [[ "$OS" == "darwin" ]]; then
    BI
