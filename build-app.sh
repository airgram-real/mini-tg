#!/bin/bash
# Build the MiniTG iOS app from Swift sources and package an unsigned IPA.
# Requires: TDLib static tdjson already built at third-party/tdlib-ios
set -euo pipefail

APP_NAME="MiniTG"
BUNDLE_ID="com.mini.tg.app"
ROOT="$PWD"
APP_DIR="$ROOT/app"
LIB_DIR="$ROOT/third-party/tdlib-ios"
WORK="$ROOT/build"
CPU_COUNT=$(sysctl -n hw.ncpu)

rm -rf "$WORK"
mkdir -p "$WORK/$APP_NAME.app"

echo "==> Locating tdjson static library"
TDJSON_A=$(find "$LIB_DIR" -name "libtdjson.a" | head -1)
TDJSON_H=$(find "$LIB_DIR" -name "td_json_client.h" | head -1)
if [ -z "$TDJSON_A" ]; then
  # some builds install it as libtdjson_static.a
  TDJSON_A=$(find "$LIB_DIR" -name "libtdjson_static.a" | head -1)
fi
if [ -z "$TDJSON_A" ]; then
  echo "ERROR: libtdjson.a not found in $LIB_DIR" >&2
  find "$LIB_DIR" -name "*.a" >&2
  exit 1
fi
echo "   using: $TDJSON_A"
mkdir -p "$WORK/include"
cp "$TDJSON_H" "$WORK/include/td_json_client.h"

echo "==> Compiling Swift sources (arm64, iOS 12.0), linking static tdjson"
xcrun -sdk iphoneos swiftc \
  -target arm64-apple-ios12.0 \
  -O -whole-module-optimization \
  -sdk "$(xcrun -sdk iphoneos -show-sdk-path)" \
  -import-objc-header "$APP_DIR/TD-Bridge.h" \
  -I "$WORK/include" \
  "$TDJSON_A" \
  $(find "$APP_DIR/Sources" -name "*.swift") \
  -o "$WORK/$APP_NAME.app/$APP_NAME"

echo "==> Assembling bundle"
cp "$APP_DIR/Info.plist" "$WORK/$APP_NAME.app/Info.plist"
cp "$APP_DIR/LaunchScreen.storyboard" "$WORK/$APP_NAME.app/LaunchScreen.storyboard"

# Ad-hoc sign so that Sideloadly / ldid can re-sign cleanly
echo "==> Ad-hoc signing"
cat > "$WORK/ent.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>*.$BUNDLE_ID</string>
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
