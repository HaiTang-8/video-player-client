#!/usr/bin/env bash
# 构建 rust/dovi_jni（libdovi 解析杜比视界 RPU），输出到 src/main/jniLibs，产物需要提交。
# Rust 版本由 rust/dovi_jni/rust-toolchain.toml 固定，首次运行时 rustup 会自动安装工具链和目标。
set -euo pipefail

NDK_VERSION=27.0.12077973
ANDROID_API=24
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/rust/dovi_jni"
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
case "$(uname -s)" in
  Darwin) HOST=darwin-x86_64 ;;
  *) HOST=linux-x86_64 ;;
esac
BIN="$ANDROID_HOME/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/$HOST/bin"
# Android 15 起部分设备使用 16 KB 页
export RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384"

build() {
  local target="$1" abi="$2" clang="$3"
  local env_target
  env_target="$(echo "$target" | tr 'a-z-' 'A-Z_')"
  export "CARGO_TARGET_${env_target}_LINKER=$BIN/$clang"
  (cd "$CRATE" && cargo build --release --target "$target")
  mkdir -p "$ROOT/src/main/jniLibs/$abi"
  cp "$CRATE/target/$target/release/libdovi_jni.so" "$ROOT/src/main/jniLibs/$abi/"
  echo "$abi: $(wc -c < "$ROOT/src/main/jniLibs/$abi/libdovi_jni.so") bytes"
}

build aarch64-linux-android arm64-v8a "aarch64-linux-android${ANDROID_API}-clang"
build armv7-linux-androideabi armeabi-v7a "armv7a-linux-androideabi${ANDROID_API}-clang"
build x86_64-linux-android x86_64 "x86_64-linux-android${ANDROID_API}-clang"
