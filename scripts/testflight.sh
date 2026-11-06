#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
exec "$HOME/ios/release/testflight.sh" --project Pet.xcodeproj --scheme Pet "$@"
