# Android Device 调研记录

日期：2026-07-03

本文记录 Ask UI 将中心区域改为安卓手机画面并支持点击操作时，围绕 `scrcpy`、ADB、bridge 边界和 Web 嵌入方式做过的校准结论。

## 目标

Ask UI 的中心区域应成为 `Live App Surface`：用户可以在 Workbench 内看到目标安卓设备上的 Flutter app 画面，并直接点击这块画面操作设备。

当前只支持 Android。页面启动参数中必须包含 `deviceId`，它应是 ADB/scrcpy 可使用的稳定设备标识。一个 `vmServiceUri` 在一个 workbench session 生命周期内只对应一个 Target Device，且不会变化；`deviceId` 必须指向同一个设备。

## 已确认的产品语义

- 中心区域的产品术语仍是 `Live App Surface`。
- React 组件名倾向使用 `Device`。
- 不引入 `Operate Mode` 按钮或开关。
- Live App Surface 始终可点击，点击始终发送给 Target Device。
- Select Widget 只改变 Flutter Inspector 如何解释触摸；Ask UI 不在前端引入另一套“拦截点击但不转发”的模式。

## 架构边界

Android 设备画面和输入控制应由本地 bridge 托管，而不是由 Web 前端直接管理 scrcpy/ADB。

原因：

- bridge 已经拥有 Flutter VM Service session 边界。
- scrcpy/ADB 涉及本地进程、设备 serial、端口、流生命周期和错误处理。
- Web 前端应只消费 bridge 提供的 surface 状态/流地址，并通过 bridge API 发送输入。

该决策已记录在：

- `docs/adr/0001-bridge-owned-android-device.md`

## 本机校准环境

已验证工具：

- `adb`: Android Debug Bridge 1.0.41，version 35.0.1-11580240
- `scrcpy`: 4.0
- `ffmpeg`: 本机可用

已连接设备：

- ADB serial: `19271FDF6007TY`
- Model: `Pixel_6`
- Android: 14
- Display 0: `1080x2400`

关键命令证据：

```sh
adb devices -l
scrcpy -s 19271FDF6007TY --list-displays
adb -s 19271FDF6007TY shell wm size
adb -s 19271FDF6007TY shell input
```

## scrcpy CLI 能力结论

官方桌面 `scrcpy` CLI 默认面向本机窗口播放，不天然提供浏览器 live stream endpoint。

已验证：

- `scrcpy --list-displays` 可得到设备 display 信息。
- `scrcpy --no-window` 会禁用视频，日志显示没有 playback/recording/sink 时 video disabled。
- `scrcpy --no-video-playback --record=...` 可以无窗口录制 H.264 MP4/MKV 文件。
- `--record=-` 不是 stdout 流语义，不可作为直接管道使用。
- 录制到 FIFO 可行，但 ffmpeg 对仍在写入中的 MKV/FIFO 不能稳定实时输出给 HTTP response；等 scrcpy 结束后可以转换出帧。

结论：

- 官方 CLI 可用于能力校准 demo。
- 官方 CLI 不应作为最终低延迟 Web 嵌入方案。
- 最终方案仍需要校准浏览器端 H.264 解码播放和官方 scrcpy control protocol。

## ws-scrcpy / bridge-rs 参考结论

调研了两个参考项目：

- `/Users/drown/ai_project/bridge-rs`
- `/Users/drown/ai_project/ws-scrcpy`

`bridge-rs` 的作用：

- 启动或连接本机 ADB server。
- 暴露 `/bridge/` WebSocket。
- 将浏览器二进制包原样转发到 ADB TCP 连接。
- 将 ADB 返回二进制包原样发回浏览器。
- 它本身不调用桌面 `scrcpy` CLI，也不解码视频。

`ws-scrcpy` 的作用：

- vendored 一个 `scrcpy-server.jar`。
- push jar 到 Android 设备。
- 通过 `app_process` 启动 `com.genymobile.scrcpy.Server`。
- 设备端 server 监听端口 `8886`。
- 通过 ADB forward 暴露该端口。
- Web 通过 WebSocket 接收初始元数据、H.264 帧和设备消息。
- Web 用 MSE/WebCodecs/Broadway/TinyH264 等播放器解码。
- 点击/触摸格式化为 scrcpy control message 发回同一条 stream。

