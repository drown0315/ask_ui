# scrcpy WebCodecs MVP 经验教训

日期：2026-07-04

本文记录 `test_scrcpy/` WebCodecs MVP 实现过程中得到的经验教训。范围限定在能力校准 demo，不代表正式产品实现已经完成。

## 本轮实现范围

新增了一个最小 WebCodecs 路线：

- `test_scrcpy/server.mjs`
  - 保留原有 JPEG 刷新 demo。
  - 新增 `/webcodecs.html` 页面入口。
  - 新增 `/raw-h264` WebSocket。
  - 通过官方 scrcpy 4.0 server + ADB reverse 获取 raw H.264 Annex B。
  - 将收到的 raw H.264 bytes 原样通过 WebSocket binary frame 发给浏览器。
- `test_scrcpy/webcodecs.html`
  - 浏览器侧用 `VideoDecoder` 解码。
  - 用 `canvas` 渲染 `VideoFrame`。
  - 点击和滑动已改为走官方 scrcpy 4.0 control socket。
- `test_scrcpy/README.md`
  - 补充 WebCodecs MVP 的入口和环境变量。

运行入口：

```text
http://127.0.0.1:3010/webcodecs.html
```

示例启动：

```sh
DEVICE_ID=emulator-5554 node test_scrcpy/server.mjs
```

## 已验证的能力

在 `emulator-5554` 上验证到：

- ADB 设备在线。
- `adb shell wm size` 返回 `720x1280`。
- Node HTTP 服务可启动在 `127.0.0.1:3010`。
- `/raw-h264` WebSocket 可完成 `101 Switching Protocols` 握手。
- 官方 scrcpy server 可通过 ADB reverse 连回 Node。
- Node 收到 raw H.264 video socket 数据。
- 服务端日志出现过：

```text
raw h264 video socket connected
raw h264 first chunk: 42293 bytes
```

在物理设备 `19271FDF6007TY` 上也验证到：

```text
raw h264 video socket connected
raw h264 first chunk: 31 bytes
```

以及 WebSocket binary frame 收到 H.264 数据：

```text
BINARY 31 total 31
BINARY 23246 total 23277
```

这些证据说明：官方 scrcpy 4.0 raw H.264 stream 已能从 Android 设备走到浏览器 WebSocket 边界。

## 关键实现经验

### 1. raw stream 建链顺序要贴近官方客户端

当前可行顺序是：

1. Node 先监听本地 TCP 端口。
2. 建立 `adb reverse localabstract:scrcpy_<scid> tcp:<port>`。
3. push 官方 `scrcpy-server` 到设备。
4. 用 `app_process` 启动 `com.genymobile.scrcpy.Server`。
5. Android 端 server 主动连回 Node 监听端口。

这和官方 scrcpy 客户端默认 reverse 路线一致。不要把它想成普通 HTTP 拉流。

### 2. WebSocket frame 需要正确处理长度

第一次实现 text frame 时只用了单字节 payload length，短消息没问题，但 scrcpy server 日志稍长就可能破坏 WebSocket frame。

修正方式：

- binary frame 和 text frame 共用 `sendWebSocketFrame()`。
- 支持 payload length `<126`、`126`、`127` 三种长度编码。

经验：即使是 calibration demo，也不要手写“只适合短消息”的 WebSocket frame；调试日志经常比预期长。

### 3. session 生命周期比视频解码更早暴露问题

遇到过的问题：

- 探针连接断开后，Node 里的 `rawSession` 仍认为 active。
- 后续浏览器或探针连接收到：

```text
{"type":"error","message":"raw stream already active"}
```

修正点：

- raw session 绑定具体 `webSocket`。
- `end`、`close`、`error` 都触发清理。
- 清理时 kill scrcpy server process、关闭 video socket、关闭 capture server、移除 ADB reverse/forward。
- 如果旧 session 的 WebSocket 已 destroyed，允许下一次连接先清理旧 session。

经验：DeviceSurface 正式实现必须把 session lifecycle 当作一等能力，而不是附属逻辑。

### 4. 单连接限制要明确

当前 MVP 只支持一个 `/raw-h264` WebSocket 连接。

原因：

- 一个 scrcpy server session 对应一条 video socket。
- 多浏览器连接需要 fan-out、引用计数或每连接独立 scrcpy session。
- 这超出本轮最小验证范围。

当前行为：

- 已有连接时，新连接返回 `raw stream already active`。

正式产品建议：

- 一个 bridge session 只创建一条设备视频流。
- Web 侧如果需要多 consumer，应在 bridge 内部 fan-out，而不是启动多个 scrcpy server。

### 5. TCP chunk 不是视频帧

`/raw-h264` 里收到的是任意 TCP chunk，不等于 NAL，也不等于 frame/access unit。

浏览器侧必须：

- 按 Annex B start code 拆 NAL。
- 缓存跨 chunk 的尾部数据。
- 基于 NAL type 组装 access unit。
- IDR 前带上 SPS/PPS。

当前 `webcodecs.html` 的 access-unit 组装只是校准级启发式：

- 能用于最小验证。
- 不能直接作为正式 parser。

正式实现需要更稳的 H.264 Annex B parser。

### 6. WebCodecs 配置不要传 `description`

官方 raw stream 是 Annex B。WebCodecs AVC registration 里，不传 `VideoDecoderConfig.description` 时，bitstream 才按 Annex B 解释。

