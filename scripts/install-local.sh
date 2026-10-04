#!/bin/bash
# Build with the configured development identity and install the signed bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
identity="$(awk '$1 == "CODE_SIGN_IDENTITY:" { print $2 }' project.yml)"
if [[ ! "$identity" =~ ^[A-F0-9]{40}$ ]]; then
  echo 'project.yml must pin exactly one signing certificate SHA-1.' >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -Fq " $identity "; then
  echo "Required signing identity $identity is unavailable; no fallback is allowed." >&2
  exit 1
fi
requirement="identifier \"com.wnip.app\" and anchor apple generic and certificate leaf = H\"$identity\""
xcodegen generate
xcodebuild build -quiet -project Wnip.xcodeproj -scheme Wnip \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=YES
product="$PWD/DerivedData/Build/Products/Release/Wnip.app"
registration='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
codesign --verify --deep --strict "$product"
# Reject ad-hoc/linker signing before stopping or replacing the installed app.
codesign --verify -R="$requirement" "$product"
# Unregister other copies, including build products, so LaunchServices only
# routes application launches to the canonical installation.
while IFS= read -r registered_app; do
  [ "$registered_app" = /Applications/Wnip.app ] || "$registration" -u "$registered_app"
done < <("$registration" -dump | sed -nE 's/^path: +(.+\/Wnip\.app) \(0x[[:xdigit:]]+\)$/\1/p')
while IFS= read -r process_id; do
  [ -z "$process_id" ] || kill "$process_id"
done < <(pgrep -x Wnip || true)
for attempt in {1..20}; do
  if ! pgrep -x Wnip >/dev/null; then break; fi
  sleep 0.25
done
if pgrep -x Wnip >/dev/null; then
  echo 'Wnip is still running; installation stopped.' >&2
  exit 1
fi
if [ -e /Applications/Wnip.app ]; then
  backup="$(mktemp -d "$HOME/.Trash/Wnip-update.XXXXXX")"
  "$registration" -u /Applications/Wnip.app
  mv /Applications/Wnip.app "$backup/Wnip.app"
  echo "Previous installation: $backup/Wnip.app"
fi
ditto "$product" /Applications/Wnip.app
codesign --verify --deep --strict /Applications/Wnip.app
codesign --verify -R="$requirement" /Applications/Wnip.app
cmp "$product/Contents/MacOS/Wnip" /Applications/Wnip.app/Contents/MacOS/Wnip
open /Applications/Wnip.app
for attempt in {1..20}; do
  if pgrep -f '^/Applications/Wnip.app/Contents/MacOS/Wnip$'; then exit 0; fi
  sleep 0.25
done
echo 'Installed Wnip did not start from /Applications.' >&2
exit 1
