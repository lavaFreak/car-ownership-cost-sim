#!/usr/bin/env bash

# Unified local verification entrypoint used by both developers and CI.
#
# The script keeps Cabal's writable state under /tmp by default so it behaves
# well in sandboxed environments.

set -euo pipefail

CABAL_DIR="${CABAL_DIR:-/tmp/cabal}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/xdg}"
CABAL_STORE_DIR="${CABAL_STORE_DIR:-${CABAL_DIR}/store}"

echo "==> cabal build"
env CABAL_DIR="${CABAL_DIR}" XDG_CACHE_HOME="${XDG_CACHE_HOME}" cabal --store-dir="${CABAL_STORE_DIR}" build

echo "==> cabal test"
env CABAL_DIR="${CABAL_DIR}" XDG_CACHE_HOME="${XDG_CACHE_HOME}" cabal --store-dir="${CABAL_STORE_DIR}" test

if command -v node >/dev/null 2>&1; then
  echo "==> node --check static/app.js"
  node --check static/app.js
fi
