#!/usr/bin/env bash
# Thin wrapper → tilix-cytracon.sh (all-in-one)
# Echo only the tarball path on the last line (for CI capture).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# Run package; tilix-cytracon logs to stdout — re-run capture via pkgpath
"$ROOT/tilix-cytracon.sh" package "$@"
PKG_DIR="${PKG_DIR:-/tmp}"
if [[ -f "${PKG_DIR}/tilix-cytracon-latest.pkgpath" ]]; then
  cat "${PKG_DIR}/tilix-cytracon-latest.pkgpath"
elif [[ -f "./tilix-cytracon-latest.pkgpath" ]]; then
  cat "./tilix-cytracon-latest.pkgpath"
fi
