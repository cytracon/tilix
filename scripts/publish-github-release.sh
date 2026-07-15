#!/usr/bin/env bash
# Thin wrapper → tilix-cytracon.sh (all-in-one)
exec "$(cd "$(dirname "$0")" && pwd)/tilix-cytracon.sh" publish "$@"
