# native_player

播放内核的原生实现，由 App 的 `lib/playback/engines/native/` 通过 Pigeon 契约驱动。设计和阶段计划见 `client/doc/playback_engine_plan.md`。

- `pigeons/native_player_api.dart`：Dart 与原生之间唯一的契约
- `lib/src/generated/`、`darwin/native_player/Sources/native_player/*.g.swift`：Pigeon 生成，禁止手改
- `darwin/native_player/`：iOS / macOS 共用源码，以 Swift Package Manager 集成（App 在 pubspec 中开启了 `enable-swift-package-manager`）

修改契约后重新生成：

```bash
cd client/packages/native_player
dart run pigeon --input pigeons/native_player_api.dart
dart format lib/src/generated
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

## Android：杜比视界 P5 的 GPU 重建

没有杜比视界解码器（或片源没有在封装里声明杜比视界）时，P5 由 `dovi/DoviGlRenderer` 在 GPU 上按逐帧 RPU 重建颜色，以 HDR10（BT.2020 PQ + 静态元数据）送显。设备不支持所需的 EGL / GLES 扩展时回退到 mpv。

- `rust/dovi_jni`：用 [libdovi](https://github.com/quietvoid/dovi_tool)（`dolby_vision` crate，MIT）解析 RPU 并转成着色器参数，`src/main/jniLibs/<abi>/libdovi_jni.so` 为预编译产物（arm64-v8a、armeabi-v7a、x86_64，16 KB 页对齐）
- 依赖许可证：均为 MIT / Apache-2.0 / Unlicense / Zlib 等宽松许可证，链接进产物的没有 GPL / LGPL 组件
- 修改 Rust 代码或升级依赖后重新构建并提交产物（Rust 版本由 `rust-toolchain.toml` 固定）：

```bash
cd client/packages/native_player/android
./tool/build_dovi_jni.sh
```

- 单元测试（宿主机运行，用真实 RPU 与 FFmpeg 的解码结果对照）：

```bash
cd client/packages/native_player/android/rust/dovi_jni
cargo test
```

- 调试属性（`adb shell setprop`）：`debug.nativeplayer.dovi.log=1` 每 5 秒输出帧统计；`debug.nativeplayer.dovi.dump=<显示时间微秒>` 读回该帧的 PQ 网格；`debug.nativeplayer.dovi.mmr=1` 把多项式改成等价的 MMR 上传，用来验证着色器的 MMR 分支。手动诊断用 `integration_test/dolby_vision_probe_test.dart`

## Android：ASS 字幕（libass）

ASS / SSA 由 libass 渲染（行内样式、特效、卡拉 OK、MKV 内嵌字体），其余字幕仍由 Media3 的 `SubtitleView` 显示；PGS 使用插件自己的 `PgsSubtitleParser`（一个显示集多个对象）。

- 来源：[peerless2012/libass-android](https://github.com/peerless2012/libass-android) 的 `ass-media` / `ass-kt` 0.5.1（MIT），按 Media3 1.8.0 构建，在本插件的 Media3 1.10.1 下验证可用；升级 Media3 时要回归 ASS（`AssMatroskaExtractor` 通过反射读取 `MatroskaExtractor` 的私有字段）
- `libass.so` 静态链接了 libass（ISC）、freetype（FTL）、harfbuzz（MIT）、fribidi（LGPL 2.1+）、libunibreak（zlib）、fontconfig、expat（MIT）、libpng；没有 GPL 组件。字体走 fontconfig 的系统字体（`sans-serif`）
- 渲染方式 `OVERLAY_OPEN_GL`：叠加层放在 `SubtitleView` 内，不阻塞 UI 线程，不影响 HDR / 杜比视界送显
- 接入时对库做了三处处理（`Media3PlayerBackend`）：
  - `PgsSubtitleParserFactory` 包在 `AssSubtitleParserFactory` 外面，MKV 改用 `AssExtractorsFactory`，否则库会把 PGS 交回 Media3 默认解析器
  - 杜比视界 GPU 重建时播放器报告的 Surface 尺寸无效（-1），改按 SurfaceView 的尺寸设置 libass 帧大小
  - 叠加层只随播放推进重画：暂停时切换字幕或 seek 后手动重画一次；切换字幕轨时改动一次帧尺寸，避免 libass 认为“没有变化”而不重画
