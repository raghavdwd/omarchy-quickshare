#!/usr/bin/env bash
# Install the Omarchy Quick Share plugin prerequisites and its BLE receiver.
# Review before running. Only the firewall rule needs a password.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/quickshare-backend"
BIN_DIR="$HOME/.local/bin"

echo "==> Bridge scripts"
chmod +x "$PLUGIN_DIR/bin/quickshare-bridge" "$PLUGIN_DIR/bin/quickshare-ask"

echo "==> Rust toolchain"
if ! command -v cargo >/dev/null 2>&1; then
  echo "Installing rustup (minimal profile) into your home directory..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
fi
export PATH="$HOME/.cargo/bin:$BIN_DIR:$PATH"

echo "==> protoc"
if ! command -v protoc >/dev/null 2>&1; then
  echo "Installing protoc into $BIN_DIR ..."
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/protoc.zip" \
    https://github.com/protocolbuffers/protobuf/releases/download/v29.3/protoc-29.3-linux-x86_64.zip
  unzip -oq "$tmp/protoc.zip" -d "$tmp"
  mkdir -p "$BIN_DIR"
  install -m755 "$tmp/bin/protoc" "$BIN_DIR/protoc"
  rm -rf "$tmp"
fi
export PROTOC="${PROTOC:-$(command -v protoc)}"

echo "==> Protocol library"
mkdir -p "$DATA_DIR"
if [[ ! -d "$DATA_DIR/oqs-core" ]]; then
  git clone --depth 1 https://github.com/ignotusbucius/open-quickshare.git "$DATA_DIR/open-quickshare"
  cp -a "$DATA_DIR/open-quickshare/core_lib" "$DATA_DIR/oqs-core"
fi

echo "==> Receiver binary"
mkdir -p "$DATA_DIR/bridge-rs/src"
cp "$PLUGIN_DIR/backend/Cargo.toml" "$DATA_DIR/bridge-rs/Cargo.toml"
cp "$PLUGIN_DIR/backend/src/main.rs" "$DATA_DIR/bridge-rs/src/main.rs"
( cd "$DATA_DIR/bridge-rs" && cargo build --release )
install -m755 "$DATA_DIR/bridge-rs/target/release/quickshare-rx" "$BIN_DIR/quickshare-rx"

echo "==> Local services"
sudo systemctl enable --now avahi-daemon.service bluetooth.service || true

echo "==> Firewall (needs your password)"
if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q 'Status: active'; then
  sudo ufw allow 53318/tcp comment quickshare || true
fi

echo
echo "Done. Plugin id: async.quickshare"
echo "Add { \"id\": \"async.quickshare\" } to bar.layout.right in ~/.config/omarchy/shell.json"
echo "Then run: omarchy restart shell"
