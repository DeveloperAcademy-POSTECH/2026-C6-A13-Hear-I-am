#!/bin/bash
set -euo pipefail
poc_root="$(cd "$(dirname "$0")/.." && pwd)"
poc_temp="$(mktemp -d /tmp/poc3-tests.XXXXXX)"
trap 'rm -rf "$poc_temp"' EXIT
xcrun swiftc -module-cache-path "$poc_temp/module-cache" \
  "$poc_root/PoC3/StageMap/PlanTransform.swift" \
  "$poc_root/PoC3/StageMap/StageGeometry.swift" \
  "$poc_root/PoC3/StageMap/StageOverlayMath.swift" \
  "$poc_root/PoC3/PeopleTracking/PeopleTrackingMath.swift" \
  "$poc_root/PoC3/Guidance/GuidanceCore.swift" \
  "$poc_root/PoC3/Guidance/AudioOutputPolicy.swift" \
  "$poc_root/PoC3/Guidance/BodyNavigationCore.swift" \
  "$poc_root/Tests/BodyNavigationTests.swift" -o "$poc_temp/body-tests"
"$poc_temp/body-tests"
