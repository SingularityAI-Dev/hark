#!/bin/bash
# Builds dist/hark.exe (64-bit Windows) from this Mac with the polish server baked in.
# The URL comes from HARK_POLISH_URL (the Cloudflare tunnel address) and the key from the
# login keychain entry hark uses, so the key is never typed, printed or written to disk.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
: "${HARK_POLISH_URL:?set HARK_POLISH_URL to the tunnel address, e.g. https://hark.example.com/v1}"
HARK_POLISH_KEY="$(security find-generic-password -s dev.hark.app -a polish-server-key -w)"
export HARK_POLISH_KEY
export HARK_POLISH_MODEL="${HARK_POLISH_MODEL:-auto}"
cargo build --release --target x86_64-pc-windows-gnu
mkdir -p dist
cp target/x86_64-pc-windows-gnu/release/hark.exe dist/hark.exe
ls -l dist/hark.exe
