#!/usr/bin/env bash
# 构建 Media3 FFmpeg 音频扩展（LGPL 2.1+），输出到 ../maven 本地仓库。
# 升级 Media3 时修改 MEDIA3_VERSION（与 build.gradle.kts 保持一致）后重新运行并提交产物。
set -euo pipefail

MEDIA3_VERSION=1.10.1
FFMPEG_TAG=n6.0.1
DECODERS=(ac3 eac3 dca truehd)
ANDROID_ABI=24
NDK_VERSION=27.0.12077973
GROUP=com.mediaserver.media3
ARTIFACT=decoder-ffmpeg

export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
NDK_PATH="$ANDROID_HOME/ndk/$NDK_VERSION"
case "$(uname -s)" in
  Darwin) HOST_PLATFORM=darwin-x86_64 ;;
  *) HOST_PLATFORM=linux-x86_64 ;;
esac
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/maven/${GROUP//.//}/$ARTIFACT/$MEDIA3_VERSION"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

git clone --depth 1 --branch "$MEDIA3_VERSION" https://github.com/androidx/media.git "$WORK_DIR/media"
MODULE_DIR="$WORK_DIR/media/libraries/decoder_ffmpeg"
FFMPEG_MODULE_PATH="$MODULE_DIR/src/main"
git clone --depth 1 --branch "$FFMPEG_TAG" https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_MODULE_PATH/jni/ffmpeg"

(cd "$FFMPEG_MODULE_PATH/jni" &&
  ./build_ffmpeg.sh "$FFMPEG_MODULE_PATH" "$NDK_PATH" "$HOST_PLATFORM" "$ANDROID_ABI" "${DECODERS[@]}")
grep -q 'FFMPEG_LICENSE "LGPL version 2.1 or later"' "$FFMPEG_MODULE_PATH/jni/ffmpeg/config.h" ||
  { echo "FFmpeg 配置不是 LGPL 2.1+，已中止" >&2; exit 1; }

echo "android.ndkVersion = '$NDK_VERSION'" >> "$MODULE_DIR/build.gradle"
# 与 App 的 android/settings.gradle.kts 一致，优先走镜像
cat > "$WORK_DIR/mirror.gradle" <<'EOF'
allprojects {
    buildscript.repositories { maven { url 'https://mirrors.cloud.tencent.com/nexus/repository/maven-public/' } }
    repositories { maven { url 'https://mirrors.cloud.tencent.com/nexus/repository/maven-public/' } }
}
EOF
(cd "$WORK_DIR/media" &&
  ./gradlew --no-daemon --init-script "$WORK_DIR/mirror.gradle" :lib-decoder-ffmpeg:assembleRelease)

mkdir -p "$OUT_DIR"
cp "$(find "$MODULE_DIR" -name '*-release.aar' | head -1)" "$OUT_DIR/$ARTIFACT-$MEDIA3_VERSION.aar"
cat > "$OUT_DIR/$ARTIFACT-$MEDIA3_VERSION.pom" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>$GROUP</groupId>
  <artifactId>$ARTIFACT</artifactId>
  <version>$MEDIA3_VERSION</version>
  <packaging>aar</packaging>
  <description>Media3 $MEDIA3_VERSION decoder_ffmpeg, FFmpeg $FFMPEG_TAG (LGPL-2.1-or-later), decoders: ${DECODERS[*]}</description>
  <dependencies>
    <dependency>
      <groupId>androidx.media3</groupId>
      <artifactId>media3-decoder</artifactId>
      <version>$MEDIA3_VERSION</version>
      <scope>compile</scope>
    </dependency>
    <dependency>
      <groupId>androidx.media3</groupId>
      <artifactId>media3-exoplayer</artifactId>
      <version>$MEDIA3_VERSION</version>
      <scope>runtime</scope>
    </dependency>
  </dependencies>
</project>
EOF
echo "已输出到 $OUT_DIR"