重要差异：

- `ws-scrcpy` vendored jar 的协议版本是 `1.19-ws5`。
- 本机官方 scrcpy 4.0 的 server 位于 `/opt/homebrew/Cellar/scrcpy/4.0/share/scrcpy/scrcpy-server`。
- 两者 hash 和大小不同，不能假设协议兼容。

结论：

- `ws-scrcpy` 是很有价值的架构参考。
- Ask UI 当前方向仍是优先校准官方 scrcpy 4.0 server，而不是直接锁定 `ws-scrcpy` vendored jar。

## 官方 scrcpy server raw socket 校准结果

第一轮尝试曾手动 push 官方 scrcpy 4.0 server，并以 `raw_stream=true` 启动，但当时未对齐官方客户端的 socket 方向和 socket 名，未收到可解码帧。

下一轮 spike 已对齐官方 4.0 源码和客户端行为，关键结论如下：

- 官方客户端默认优先使用 `adb reverse`：本机先 listen，Android 端 server 主动连接 `localabstract:scrcpy_<scid>` 映射到的本机 TCP 端口。
- `adb forward` 仍可作为 fallback；此时 server 参数必须包含 `tunnel_forward=true`，Android 端创建 `LocalServerSocket`，本机再连接。
- socket 名格式是 `scrcpy_<8位十六进制scid>`，例如 `scrcpy_1a2b3c4d`。
- `raw_stream=true` 会关闭 `send_device_meta`、`send_frame_meta`、`send_dummy_byte` 和 `send_stream_meta`。
- 因此 video socket 上收到的是无 scrcpy 元数据包头的 raw H.264 Annex B NAL 字节流。

本轮新增 `test_scrcpy/raw_stream_probe.mjs`，使用官方 server 二进制：

```sh
DEVICE_ID=19271FDF6007TY node test_scrcpy/raw_stream_probe.mjs
```

已验证默认 reverse 路径：

- 收到 `402129` bytes。
- H.264 start code 数量：`13`。
- NAL types：`1`、`5`、`7`、`8`。
- `hasSps=true`、`hasPps=true`、`hasIdr=true`。
- `ffprobe` 可识别为 H.264，`ffmpeg` 可抽取 JPEG 帧。

也验证过 forward fallback 路径：

- 收到 `706081` bytes。
- NAL types：`1`、`5`、`7`、`8`。
- `hasSps=true`、`hasPps=true`、`hasIdr=true`。

已观察到的 server 日志特征：

- `[server] INFO: Device: [Google] google Pixel 6 (Android 14)`
- `[server] DEBUG: Using video encoder: 'c2.exynos.h264.encoder'`
- `[server] DEBUG: Display: using DisplayManager API`

结论：

- 官方 scrcpy 4.0 server raw video stream 已校准到 Node bridge 可稳定接收。
- 当前 raw video stream 输出是 Annex B H.264，可作为下一步 WebCodecs/MSE spike 的输入。
- 后续 spike 已校准官方 scrcpy 4.0 control socket，WebCodecs 页面点击/滑动已不再依赖 ADB `input tap/swipe`。

## Web 解码路线校准结果

本轮 spike 聚焦如何把官方 scrcpy 4.0 raw stream 放进浏览器播放。前置输入已经确认：

- `test_scrcpy/raw_stream_probe.mjs` 捕获的是 raw H.264 Annex B NAL 字节流。
- 本机样本 `/private/tmp/ask-ui-scrcpy-raw-probe.h264` 可被 `ffprobe` 识别。
- 样本 codec 信息：H.264 High Profile，`avc1.640034`，`486x1080`，`is_avc=false`，`has_b_frames=0`。

规范和本机浏览器能力证据：

- W3C WebCodecs AVC registration 明确区分 `annexb` 和 `avc` bitstream。
- 对 `VideoDecoderConfig.description`：不提供 `description` 时，AVC bitstream 被视为 Annex B；提供 `description` 时才视为 AVCDecoderConfigurationRecord/AVC 格式。
- `VideoDecoder` 属于 WebCodecs API，需要 secure context；`http://127.0.0.1` 在本机测试中满足 `isSecureContext=true`。
- 本机 Chrome headless 在 `http://127.0.0.1` 下检测结果：
  - `VideoDecoder` 为 `function`。
  - `EncodedVideoChunk` 为 `function`。
  - `MediaSource` 为 `function`。
  - `VideoDecoder.isConfigSupported({ codec: "avc1.640034", optimizeForLatency: true })` 返回 `supported: true`。
  - `MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E"')` 返回 `true`。
  - `MediaSource.isTypeSupported('video/mp4; codecs="avc1.640034"')` 返回 `true`。

