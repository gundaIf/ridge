#!/bin/zsh
# Builds Ridge.app (menu bar only, no Dock icon) next to this script.
set -e
cd "${0:A:h}"
VERSION=1.0.0
swift build -c release --build-system native --arch arm64
# Universal binary (Apple Silicon + Intel). Falls back to Apple Silicon only if the Intel build fails.
BIN=.build/arm64-apple-macosx/release/Ridge
if swift build -c release --build-system native --arch x86_64 >/dev/null 2>&1; then
  mkdir -p .build/universal
  lipo -create .build/arm64-apple-macosx/release/Ridge .build/x86_64-apple-macosx/release/Ridge -output .build/universal/Ridge
  BIN=.build/universal/Ridge
else
  echo "note: Intel build failed; this build runs on Apple Silicon only"
fi
APP=Ridge.app

# App icon: render the artwork, then pack every size macOS asks for.
ICONWORK=$(mktemp -d)
./.build/arm64-apple-macosx/release/Ridge --icon $ICONWORK/AppIcon.png
if [[ -f $ICONWORK/AppIcon.png ]]; then
  SET=$ICONWORK/AppIcon.iconset; mkdir -p $SET
  for s in 16 32 128 256 512; do
    sips -z $s $s $ICONWORK/AppIcon.png --out $SET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) $ICONWORK/AppIcon.png --out $SET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $SET -o $ICONWORK/AppIcon.icns
fi

rm -rf "${APP:?}"
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN $APP/Contents/MacOS/
[[ -f $ICONWORK/AppIcon.icns ]] && cp $ICONWORK/AppIcon.icns $APP/Contents/Resources/
rm -rf "${ICONWORK:?}"
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Ridge</string>
  <key>CFBundleDisplayName</key><string>Ridge</string>
  <key>CFBundleIdentifier</key><string>io.github.gundaif.ridge</string>
  <key>CFBundleExecutable</key><string>Ridge</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Ad-hoc signature with a designated requirement naming only the bundle id, so the
# Accessibility grant carries over to new builds instead of resetting every time.
codesign --force --sign - -r='designated => identifier "io.github.gundaif.ridge"' $APP
echo "Built $PWD/$APP"

# ./build.sh --zip also packs a release archive.
if [[ "$1" == "--zip" ]]; then
  rm -f Ridge-$VERSION.zip
  ditto -c -k --keepParent $APP Ridge-$VERSION.zip
  echo "Packed $PWD/Ridge-$VERSION.zip"
fi
