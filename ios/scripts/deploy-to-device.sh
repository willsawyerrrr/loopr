#!/usr/bin/env bash
# Builds Loopr from the up-to-date `main` worktree and installs it on the paired iPhone,
# without opening Xcode. Skips unless `main` has new commits or the last install is older
# than `LOOPR_MAX_AGE_DAYS` (a free team's install expires after 7 days). `--force` always installs.
set -euo pipefail

MAX_AGE_DAYS="${LOOPR_MAX_AGE_DAYS:-5}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/loopr"
STATE_FILE="$STATE_DIR/last-deploy"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && git rev-parse --show-toplevel)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

git -C "$REPO" pull --ff-only --quiet
sha="$(git -C "$REPO" rev-parse HEAD)"
now="$(date +%s)"
mkdir -p "$STATE_DIR"
read -r last_sha last_time < "$STATE_FILE" 2>/dev/null || { last_sha=""; last_time=0; }

if [[ "${1:-}" != "--force" && "$sha" == "$last_sha" && $((now - last_time)) -lt $((MAX_AGE_DAYS * 86400)) ]]; then
  echo "Up to date ($sha)"
  exit 0
fi

device="${LOOPR_DEVICE:-$(xcrun devicectl list devices --json-output /dev/stdout --quiet 2>/dev/null | python3 -c '
import json, sys
for d in json.load(sys.stdin)["result"]["devices"]:
    if d["hardwareProperties"].get("reality") == "physical" and d["hardwareProperties"].get("platform") == "iOS":
        print(d["identifier"])
        break
')}"
[[ -n "$device" ]] || { echo "No paired iPhone found" >&2; exit 1; }

cd "$REPO/ios"
xcodegen generate --quiet
xcodebuild -project Loopr.xcodeproj -scheme Loopr -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates -quiet build
xcrun devicectl device install app --device "$device" build/Build/Products/Debug-iphoneos/Loopr.app

echo "$sha $now" > "$STATE_FILE"
echo "Installed $sha"
