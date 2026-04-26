#!/usr/bin/env bash

# Unified local verification entrypoint used by both developers and CI.
#
# The script prefers a throwaway Cabal home under /tmp when it already has a
# package index, but it falls back to the user's normal Cabal home when /tmp is
# empty. That keeps sandboxed runs tidy without breaking local verification on a
# fresh machine.

set -euo pipefail

default_cabal_dir="/tmp/cabal"
default_xdg_cache_home="/tmp/xdg"

if [[ ! -e "${default_cabal_dir}/packages/hackage.haskell.org/01-index.cache" && -e "${HOME}/.cabal/packages/hackage.haskell.org/01-index.cache" ]]; then
  default_cabal_dir="${HOME}/.cabal"
  default_xdg_cache_home="${HOME}/.cache"
fi

CABAL_DIR="${CABAL_DIR:-${default_cabal_dir}}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${default_xdg_cache_home}}"
CABAL_STORE_DIR="${CABAL_STORE_DIR:-${CABAL_DIR}/store}"

echo "==> cabal build"
env CABAL_DIR="${CABAL_DIR}" XDG_CACHE_HOME="${XDG_CACHE_HOME}" cabal --store-dir="${CABAL_STORE_DIR}" build

echo "==> cabal test"
env CABAL_DIR="${CABAL_DIR}" XDG_CACHE_HOME="${XDG_CACHE_HOME}" cabal --store-dir="${CABAL_STORE_DIR}" test

if command -v node >/dev/null 2>&1; then
  echo "==> node --check static/app-render.js"
  node --check static/app-render.js
  echo "==> node --check static/app.js"
  node --check static/app.js
  echo "==> node --check static/report.js"
  node --check static/report.js
fi
