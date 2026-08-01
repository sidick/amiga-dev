#!/bin/sh
# Installs Copperline into /opt/copperline, preserving the bin/+share/
# layout its own romsearch.rs looks for relative to the executable (the
# same layout the upstream Homebrew formula and AppImage both use), so no
# COPPERLINE_AROS_DIR override is needed downstream.
#
# amd64: the upstream prebuilt AppImage is extracted directly (fast, no
# Rust toolchain needed). arm64: no Linux aarch64 asset is published
# upstream, so the release tag is built from source instead (see
# docs/phase0-decisions.md, "Resolve Copperline arm64").
set -eu

version="${COPPERLINE_VERSION:?COPPERLINE_VERSION must be set}"
arch="${1:?usage: install-copperline.sh <amd64|arm64>}"

install -d /opt/copperline/bin /opt/copperline/share/copperline

case "$arch" in
  amd64)
    workdir="$(mktemp -d)"
    cd "$workdir"
    curl -fsSL -o copperline.AppImage \
      "https://github.com/CopperlineHQ/Copperline/releases/download/v${version}/Copperline-${version}-x86_64.AppImage"
    chmod +x copperline.AppImage
    ./copperline.AppImage --appimage-extract >/dev/null
    cp squashfs-root/usr/bin/copperline /opt/copperline/bin/copperline
    cp -r squashfs-root/usr/share/copperline/aros /opt/copperline/share/copperline/aros
    cd /
    rm -rf "$workdir"
    ;;
  arm64)
    workdir="$(mktemp -d)"
    git clone --branch "v${version}" --depth 1 \
      https://github.com/CopperlineHQ/Copperline.git "$workdir"
    cd "$workdir"
    cargo build --release --bin copperline
    cp target/release/copperline /opt/copperline/bin/copperline
    cp -r assets/aros /opt/copperline/share/copperline/aros
    cd /
    rm -rf "$workdir"
    ;;
  *)
    echo "install-copperline.sh: unknown arch '$arch' (want amd64 or arm64)" >&2
    exit 1
    ;;
esac

chmod +x /opt/copperline/bin/copperline
