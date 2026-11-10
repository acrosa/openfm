#!/bin/sh
# Builds OpenFM for the simulator and prints only errors, warnings and the result.
#   Tools/build.sh [build|test] ["simulator name"]
# If a name matches several simulators, xcodebuild refuses it: pass the full
# destination instead, e.g. OPENFM_DESTINATION="id=<UDID>" Tools/build.sh
cd "$(dirname "$0")/.." || exit 1
ACTION="${1:-build}"
DEVICE="${2:-iPad Pro 11-inch (M5)}"
xcodebuild -project OpenFM.xcodeproj -scheme OpenFM \
  -destination "${OPENFM_DESTINATION:-platform=iOS Simulator,name=$DEVICE}" \
  -derivedDataPath build "$ACTION" 2>&1 |
  grep -E "^/.*: (error|warning):|^(error|ld|clang|xcodebuild): |Undefined symbol|\*\* |Test Suite 'All tests'|Executed [0-9]+ tests|: error: -\[|failed \(" |
  grep -v "OpenFMEngine/msfa/" | sort -u | cut -c1-400
