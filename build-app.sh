#!/bin/bash
# Build the MiniTG iOS app from Swift sources using the prebuilt TDLibFramework
# (Swiftgram TDLib XCFramework, min iOS 12) and package an unsigned IPA.
# Fast: no TDLib compilation, just download + swiftc + package.
set -euo pipefail

APP_NAME="MiniTG"
ROOT="$PWD"
APP_DIR="$ROOT/app"
WORK="$ROOT/build"
FW_URL="https://github.com/Swiftgram/TDLibFramework/releases/download/1.8.68-c15d3f5a/TDLibFramework.zip"
FW_ZIP="$ROOT/third-party/TDLibFramework.zip"

mkdir -p "$ROOT/third-party" "$WORK"

echo "==> Fetching prebuilt TDLibFramework (cached between runs)"
if [ ! -f "$FW_ZIP" ]; then
  curl -L --retry 3 -o "$FW_ZIP" "$FW_URL"
fi

echo "==> Extracting xcframework"
rm -rf "$ROOT/third-party/TDLibFramework.xcframework"
cd "$ROOT/third-party"
unzip -q -o "$(basename "$FW_ZIP")"
cd "$ROOT"

FW_PATH=$(find "$ROOT/third-party" -path "*ios-arm64/TDLibFramework.framework" | head -1)
if [ -z "$FW_PATH" ]; then
  # fallback: exclude simulator slices explicitly
  FW_PATH=$(find "$ROOT/third-party" -name "TDLibFramework.framework" | grep -v -E "simulator|catalyst|maccatalyst" | head -1)
fi
if [ -z "$FW_PATH" ]; then
  echo "ERROR: TDLibFramework.framework (device slice) not found" >&2
  find "$ROOT/third-party" -maxdepth 3 -name "*.framework" >&2
  exit 1
fi
echo "   framework: $FW_PATH"
FW_DIR=$(dirname "$FW_PATH")

echo "==> Compiling Swift sources (arm64, iOS 12.0)"
# TDLibFramework is a STATIC library — linked into our binary, not embedded
rm -rf "$WORK/$APP_NAME.app"
mkdir -p "$WORK/$APP_NAME.app"

xcrun -sdk iphoneos swiftc \
  -target arm64-apple-ios12.0 \
  -O -whole-module-optimization \
  -sdk "$(xcrun -sdk iphoneos -show-sdk-path)" \
  -import-objc-header "$APP_DIR/TD-Bridge.h" \
  -F "$FW_DIR" \
  -framework TDLibFramework \
  -lz -lc++ \
  $(find "$APP_DIR/Sources" -name "*.swift") \
  -o "$WORK/$APP_NAME.app/$APP_NAME"

echo "==> Assembling bundle"
cp "$APP_DIR/Info.plist" "$WORK/$APP_NAME.app/Info.plist"
cp "$APP_DIR/LaunchScreen.storyboard" "$WORK/$APP_NAME.app/LaunchScreen.storyboard"

echo "==> Ad-hoc signing"
cat > "$WORK/ent.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>*.com.mini.tg.app</string>
	<key>get-task-allow</key>
	<true/>
</dict>
</plist>
EOF
codesign --force --sign - --entitlements "$WORK/ent.plist" "$WORK/$APP_NAME.app" || \
  echo "codesign failed (continuing, Sideloadly will sign)"

echo "==> Packaging IPA"
mkdir -p "$WORK/Payload"
cp -R "$WORK/$APP_NAME.app" "$WORK/Payload/"
cd "$WORK"
python3 - <<'PY'
import zipfile, os
with zipfile.ZipFile('MiniTG.ipa', 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('Payload'):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, p)
print('ipa done')
PY

cp "$WORK/MiniTG.ipa" "$ROOT/MiniTG.ipa"
echo "==> DONE: $ROOT/MiniTG.ipa"
ls -lh "$ROOT/MiniTG.ipa"
