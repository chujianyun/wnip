#!/bin/bash
# Build signed, architecture-specific drag-to-install DMGs.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:-0.1.0}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Usage: bash scripts/package-release.sh MAJOR.MINOR.PATCH' >&2
  exit 1
fi
identity="${WNIP_SIGNING_IDENTITY:-$(awk '$1 == "CODE_SIGN_IDENTITY:" { print $2 }' project.yml)}"
if [[ ! "$identity" =~ ^[A-Fa-f0-9]{40}$ ]] || \
   ! security find-identity -v -p codesigning | grep -Fiq " $identity "; then
  echo 'Set WNIP_SIGNING_IDENTITY to the SHA-1 of an available signing certificate.' >&2
  exit 1
fi
for arch in arm64 x86_64; do
  if [[ -e "dist/Wnip-$version-macOS-$arch.dmg" ]]; then
    echo "Release artifact already exists for $arch; move it before rebuilding." >&2
    exit 1
  fi
done
xcodegen generate
mkdir -p dist
staging="$(mktemp -d "${TMPDIR:-/tmp}/wnip-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
for arch in arm64 x86_64; do
  derived="DerivedData/Release-$arch"
  xcodebuild build -quiet -project Wnip.xcodeproj -scheme Wnip \
    -configuration Release -destination "generic/platform=macOS" \
    -derivedDataPath "$derived" ARCHS="$arch" ONLY_ACTIVE_ARCH=YES \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION=1 \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity"
  product="$derived/Build/Products/Release/Wnip.app"
  codesign --verify --deep --strict "$product"
  codesign --verify -R="identifier \"com.wnip.app\" and anchor apple generic and certificate leaf = H\"$identity\"" "$product"
  actual_arch="$(lipo -archs "$product/Contents/MacOS/Wnip")"
  [[ "$actual_arch" = "$arch" ]] || { echo "Unexpected architecture: $actual_arch" >&2; exit 1; }
  mkdir "$staging/$arch"
  ditto "$product" "$staging/$arch/Wnip.app"
  ln -s /Applications "$staging/$arch/Applications"
  cat > "$staging/$arch/安装说明.txt" <<'EOF'
Wnip — macOS 15.0+

退出正在运行的 Wnip，将 Wnip.app 拖入 Applications 文件夹，完整替换旧版本。
请从 /Applications/Wnip.app 启动，不要直接运行磁盘映像中的副本。
首次截图需在系统设置中授予屏幕录制权限。

此包使用开发证书签名，未经 Apple 公证。
EOF
  image="dist/Wnip-$version-macOS-$arch.dmg"
  hdiutil create -volname "Wnip $version $arch" -srcfolder "$staging/$arch" \
    -format UDZO "$image"
  hdiutil verify "$image"
done
(cd dist && shasum -a 256 "Wnip-$version-macOS-arm64.dmg" \
  "Wnip-$version-macOS-x86_64.dmg" > "Wnip-$version-SHA256SUMS.txt")
echo "Release DMGs and checksums are ready in $PWD/dist"
