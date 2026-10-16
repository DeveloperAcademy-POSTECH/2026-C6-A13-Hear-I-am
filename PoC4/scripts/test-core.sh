#!/bin/bash
set -euo pipefail
poc_root="$(cd "$(dirname "$0")/.." && pwd)"
xcrun swift test --package-path "$poc_root/Packages/PoC4Core" "$@"
