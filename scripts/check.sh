#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Use Foundry's standard compiler version resolver and the vendored official compiler.
export XDG_DATA_HOME="$PWD/toolchain"
forge build --offline
forge test --offline
forge fmt --check