对三条路线的判断：

### WebCodecs 优先

WebCodecs 是当前最直接的官方 raw stream 播放路线。

推荐方向：

1. bridge 通过 WebSocket/SSE-like binary channel 向 Web 发送 raw H.264 bytes。
2. Web 侧按 Annex B start code 拆 NAL。
3. 从 SPS 解析 codec string、宽高，配置 `VideoDecoder`。
4. 不传 `VideoDecoderConfig.description`，让 AVC 解码器按 Annex B 解释 `EncodedVideoChunk.data`。
5. 将包含 SPS/PPS/IDR 的访问单元作为 key chunk 喂给 `VideoDecoder.decode()`。
6. 将输出 `VideoFrame` draw 到 `canvas`，或后续评估 `VideoFrame` 到其他渲染路径。

需要 spike 验证的细节：

- raw stream 中如何稳定组装 access unit，而不是按任意 TCP chunk 调 `decode()`。
- timestamp 如何生成。scrcpy raw stream 没有 frame meta，需要 bridge 或 Web 侧按接收时间/帧率生成单调 timestamp。
- Chrome 之外的浏览器支持范围，尤其 Safari/Firefox。
- 长时间运行时的 backpressure：`VideoDecoder.decodeQueueSize`、丢帧策略、`VideoFrame.close()`。

### MSE 作为兼容方案

MSE 不应直接消费当前 raw Annex B 字节流。它需要 ISO BMFF/fMP4 初始化段和媒体段。

推荐方向：

1. 将 Annex B NAL 组装为 access unit。
2. 提取 SPS/PPS，生成 MP4 init segment。
3. 将后续帧封装为 fragmented MP4 `moof`/`mdat` media segment。
4. 通过 `MediaSource.addSourceBuffer('video/mp4; codecs="..."')` 和 `SourceBuffer.appendBuffer()` 播放。

`ws-scrcpy` 的 MSE player 也是这个路线：使用 `h264-converter` 从设备收到的 NALU 创建 MP4 container，再喂给 `MediaSource`。它是可参考实现，但仍要注意它基于旧的 vendored scrcpy server 协议，不等同于官方 4.0 server wire protocol。

MSE 的优势是可走浏览器原生 video pipeline；劣势是实现复杂度比 WebCodecs 高，而且低延迟 buffer 管理更敏感。

### Broadway/TinyH264 仅作为 fallback 候选

Broadway/TinyH264 是 wasm/software decoder 路线。它们不依赖 WebCodecs/MSE codec support，但会引入更高 CPU 成本、更多包体、渲染质量和维护风险。

当前不建议作为首轮产品实现，只保留在以下情况继续评估：

- 目标浏览器缺失 WebCodecs 且 MSE/fMP4 路线不稳定。
- 需要支持无法硬解当前 H.264 profile 的环境。
- 内部 dogfood 发现 WebCodecs/MSE 兼容性不足。

## Web 解码能力矩阵

| 能力 | 状态 | 结论 |
| --- | --- | --- |
| 浏览器直接解官方 raw H.264 Annex B | 已支持/待集成 | 本机 Chrome 支持 `VideoDecoder` + `avc1.640034`；WebCodecs 规范支持不带 `description` 的 Annex B 输入 |
| 从 raw stream 提取 codec string | 可支持 | SPS 中可解析 `avc1.xxxxxx`；`ws-scrcpy` 已有类似实现参考 |
| 将 TCP chunk 直接作为 decode chunk | 不支持 | TCP chunk 边界不是视频帧边界；必须按 NAL/access unit 重组 |
| MSE 直接播放 raw Annex B | 不支持 | MSE ISO BMFF byte stream 需要 init segment/media segment，不是裸 Annex B |
| MSE 播放 fMP4 封装后的 H.264 | 已支持/待集成 | 本机 Chrome `MediaSource.isTypeSupported()` 对 baseline 和样本 High profile 均返回 true |
| Broadway/TinyH264 软件解码 | 参考可行 | `ws-scrcpy` 有集成经验；当前只作为 fallback 候选 |

