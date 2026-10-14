#!/bin/bash
# Build TDLib (tdjson) for iOS arm64, deployment target iOS 12.0
# Runs on GitHub Actions macos-14 (has brew, cmake via brew install)
set -euo pipefail

TD_DIR="$PWD/third-party/td"
OUT="$PWD/third-party/tdlib-ios"
CPU_COUNT=$(sysctl -n hw.ncpu)

echo "==> Installing dependencies"
brew install cmake ninja php gperf || true

echo "==> Cloning TDLib"
if [ ! -d "$TD_DIR" ]; then
  git clone --depth 1 https://github.com/tdlib/td.git "$TD_DIR"
fi
cd "$TD_DIR"

echo "==> Building OpenSSL for iOS arm64"
OPENSSL_DIR="$TD_DIR/example/ios/openssl"
if [ ! -d "$OPENSSL_DIR" ]; then
  cd example/ios
  ./build-openssl.sh
  cd "$TD_DIR"
fi

echo "==> Configuring TDLib (arm64, iOS 12.0, static tdjson)"
rm -rf build-ios
mkdir -p build-ios
cd build-ios

export OPENSSL_ROOT_DIR="$OPENSSL_DIR"

cmake -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_C_FLAGS="-miphoneos-version-min=12.0" \
  -DCMAKE_CXX_FLAGS="-miphoneos-version-min=12.0" \
  -DCMAKE_OBJC_FLAGS="-miphoneos-version-min=12.0" \
  -DCMAKE_OBJCXX_FLAGS="-miphoneos-version-min=12.0" \
  -DCMAKE_INSTALL_PREFIX:PATH="$OUT" \
  -DTD_ENABLE_JNI=OFF \
  -DTD_ENABLE_DOTNET=OFF \
  -DTD_ENABLE_JSON=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_CXX_FLAGS_EXTRA="-Ofast" \
  ..

cmake --build . --target tdjson -- -j "$CPU_COUNT"
cmake --build . --target tdjson_static -- -j "$CPU_COUNT" || true
cmake --install .

echo "==> TDLib built. Artifacts:"
find "$OUT" -name "*.a" -o -name "*.dylib" -o -name "td_json_client.h" | head -20
