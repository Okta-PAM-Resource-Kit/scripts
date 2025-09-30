#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-install}"   # default to install if no arg provided

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
          echo "ℹ️ Apple silicon detected (Rosetta). Using native arm64 binary." >&2
          arch="aarch64"
        fi
      fi
    fi
  fi
  printf "%s" "$arch"
}

install_asciinema() {
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  UNAME_ARCH="$(uname -m)"
  ARCH="$(detect_arch "$OS" "$UNAME_ARCH")"

  LATEST_VERSION="$(curl -fsSL https://api.github.com/repos/asciinema/asciinema/releases/latest | awk -F'"' '/"tag_name":/ {print $4}')"

  if [[ -z "${LATEST_VERSION:-}" ]]; then
    echo "❌ Failed to fetch latest asciinema release." >&2
    exit 1
  fi
  echo "➡️ Latest version: $LATEST_VERSION"

  case "$OS" in
    darwin) BIN="asciinema-${ARCH}-apple-darwin" ;;
    linux)  BIN="asciinema-${ARCH}-unknown-linux-gnu" ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
  esac

  URL="https://github.com/asciinema/asciinema/releases/download/${LATEST_VERSION}/${BIN}"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  echo "➡️ Downloading $URL ..."
  if curl -fL "$URL" -o "$TMP_DIR/asciinema"; then
    chmod +x "$TMP_DIR/asciinema"
    echo "➡️ Installing to /usr/local/bin (requires sudo)..."
    sudo mv "$TMP_DIR/asciinema" /usr/local/bin/
    echo "🎉 Installed: $(/usr/local/bin/asciinema --version)"
    return 0
  else
    echo "⚠️ No prebuilt binary available for $OS-$ARCH. Falling back to pip..."
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user --upgrade asciinema
    INSTALL_DIR="$(python3 -m site --user-base)/bin"
    echo "🎉 Installed via pip. Ensure $INSTALL_DIR is in your PATH."
    "$INSTALL_DIR/asciinema" --version || true
  else
    echo "❌ Python3 not found. Please install Python3/pip, then re-run." >&2
    exit 1
  fi
}

uninstall_asciinema() {
  echo "➡️ Uninstalling asciinema..."

  if [[ -x /usr/local/bin/asciinema ]]; then
    echo "🗑 Removing binary from /usr/local/bin"
    sudo rm -f /usr/local/bin/asciinema
  fi

  if command -v python3 >/dev/null 2>&1 && python3 -m pip show asciinema >/dev/null 2>&1; then
    echo "🗑 Removing pip package"
    python3 -m pip uninstall -y asciinema
  fi

  if [[ -d "$HOME/.config/asciinema" ]]; then
    echo "🗑 Removing config at ~/.config/asciinema"
    rm -rf "$HOME/.config/asciinema"
  fi

  echo "🎉 Uninstallation complete."
}

show_help() {
  cat <<EOF
Usage: $0 [install|uninstall|help]

Actions:
  install    Install the latest asciinema (default if no action is given).
             Prefers GitHub prebuilt binary; falls back to pip if unavailable.

  uninstall  Remove asciinema (binary or pip install) and config files.

  help       Show this help message.

Examples:
  $0            # install latest asciinema
  $0 install    # same as above
  $0 uninstall  # remove asciinema
  $0 help       # show this help message
EOF
}

case "$ACTION" in
  install)   install_asciinema ;;
  uninstall) uninstall_asciinema ;;
  -h|--help|help) show_help ;;
  *)
    echo "❌ Unknown action: $ACTION"
    show_help
    exit 1
    ;;
esac
