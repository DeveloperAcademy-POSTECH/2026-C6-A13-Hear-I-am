#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
xcrun swift test --package-path "$project_root/Packages/HearIAmCore" "$@"
