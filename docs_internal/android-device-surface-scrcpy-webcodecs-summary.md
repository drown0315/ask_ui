# Android DeviceSurface scrcpy/WebCodecs 方案总结

日期：2026-07-04

本文总结 `test_scrcpy/` spike 中最终跑通的 Android DeviceSurface 技术路线、实测参数、关键经验和生产化风险。本文是阶段性方案总结，不代表正式 `apps/web` 产品代码已经集成。

## 最终验证方案

当前验证通过的方案是：

```text
Android device
-> official scrcpy 4.0 server
-> raw H.264 Annex B video socket
-> Node bridge WebSocket binary frames
-> Browser WebCodecs VideoDecoder
-> canvas

Browser pointer events
-> same browser WebSocket JSON control messages
-> Node encodes scrcpy touch control messages
-> official scrcpy control socket
-> Android device
```

这条路线不使用桌面 `scrcpy` 窗口，不使用 Screen Capture API，不使用通用 Web 播放器框架，也不依赖 `ws-scrcpy` 的 fork server jar。

## 当前可运行入口

启动：

```sh
DEVICE_ID=19271FDF6007TY MAX_FPS=60 VIDEO_BIT_RATE=16000000 node test_scrcpy/server.mjs
```

打开：

```text
http://127.0.0.1:3010/webcodecs.html
```

当前在物理设备 `19271FDF6007TY` 上验证过：

- 设备：Pixel 6。
- Android：14。
- display size：`1080x2400`。
- `MAX_SIZE=1080`。
- `MAX_FPS=60`。
- `VIDEO_BIT_RATE=16000000`。
- 用户体感：延迟已可接受，16Mbps 码率清晰度够用。

## 为什么选择这条路线

### WebCodecs 优先

官方 scrcpy 4.0 `raw_stream=true` 输出的是 raw H.264 Annex B。WebCodecs 可以直接消费 Annex B access unit，只要：

- 从 SPS 得到 `avc1.xxxxxx` codec string。
- `VideoDecoder.configure({ codec, optimizeForLatency: true })`。
- 不传 `VideoDecoderConfig.description`，让浏览器按 Annex B 解释输入。
- 送入 `EncodedVideoChunk` 前先按 Annex B start code 拆 NAL 并组 access unit。

WebCodecs 的优势是链路短、可控、适合低延迟。相比 MSE，它不需要先封装 fMP4。相比 Broadway/TinyH264，它优先使用浏览器内建解码器，CPU 和包体成本更低。

### 不采用通用播放器框架

`video.js`、HLS、DASH、MSE 播放器等通常以“稳定播放”为目标，会引入缓冲、时间轴和重排策略。DeviceSurface 的目标是“显示最新手机画面”，必要时应该丢帧，而不是完整播放历史帧。

### 不采用 WebRTC 作为 MVP

WebRTC 适合跨网络低延迟媒体，但 scrcpy server 输出不是 WebRTC track。要走 WebRTC，需要 bridge 把 H.264 access unit packetize 成 RTP，并处理 SDP、ICE、DTLS、SRTP、RTCP 等。当前场景是本机 bridge + 本机 browser + ADB 设备，WebRTC 的复杂度暂时不划算。

### 不采用 Screen Capture API

Screen Capture API 只能捕获宿主电脑的屏幕、窗口或标签页。它不能直接获取 Android 设备画面，也不能按 `deviceId` 自动绑定设备，更不能提供 Android 输入控制。捕获桌面 scrcpy 窗口会多绕一层 OS compositor，延迟和自动化能力都不适合正式方案。

## scrcpy server 建链经验

官方 scrcpy 客户端默认使用 ADB reverse。可行顺序是：

1. Node 在本机监听 TCP 端口。
2. 建立 `adb reverse localabstract:scrcpy_<scid> tcp:<port>`。
3. push 官方 `scrcpy-server` 到 `/data/local/tmp/scrcpy-server.jar`。
4. 用 `app_process` 启动 `com.genymobile.scrcpy.Server`。
5. Android 端 server 主动连接 `localabstract:scrcpy_<scid>`，经 ADB reverse 连回 Node。

本 spike 使用的关键 server 参数：

```text
scid=2b3c4d5e
log_level=debug
audio=false
control=true
raw_stream=true
max_size=1080
max_fps=60
video_bit_rate=16000000
cleanup=false
power_on=false
```

`control=true` 后，Node 会在同一个 reverse 监听 server 上接到两条 socket：

- 第一条：video socket，承载 raw H.264 Annex B。
- 第二条：control socket，接收 scrcpy control messages。

## WebCodecs 低延迟经验

视频低延迟的关键不是“完整播放”，而是“永远追最新画面”。

当前页面策略：

- `VideoDecoder` 配置 `optimizeForLatency: true`。
- 固定以 60fps 近似生成 `timestamp/duration`。
- `decodeQueueSize > 1` 时优先丢 delta access unit。
- `decodeQueueSize > 3` 时更激进地丢当前 access unit。
- 每个 `VideoFrame` 绘制到 canvas 后立刻 `frame.close()`。
- header 显示 decoded、fps、dropped、drop/s、queue、input MiB。
- server log 在页面端节流，避免频繁 DOM 写入影响解码。

已观察到：

- 8Mbps/60fps 延迟可接受，但清晰度仍可提升。
- 16Mbps/60fps 在物理机上清晰度够用，延迟仍可接受。
- 更高码率可以继续试，但可能增加设备编码、USB/ADB 和浏览器 GC 压力。

