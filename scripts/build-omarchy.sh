#!/usr/bin/env bash
# Native Omarchy / Arch build of Cytracon Tilix. No root required.
# Uses ~/.local/opt/ldc2 if present, otherwise ldc2/dub from PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -x "${HOME}/.local/opt/ldc2/bin/ldc2" ]]; then
  export PATH="${HOME}/.local/opt/ldc2/bin:${PATH}"
fi
command -v ldc2 >/dev/null || { echo "ldc2 missing. Install extra/ldc or unpack LDC to ~/.local/opt/ldc2" >&2; exit 2; }
command -v dub >/dev/null || { echo "dub missing." >&2; exit 2; }

echo "Compiler: $(ldc2 --version | head -1)"
dub build --compiler=ldc2 --build=release
install -Dm755 tilix "${TILIX_PREFIX:-$HOME/.local}/libexec/tilix"
echo "Built $(pwd)/tilix"