当前方向：

- 从 SPS 提取 `avc1.xxxxxx` codec string。
- `decoder.configure({ codec, optimizeForLatency: true })`。
- 不传 `description`。

这点和 MSE/fMP4 路线不同。MSE 需要封装，WebCodecs 可以更贴近 raw stream。

### 7. timestamp 目前是临时方案

scrcpy `raw_stream=true` 会关闭 frame metadata。浏览器侧拿不到官方 timestamp。

当前 MVP 用固定间隔：

```js
timestamp: frameIndex * 33333
duration: 33333
```

这只是按 30fps 近似，适合验证画面能动。正式实现需要决定：

- bridge 侧按接收时间打 timestamp。
- Web 侧按 decode 顺序生成单调 timestamp。
- 是否需要结合 `max_fps` 和实际帧到达时间。

### 8. backpressure 必须早做

WebCodecs 的 `decodeQueueSize` 不能无限增长。

MVP 里用了非常粗的策略：

- `decodeQueueSize > 8` 时丢当前 access unit。

低延迟调优 spike 已改为更激进的策略：

- 默认 scrcpy 参数改为 `MAX_FPS=60`、`VIDEO_BIT_RATE=8000000`。
- 页面端 `decodeQueueSize > 1` 时优先丢 delta access unit。
- `decodeQueueSize > 3` 时连当前 access unit 也会丢，优先追最新画面。
- 页面固定刷新轻量指标：decoded、dropped、queue、input bytes、approx FPS。
- server log 做节流，避免频繁 DOM 写入影响解码和渲染。

正式实现需要更明确：

- 优先保留最新 IDR。
- 低延迟场景允许丢 delta frame。
- 长时间运行要监控 decoded/dropped/input bytes。
- 每个 `VideoFrame` draw 完必须 `close()`。

### 9. 输入路径已从 ADB 切到 scrcpy control socket

第一版点击仍走：

```sh
adb shell input tap x y
```

这让视频解码 spike 可以独立推进，不被 scrcpy control protocol 阻塞。

后续低延迟输入 spike 已把 WebCodecs 页面改成官方 scrcpy 4.0 control socket：

- scrcpy server 启动参数从 `control=false` 改为 `control=true`。
- 同一个 ADB reverse socket name 下，Node 接收 video socket 后继续接收 control socket。
- 浏览器 pointer down/move/up 通过同一条 WebSocket 发 JSON 到 Node。
- Node 编码 scrcpy `INJECT_TOUCH_EVENT` control message 并写入 control socket。
- WebCodecs 页面不再用 `/api/tap` 或 `/api/swipe`。
- move 事件以约 60Hz 节流发送，避免浏览器事件风暴。

当前仍需继续校准：

- 多点触控。
- 滚轮/键盘。
- display id、orientation、裁剪后的坐标映射。
- 控制 socket backpressure 和错误恢复。

### 10. emulator 和物理机表现不同

同一套代码在物理机和 emulator 上都能收到 raw H.264，但首包大小、编码器行为和分辨率不同：

- Pixel 6 样本曾出现首包 `31 bytes`，后续大 chunk。
- emulator 首包可直接是 `42293 bytes`。
- Pixel 6 display 是 `1080x2400`。
- emulator display 是 `720x1280`。

经验：不要基于某一台设备的 chunk shape 写 parser 或状态机。

## 当前 MVP 限制

- 只支持一个 WebCodecs 连接。
- `webcodecs.html` 的 H.264 parser 是最小启发式。
- 没有生产级错误恢复。
- 没有自动重连。
- 没有正式的 frame timestamp 来源。
- 没有 MSE fallback。
- 没有 Broadway/TinyH264 fallback。
- WebCodecs 页面点击/滑动已走 scrcpy control socket；原始 JPEG demo 仍走 ADB input。
- 没有集成到 `apps/web` 的 `DeviceSurface`。
- 没有单元测试；这是 calibration demo。

## 下一步建议

1. 把 `webcodecs.html` 的 Annex B parsing 抽成独立小模块。
2. 用保存下来的 `.h264` 样本对 parser 做单元测试。
3. 明确 access unit 组装规则，避免把 TCP chunk 当 frame。
4. 在页面上显示更明确的状态：connected、configured、decoded frames、dropped frames、queue size。
5. 做一次真实浏览器可视验证：确认 canvas 非黑屏、画面连续、点击可操作。
6. 再决定是否把这套能力提升到 bridge API 设计。
7. bridge API 设计时保留 MSE fallback 的扩展点，但首期实现继续 WebCodecs first。

## 对正式 DeviceSurface 的启发

正式实现里，`DeviceSurface` 不应该直接管理 scrcpy 进程。它应该消费 bridge 提供的 surface session：

- `deviceId` 来自页面 URL，必填。
- bridge 校验 `deviceId` 和 `vmServiceUri` 对应同一台稳定设备。
- bridge 持有 scrcpy server、ADB reverse、video socket、input fallback。
- Web 前端只负责：
  - 建立视频 WebSocket。
  - 解码和渲染。
  - 映射点击坐标。
  - 调 bridge input API。

这一轮 MVP 证明了 WebCodecs 路线值得继续推进，但也暴露出正式化前必须补齐的基础设施：session lifecycle、H.264 parser、backpressure、可观测状态和错误恢复。