## 输入控制经验

第一版输入用 `/api/tap` 和 `/api/swipe`，底层是：

```sh
adb shell input tap ...
adb shell input swipe ...
```

这能验证交互闭环，但延迟和手感不适合正式 DeviceSurface。

当前 WebCodecs 页面已改为 scrcpy control socket：

- `pointerdown` -> `ACTION_DOWN`。
- `pointermove` -> `ACTION_MOVE`。
- `pointerup` / `pointercancel` -> `ACTION_UP`。
- move 事件约 60Hz 节流。
- 浏览器把 pointer 事件映射到当前 canvas/video 坐标。
- Node 编码 scrcpy touch control message 后写入 control socket。

实测结果：点击和滑动体感明显优于 ADB input，用户反馈“完美”。

## 已验证能力

| 能力 | 结论 |
| --- | --- |
| 使用 `deviceId` 选择 Android 设备 | 已验证 |
| 官方 scrcpy 4.0 server raw stream | 已验证 |
| ADB reverse 建链 | 已验证 |
| Node 收 raw H.264 Annex B | 已验证 |
| WebSocket 转发 raw H.264 | 已验证 |
| Browser WebCodecs 解码并 canvas 渲染 | 已验证 |
| 低延迟丢帧策略 | 已验证有效 |
| 16Mbps/60fps/1080 max size | 物理机体感可接受 |
| scrcpy control socket 点击/滑动 | 已验证 |
| MSE fallback | 未实现 |
| 多点触控/键盘/滚轮 | 未实现 |
| 正式 `apps/web` 集成 | 未实现 |

## 关键坑

### TCP chunk 不是帧

video socket 收到的是任意 TCP chunk。chunk 不等于 NAL，不等于 access unit。必须按 Annex B start code 拆 NAL，并组装 access unit 后再送 WebCodecs。

### raw H.264 不能直接给 `<video>`

浏览器 `<video>` 能播放 H.264，通常是 MP4/fMP4/HLS/DASH 等容器或流媒体格式。raw Annex B H.264 不能直接作为 `<video src>` 播放。

### MSE 不能直接 append raw Annex B

MSE 需要 init segment 和 media segment。raw Annex B 必须先封装成 fMP4，再 `appendBuffer()`。

### WebSocket frame 长度要写完整

不能只支持短 payload。text frame 和 binary frame 都要处理 `<126`、`126`、`127` 三种长度编码，否则 server log 或大包会破坏协议。

### Session lifecycle 是一等问题

旧 session 如果没有清理，会导致后续连接报：

```text
raw stream already active
```

清理必须覆盖：

- video socket。
- control socket。
- capture server。
- scrcpy server process。
- ADB reverse/forward。
- 浏览器 WebSocket close/error/end。

### 日志也会影响延迟

页面端如果每条 server log 都 prepend 到 DOM，会干扰解码和渲染。低延迟页面必须节流日志，只保留轻量指标。

### ADB input 不是最终输入路径

`adb shell input` 可以用于早期验证，但不适合低延迟点击/滑动。正式路线应使用 scrcpy control protocol。

### Emulator 和物理机差异明显

同一套代码在 emulator 和 Pixel 6 上首包大小、分辨率、编码器行为不同。不能根据某一台设备的 chunk shape 写 parser。

## 当前风险和可解法

这些风险是工程问题，不是路线不可行。

| 风险 | 当前状态 | 生产化解法 |
| --- | --- | --- |
| Node WebSocket write backpressure | demo 未处理 | 根据 `socket.write()` 和 buffered bytes 丢旧视频数据 |
| 浏览器 `pendingBytes` 无限增长 | demo 未设硬上限 | parser buffer、access unit buffer 设置硬上限 |
| 日志无限增长 | demo 仅 server log 节流 | log 行数/字符数上限 |
| decoder close 不够完整 | demo 可用 | socket close 时统一 close decoder、清 timer、清 buffer |
| 高码率拷贝和 GC 压力 | demo 有额外 copy | 减少 Buffer concat，复用 buffer 或分层队列 |
| control socket 错误恢复 | demo 基础可用 | control/video session 状态机和重连策略 |
| H.264 parser 启发式 | demo 可用 | 抽模块，用真实 `.h264` 样本测试 |

## 产品化建议

正式 `DeviceSurface` 不应直接管理 scrcpy 进程。边界应保持：

```text
apps/web DeviceSurface
-> bridge DeviceSurface session API
-> bridge owns ADB/scrcpy lifecycle
-> Web consumes video WebSocket and sends input events
```

推荐 bridge session 合约：

- URL 必填 `deviceId`。
- bridge 校验 `deviceId` 和 `vmServiceUri` 指向同一台稳定 Target Device。
- 一个 `vmServiceUri` 在 session 生命周期内只绑定一台设备，且不变化。
- bridge 管理 scrcpy server、ADB reverse、video socket、control socket 和清理。
- Web 前端只负责渲染、状态展示和输入事件映射。

## 下一步

1. 把 `webcodecs.html` 里的 Annex B parser/access-unit builder 抽成模块。
2. 用保存的 `.h264` 样本补 parser 测试。
3. 给 Node/Web 两侧 buffer 和日志加硬上限。
4. 实现 WebSocket backpressure 和低延迟丢包策略。
5. 抽象 bridge-owned DeviceSurface session API。
6. 集成到 `apps/web` 的 `DeviceSurface`。
7. 后续再评估 MSE/fMP4 fallback、键盘、滚轮、多点触控。
