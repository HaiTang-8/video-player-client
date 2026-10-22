# 播放缓存（续播秒开）技术预研

> 状态：预研完成；方案与实施进度以 `doc/playback_cache_plan.md` 为准
> 日期：2026-10-22
> 关联：`doc/playback_engine_plan.md`（实施时需同步更新其 §4 / §12）

## 1. 目标

1. 可设置缓存总大小（含关闭），并能查看占用、一键清理。
2. 打开上次没看完的视频时“秒开秒播”：尽量不等网络就出第一帧，并直接从续播点开始。
3. 覆盖全部内核：Aether（iOS / macOS）、Media3（Android）、mpv（Windows / Linux / Android 兜底）。

## 2. 现状：续播为什么慢

`PlaybackSession.load()` 的起播链路是串行的：

| # | 步骤 | 代码位置 | 开销 |
|---|---|---|---|
| 1 | 请求流地址 API | `PlaybackSourceResolver.resolve` → `fetchStreamInfo` | 1 次往返 |
| 2 | HEAD 解析 302 | `_resolveRedirect` | 1 次往返；302 模式下服务端还要去网盘取直链 |
| 3 | 引擎从 0 开始打开、探测封装 | `engine.open(source)` | MKV 要读头部和末尾的 Cues，MP4 可能要读末尾的 moov，每次都是对源站的 Range 请求 |
| 4 | 先从 0 播放一小段 | — | 下载了用不上的数据 |
| 5 | 时长就绪后才 seek 到续播点 | `PlaybackSession._onDuration` | 重新发 Range 请求、重新缓冲；mpv 的 `cache-pause-wait=3` 还要再等最多 3 秒 |

现有缓存都只在内存里、只活在当前这次播放：

- mpv：`demuxer` 内存缓存（`cache-secs=30`，回看 64MiB，`bufferSize` 256MB）。
- Media3：没有接入 `CacheDataSource`。
- Aether：`AetherEngine.prewarm(url:)` 只把文件**开头** 8MB 放在**内存**里，按精确 URL 匹配，App 退出就没了。对续播没用，只适合“下一集预热”。
- “本地缓存播放”指的是已下载的完整文件，与本需求无关。

## 3. 各内核的缓存能力

| 内核 | 自带的持久化磁盘缓存 | 能否从续播点直接起播 | 结论 |
|---|---|---|---|
| mpv（media_kit） | 无。`cache-on-disk` 只是把本次播放的 demux 包写进临时文件，不能跨会话复用 | 能：`Media(uri, start:)`（media_kit 1.2.6 支持，设置 mpv 的 `start` 属性） | 只能通过本地代理或自定义 stream 协议实现，后者需要 FFI 和 `mpv_stream_cb_add_ro`，media_kit 没有封装 |
| Media3 | 有：`SimpleCache` + `CacheDataSource` + `LeastRecentlyUsedCacheEvictor`，支持稀疏分段，`setCacheKeyFactory` 可自定义缓存键，`CacheWriter` 可预取任意区间 | 能：`setMediaSource(source, startPositionMs)` | 原生方案成熟 |
| Aether 7.22.2 | 无。但 `load(source: .custom(IOReader))` 可以传入自定义字节源 | 能：`load(url:startPosition:)` | 自定义 IOReader 需要自己实现 Range、取消、`makeIndependentReader`，并且会丢掉 Aether 自带 `AVIOReader` 的预取、限速和重连优化 |

## 4. 方案对比

### 方案 A：统一本地缓存代理（推荐）

在 App 内起一个只监听 `127.0.0.1` 的 HTTP 代理。所有引擎播放 `http://127.0.0.1:<port>/<token>/<cacheKey>`；代理优先从磁盘返回已缓存的区间，缺失的区间再向源站请求，同时把数据写进缓存。

- 优点
  - 一套实现覆盖三种内核，配额只有一份；引擎代码几乎不用改（只换 URL）。
  - 缓存键由我们决定：用“服务器 + 媒体 ID + 文件路径 + 文件大小”，不受 302 签名直链过期的影响。
  - **可以延迟解析上游地址**：缓存命中时，代理直接用磁盘数据响应，表 2 中的步骤 1、2 改为后台进行（只在第一次缓存未命中时才需要等待）。这是“秒开”的关键，原生缓存方案都做不到。
  - mpv 只能用这个办法。
- 缺点 / 风险
  - 数据多经过一次本机回环。4K REMUX 约 80–150 Mbps，Dart `HttpServer` 理论上够用，但需要在 Android 中端机上压测 CPU 和发热；代理放在独立 isolate，避免卡 UI。
  - iOS 挂起后监听 socket 可能失效，回到前台要检测并重新绑定（后台播放本来就不是目标，但 Aether 回前台时会重建管线）。
  - iOS / macOS 的 Info.plist 没有配置 ATS，需要验证 URLSession 访问 `http://127.0.0.1` 是否会被拦截，必要时加 `NSAllowsLocalNetworking`。Android 已经开启 `usesCleartextTraffic`。
  - 路径里要带随机 token，防止本机其他 App 通过代理读取需要鉴权的内容（代理会替请求加上鉴权头）。