## test_scrcpy Demo

已新增 throwaway 校准 demo：

- `test_scrcpy/README.md`
- `test_scrcpy/index.html`
- `test_scrcpy/server.mjs`
- `test_scrcpy/raw_stream_probe.mjs`

运行方式：

```sh
DEVICE_ID=19271FDF6007TY node test_scrcpy/server.mjs
```

打开：

```text
http://127.0.0.1:3010
```

当前 demo 路径：

1. Web 页面点击 Start。
2. Node bridge 读取设备 display size。
3. `/stream.mjpg` 每次触发一次短 scrcpy 无窗口录制。
4. ffmpeg 从短录制中抽取 JPEG 帧。
5. Web `<img>` 显示该帧并自动刷新。
6. 用户点击图像后，前端按图像尺寸映射到设备坐标。
7. Node bridge 执行 `adb shell input tap x y`。

已验证：

- `node --check test_scrcpy/server.mjs` 通过。
- `/api/start` 返回设备 `19271FDF6007TY` 和 display size `1080x2400`。
- `/stream.mjpg` 生成真实 JPEG 帧，样例为 `486x1080`，约 `43K`。
- `/api/tap` 返回 `{"status":"ok","x":10,"y":10}`。

限制：

- 这是早期刷新帧 demo，不是最终低延迟 live stream。
- 早期点击使用 ADB input；后续 WebCodecs 页面已切到 scrcpy control socket。
- 该 demo 只证明官方 scrcpy 工具链可以驱动网页内画面和点击回传；最终低延迟验证见 `docs_internal/android-device-scrcpy-webcodecs-summary.md`。

## 当前能力矩阵

| 能力 | 状态 | 结论 |
| --- | --- | --- |
| 使用 `deviceId` 定位 Android 设备 | 已支持 | `adb -s` 和 `scrcpy -s` 均可用 |
| 获取 display size | 已支持 | `adb shell wm size` 和 `scrcpy --list-displays` 可用 |
| 基础点击输入 | 已支持 | WebCodecs 页面已走 scrcpy control socket；ADB input 只保留为早期 fallback |
| 滑动/拖拽输入 | 已支持 | WebCodecs 页面已发送 pointer down/move/up 到 scrcpy control socket |
| 官方 scrcpy CLI 无窗口录制 | 已支持 | 可录制 MP4/MKV，用于校准 demo |
| 官方 scrcpy CLI 浏览器实时流 | 不支持 | CLI 没有直接 Web stream endpoint |
| `ws-scrcpy` 风格 Web H.264 解码 | 参考可行 | 但其 server jar 不是官方 4.0 server |
| 官方 scrcpy server raw socket live stream | 已支持 | Node bridge 已能通过官方 4.0 server 收到 H.264 SPS/PPS/IDR |
| WebCodecs 解码官方 raw H.264 | 已支持 | `test_scrcpy/webcodecs.html` 已完成页面级 live decode demo |
| MSE 解码官方 raw H.264 | 间接支持 | 需要先封装成 fMP4，不能直接 append raw Annex B |
| Broadway/TinyH264 软件解码 | 候选 | 仅作为 WebCodecs/MSE 不可用时的 fallback |
| scrcpy control message 输入 | 已支持 | 官方 4.0 control socket 已验证点击/滑动 |

## 推荐下一步

1. 保留 `test_scrcpy/` 作为能力校准 demo，不并入正式产品代码。
2. WebCodecs live decode demo 已完成，当前经验总结见 `docs_internal/android-device-scrcpy-webcodecs-summary.md`。
3. 输入路径已从 ADB `input tap/swipe` 切到官方 scrcpy 4.0 control socket；后续再补多点触控、滚轮和键盘。

## 当前建议的产品 contract

当前可以承诺：

- Android-only。
- 页面 URL 必填 `deviceId`。
- bridge 托管设备画面和输入生命周期。
- Web 中有一个 `Device`/Live App Surface。
- 点击 Live App Surface 会转发到 Target Device。

当前不应承诺：

- 已支持多设备切换。
- 已支持多点触控、滚轮和键盘。
- demo 级 parser/backpressure 已达到生产化质量。
