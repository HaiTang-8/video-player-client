# native_player

播放内核的原生实现，由 App 的 `lib/playback/engines/native/` 通过 Pigeon 契约驱动。设计和阶段计划见 `client/doc/playback_engine_plan.md`。

- `pigeons/native_player_api.dart`：Dart 与原生之间唯一的契约
- `lib/src/generated/`、`darwin/native_player/Sources/native_player/*.g.swift`：Pigeon 生成，禁止手改
- `darwin/native_player/`：iOS / macOS 共用源码，以 Swift Package Manager 集成（App 在 pubspec 中开启了 `enable-swift-package-manager`）

修改契约后重新生成：

```bash
cd client/packages/native_player
dart run pigeon --input pigeons/native_player_api.dart
```

pigeon 固定为 27.3.0：更高版本需要 Dart 3.11，而项目固定的 Flutter 3.38.5 自带 Dart 3.10。

## Android：FFmpeg 音频扩展

`android/maven/` 是预编译的 Media3 FFmpeg 音频扩展（本地 Maven 仓库，坐标 `com.mediaserver.media3:decoder-ffmpeg`），系统没有对应解码器时用来解码 AC3、E-AC3、DTS、TrueHD。

- 来源：Media3 `libraries/decoder_ffmpeg`（Apache-2.0）+ FFmpeg `n6.0.1`，按 Media3 的 `build_ffmpeg.sh` 静态链接进 `libffmpegJNI.so`
- 许可证：FFmpeg 为 **LGPL 2.1+**（未开启 `--enable-gpl` / `--enable-nonfree`，构建脚本会校验）；源码见 <https://github.com/FFmpeg/FFmpeg/tree/n6.0.1>
- 版本必须与 `android/build.gradle.kts` 中的 Media3 版本一致，升级 Media3 时修改脚本里的 `MEDIA3_VERSION` 后重新构建并提交产物

重新构建（macOS / Linux，需要 Android SDK 中的 NDK 27.0.12077973 和 CMake）：

```bash
cd client/packages/native_player/android
./tool/build_ffmpeg_extension.sh
```