### 方案 B：各内核用原生缓存

Android 用 Media3 `SimpleCache`，Apple 自己写基于磁盘的 `IOReader`，mpv 仍然需要代理。

- 要维护三套实现；Android 上 Media3 和 mpv 兜底各有一份缓存，统一配额和清理都很麻烦。
- 上游解析不能延迟：还是要先拿到流地址才能交给引擎。
- Apple 的自定义 IOReader 会丢掉 Aether 的网络优化。

### 方案 C：混合

Android 用 Media3 原生缓存，其他平台用代理。只有当方案 A 在 Android 上压测不达标时才退到这一步。

**推荐 A**，先做一个性能 Spike；Android 不达标再局部退到 C。

## 5. 推荐方案设计（方案 A）

### 5.1 分阶段

| 阶段 | 内容 | 效果 | 预估 |
|---|---|---|---|
| P0 | 起播位置下沉到引擎：契约增加 `open(source, startPosition:)`，Aether 用 `load(startPosition:)`，mpv 用 `Media(start:)`，Media3 用 `setMediaSource(src, startMs)`；去掉“先从 0 播放再 seek”；调整 mpv 起播阶段的 `cache-pause-wait` | 不依赖缓存，续播就能少一轮请求和缓冲，也修掉 plan §12 里“开头先从 0 播放一瞬间”的已知问题 | 1 天 |
| P1 | 缓存代理 + 磁盘缓存 + 配额设置 | 看过的部分再次播放不走网络；续播点之后预读过的数据会命中缓存 | 5–7 天（含 Spike 和压测） |
| P2 | 缓存命中时延迟解析上游地址 | 步骤 1、2 不再阻塞起播 | 1–2 天 |
| P3（可选） | “继续观看”预取：Wi-Fi 下为最近 N 部未看完的条目预取“续播集”（见 5.3） | 在其他设备上看过、或本机没缓存的片子也能秒开 | 2 天 |

### 5.2 缓存结构

- 目录：`<应用缓存目录>/playback_cache/`，每个条目一个子目录：
  - `data`：稀疏文件，按源文件偏移写入。
  - `meta.json`：文件大小、Content-Type、ETag / Last-Modified、已缓存区间（按 1MB 块对齐的位图或区间表）、最后访问时间、最后播放位置对应的字节偏移。
- 缓存键：`sha1(serverId + 媒体类型 + 媒体 ID + filePath + fileSize)`。上游返回的大小或 ETag 不一致时，整条作废。
- 并发：同一条目可能有多路读取（Aether 的独立 reader、拖动预览），按块加写锁；正在播放的条目不允许淘汰。
- 已下载的完整文件仍然最优先，不走代理。

### 5.3 配额与淘汰

- 设置项：关闭 / 1 / 2 / 5 / 10 / 20 GB（默认待定），实际上限 = min(配额, 剩余空间 − 保留空间)。
- 两级淘汰：
  1. **先瘦身**：最久没访问的条目只保留“续播集”（头部约 4MB + 尾部索引区 + 续播点前后各约 30–60MB），其余块删除。
  2. **再整条删除**：瘦身后仍超出配额，按 LRU 整条删除。
- 这样同样 5GB，可以保留几十部“随时秒开”的片子，而不是只保留两三部完整缓存。
- 设置页“存储空间”加“播放缓存”分类，显示占用并支持清理；配额放在播放设置里（`PlaybackSettings` 新增字段）。

### 5.4 代码落点（遵守 plan §4.1 的依赖规则）

```
lib/playback/cache/
├── playback_cache_store.dart     # 磁盘存储、区间索引、配额、淘汰（纯 Dart，可单测）
├── playback_cache_proxy.dart     # 127.0.0.1 HTTP 代理（独立 isolate），处理 Range / 上游转发 / 边下边写
└── upstream_resolver.dart        # 复用 PlaybackSourceResolver 的鉴权与 302 逻辑，按需或延迟解析
```

- `PlaybackSourceResolver` 产出代理 URL；引擎完全感知不到缓存。
- 代理只在 `lib/playback/` 内，UI 不直接依赖。

## 6. 待确认问题

1. **缓存目标**：只保证“续播秒开”（按续播集保留，占用小），还是“看过的部分都尽量留着，回看也不走网络”（占用大）？推荐两级淘汰兼顾两者。
2. **默认配额**：建议移动端 2GB、桌面端 10GB，是否同意？
3. **是否做 P3 预取**：会在 Wi-Fi 下主动消耗流量和服务器 / 网盘带宽（网盘可能限流）。
4. **平台优先级**：先在哪个平台落地验证？建议先做 Android（Media3），同时做代理吞吐压测。

## 7. 验证计划

- Spike：Android 中端机 + 4K REMUX（约 100 Mbps），通过代理播放时检查 CPU、发热、是否卡顿，并与直连对比。
- 指标：续播时“点击 → 第一帧”的耗时，分别测缓存命中 / 未命中 / 302 直链三种场景，P0 前后各测一次。
- 单测：区间合并、配额淘汰、ETag 不一致时作废、多路并发 Range。
