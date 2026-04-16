#!/usr/bin/env bash

set -euo pipefail

echo "==> cabal build"
cabal build

echo "==> cabal test"
cabal test

if command -v node >/dev/null 2>&1; then
  echo "==> node --check static/app.js"
  node --check static/app.js
fi
