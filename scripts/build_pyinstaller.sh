#!/usr/bin/env bash
# onedir（见 packaging/pfc.spec）。macOS 不打 .app。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -m pip install -U pip
python3 -m pip install ".[build]"
python3 -m PyInstaller --noconfirm --clean packaging/pfc.spec

echo "产物目录: $ROOT/dist/PFC"
