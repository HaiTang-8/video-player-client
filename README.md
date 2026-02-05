# Media Player（Flutter 客户端）

本项目是 `backend`（Media Server）的 Flutter 客户端，用于浏览媒体库、管理存储源、在线播放电影/剧集。

## 支持平台

- macOS
- Windows
- iOS
- Android

## 功能概览

- 海报墙 / 分类 / 搜索
- 电影 / 剧集详情与播放（支持多播放源）
- 观看历史（继续播放、最近观看）
- 存储源管理：WebDAV / 本地目录（由后端支持），支持扫描进度与任务管理
- 元数据刮削：TMDB / IMDb(OMDb)（由后端支持）
- 图片代理：对 TMDB 图片自动走后端代理，减少客户端直连失败
- 数据库备份/回滚、字幕列表（后端启用后可用）
- 离线下载：集成 aria2，支持后台下载与任务管理
- 外挂字幕：自动加载同目录下的外挂字幕文件
- 自动更新：macOS 支持 Sparkle 自动更新
- 桌面端平滑滚动体验

## 技术栈

| 类别 | 依赖 |
|------|------|
| 状态管理 | flutter_riverpod |
| 视频播放 | media_kit |
| UI 组件 | shadcn_flutter |
| 网络请求 | dio |
| 路由 | go_router |
| 离线下载 | aria2 |

## 依赖

- Flutter（Dart >= 3.7，见 `pubspec.yaml`）
- 后端服务：`../backend`（默认监听 `http://localhost:8080`）

## 快速开始

### 1) 启动后端

参考 `../backend/README.md` 完整说明。快速启动示例：

```bash
cd ../backend
cp config.example.yaml config.yaml
# 编辑 config.yaml：至少配置 storage，以及 tmdb.api_key（用于元数据/海报）
make dev
```

启动后可访问：

- Swagger：`http://localhost:8080/swagger/index.html`
- Health：`http://localhost:8080/health`

### 2) 运行客户端

```bash
flutter pub get
flutter run
```

### 3) 配置服务器地址

在 App 内「设置 / 服务器」中填写后端 Base URL（需要包含协议和端口）。

常见填写示例：

| 场景 | Base URL 示例 |
|------|--------------|
| iOS Simulator / macOS / Windows（后端在本机） | `http://localhost:8080` |
| Android Emulator（后端在本机） | `http://10.0.2.2:8080` |
| 真机（后端在同一局域网的电脑） | `http://192.168.1.100:8080` |

## 常见问题

### 连接失败

1. 在浏览器打开 `http://<server>/health`，确认后端可达
2. 确认手机/模拟器与后端在同一网络（或端口已正确映射）

### 没有媒体内容

需要先在客户端添加存储源并启动扫描；扫描完成后才会出现在海报墙/列表中。
