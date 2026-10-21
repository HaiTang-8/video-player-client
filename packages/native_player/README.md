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
