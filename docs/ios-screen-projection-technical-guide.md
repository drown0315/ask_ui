# 物理 iPhone 屏幕实时投影到 Web：语言无关技术指南

## 1. 目的

本文描述如何在 macOS 上采集一台通过 USB 连接的物理 iPhone，将屏幕实时编码为 H.264，并通过本地网络服务投影到 Web 浏览器。

本文是一份独立技术规范，不依赖任何现有工程、目录结构或服务端语言。实现者可以自由选择 Go、Rust、Dart、Node.js、Java、Kotlin、C# 或其他能够管理子进程与 WebSocket 的语言。

只有设备采集层建议使用 Swift，因为它需要直接调用 macOS 的 CoreMediaIO、AVFoundation 和 VideoToolbox。

本文只讨论屏幕投影，不讨论鼠标、触摸或键盘控制。视频采集与设备控制是两个不同的系统边界，应分别设计。

## 2. 支持范围

### 2.1 支持

- macOS 主机；
- 一台通过 USB 连接的物理 iPhone；
- iPhone 已解锁并信任当前 Mac；
- 实时屏幕画面，无音频；
- H.264 低延迟编码；
- WebSocket 本地传输；
- 支持 WebCodecs 的 Chromium 系浏览器；
- 浏览器刷新后复用同一采集进程；
- iPhone 断开、权限拒绝、设备繁忙等错误诊断。

### 2.2 不包含

- iPhone 音频；
- 屏幕操作注入；
- 多台 iPhone 同时采集；
- 互联网远程访问；
- 用户认证和传输加密；
- MOV/MP4 文件录制；
- ReplayKit 应用内广播；
- iPhone Mirroring 私有协议。

## 3. 系统架构

```text
Physical iPhone
  │ USB
  ▼
CoreMediaIO iOS screen-capture device
  ▼
AVCaptureDevice
  ▼
AVCaptureSession
  ▼
AVCaptureVideoDataOutput
  ▼ CMSampleBuffer / CVPixelBuffer
VideoToolbox VTCompressionSession
  ▼ H.264 Annex B access units
Swift capture helper stdout
  ▼ framed binary stream
Host orchestrator
  ▼ WebSocket binary messages
Browser WebCodecs VideoDecoder
  ▼ VideoFrame
HTML Canvas
```

系统分为三个独立组件：

1. **Swift capture helper**：发现 iPhone、采集屏幕、编码 H.264；
2. **Host orchestrator**：启动 helper、解析 stdout、管理生命周期、转发 WebSocket；
3. **Web viewer**：解析帧、配置 WebCodecs、绘制 Canvas。

组件之间只通过稳定协议通信。这样可独立替换服务端语言或浏览器框架，而不修改 Swift 采集逻辑。

## 4. 环境要求

### 4.1 macOS

- 安装 Xcode 或 Xcode Command Line Tools；
- `swiftc` 可用；
- 运行 helper 的终端或宿主应用具有 Camera 权限；
- 没有 QuickTime Player、OBS 或其他程序占用 iPhone capture device。

检查：

```sh
xcode-select -p
swiftc --version
xcrun xctrace list devices
```

### 4.2 iPhone

- 通过 USB 连接；
- 已解锁；
- 屏幕保持点亮；
- 已确认“信任此电脑”；
- 能出现在 `xcrun xctrace list devices` 的 `== Devices ==` 区域。

`xctrace` 能看到设备，只说明 USB/Xcode 设备在线，不代表 AVFoundation 已经发布屏幕采集设备。

### 4.3 浏览器

浏览器必须支持：

- `WebSocket`；
- `VideoDecoder`；
- `EncodedVideoChunk`；
- H.264 decode profile；
- Canvas 2D 或 WebGL。

建议优先使用当前稳定版 Chrome 或 Edge。

## 5. 设备身份模型

macOS 对同一台 iPhone 暴露两种不同 ID。

### 5.1 Development UDID

来源：

```sh
xcrun xctrace list devices
```

典型格式是 40 位十六进制字符串。Xcode 和其他开发工具通常使用该 ID。

### 5.2 AVFoundation capture ID

来源：

```swift
AVCaptureDevice.uniqueID
```

典型格式是 UUID 风格字符串。真正建立 `AVCaptureDeviceInput` 时使用该 ID。

### 5.3 两种 ID 不能互换

```text
Development UDID != AVCaptureDevice.uniqueID
```

如果用户提供 development UDID，orchestrator 可以通过 xctrace 找到设备显示名称，再把 UDID 与名称一起传给 Swift helper。Swift 首先匹配 capture ID，匹配失败后按精确名称查找。

如果用户直接提供 capture ID，orchestrator 应将其原样传给 Swift helper，即使该 ID 不存在于 xctrace 输出中。

## 6. 关键发现：设备发现与采集必须位于同一进程

不要使用以下启动流程：

```text
helper list process
  -> discovers AVCaptureDevice
  -> exits

helper stream process
  -> performs a new discovery
  -> capture_device_not_found
```

物理设备验证表明，CoreMediaIO 的 iOS screen-device opt-in 和异步发布具有进程生命周期特征。一个短生命周期进程成功列出设备，并不能保证随后的新进程立即看到同一设备。

正确流程：

```text
xctrace only for USB identity/name mapping
  -> start exactly one Swift stream process
  -> enable CoreMediaIO in that process
  -> discover AVCaptureDevice in that process
  -> create AVCaptureSession in that process
  -> keep process alive for the entire projection session
```

可以保留独立 `list` 命令用于人工诊断，但 orchestrator 启动实时投影时不能把它作为 preflight。

## 7. Swift capture helper

### 7.1 编译

```sh
swiftc -parse-as-library ios_capture.swift -o ios_capture
```

依赖：

```swift
import AVFoundation
import CoreMediaIO
import Foundation
import VideoToolbox
```

### 7.2 CLI contract

建议提供：

```text
ios_capture stream \
  --device-id ID \
  [--device-name NAME] \
  [--max-fps 30] \
  [--bit-rate 6000000]
```

stdout 只能写协议数据，stderr 只能写诊断信息。

### 7.3 开启 CoreMediaIO iOS screen devices

```swift
func enableIOSScreenCaptureDevices() {
    var address = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(
            kCMIOHardwarePropertyAllowScreenCaptureDevices
        ),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var allow: UInt32 = 1
    CMIOObjectSetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        UInt32(MemoryLayout.size(ofValue: allow)),
        &allow
    )

    // 真实设备上必须给 CoreMediaIO 一个固定发布窗口。
    Thread.sleep(forTimeInterval: 1.0)
}
```

固定等待后仍应做有界轮询：

```swift
func waitForDeviceEvents(until deadline: Date) {
    RunLoop.current.run(
        until: min(deadline, Date().addingTimeInterval(0.25))
    )
}
```

推荐总 discovery timeout 为 10 秒。

### 7.4 查找 iPhone capture device

```swift
func currentIOSDevices() -> [AVCaptureDevice] {
    let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external, .builtInWideAngleCamera],
        mediaType: nil,
        position: .unspecified
    )
    return discovery.devices.filter {
        $0.modelID == "iOS Device" &&
        $0.manufacturer == "Apple Inc."
    }
}
```

轮询逻辑：

```text
deadline = now + 10 seconds
repeat:
  devices = currentIOSDevices()
  if uniqueID == requested ID: return device
  if exact localizedName == requested name: return device
  run current RunLoop for <= 250 ms
until deadline
return not found
```

如果名称匹配到多个设备，必须返回 ambiguous error，不能任意选择。

### 7.5 Camera 权限

启动前检查：

```swift
let status = AVCaptureDevice.authorizationStatus(for: .video)
```

至少区分：

- denied/restricted：`capture_permission_denied`；
- authorized：继续；
- notDetermined：宿主应用需要请求权限，CLI 首次调用可能触发系统提示。

### 7.6 AVCaptureSession

```swift
session.beginConfiguration()
session.sessionPreset = .high

let input = try AVCaptureDeviceInput(device: device)
guard session.canAddInput(input) else {
    throw CaptureError("capture_device_busy")
}
session.addInput(input)

output.alwaysDiscardsLateVideoFrames = true
output.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
]
output.setSampleBufferDelegate(self, queue: encodeQueue)

guard session.canAddOutput(output) else {
    throw CaptureError("capture_start_failed")
}
session.addOutput(output)
session.commitConfiguration()
session.startRunning()
```

`alwaysDiscardsLateVideoFrames = true` 是实时投影的关键设置。投影系统应丢弃过期帧，不应积压并延迟播放。

### 7.7 VideoToolbox encoder

从第一个 `CVPixelBuffer` 获取实际宽高，然后创建：

```swift
VTCompressionSessionCreate(
    allocator: kCFAllocatorDefault,
    width: Int32(width),
    height: Int32(height),
    codecType: kCMVideoCodecType_H264,
    encoderSpecification: nil,
    imageBufferAttributes: nil,
    compressedDataAllocator: nil,
    outputCallback: compressionOutputCallback,
    refcon: Unmanaged.passUnretained(self).toOpaque(),
    compressionSessionOut: &encoder
)
```

推荐配置：

```swift
VTSessionSetProperty(encoder,
    key: kVTCompressionPropertyKey_RealTime,
    value: kCFBooleanTrue)
VTSessionSetProperty(encoder,
    key: kVTCompressionPropertyKey_AllowFrameReordering,
    value: kCFBooleanFalse)
VTSessionSetProperty(encoder,
    key: kVTCompressionPropertyKey_ProfileLevel,
    value: kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel)
VTSessionSetProperty(encoder,
    key: kVTCompressionPropertyKey_ExpectedFrameRate,
    value: maxFPS as CFNumber)
VTSessionSetProperty(encoder,
    key: kVTCompressionPropertyKey_AverageBitRate,
    value: bitRate as CFNumber)
VTSessionSetProperty(encoder,
    key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
    value: maxFPS as CFNumber)
```

设计含义：

- `RealTime`：编码器优化实时路径；
- 禁用 frame reordering：不生成依赖重排序的 B-frame；
- Baseline profile：提高浏览器兼容性；
- 关键帧间隔约 1 秒：新 viewer 最多等待约一个 GOP；
- 6 Mbps / 30 FPS：适合作为 750x1334 屏幕的初始值，可配置。

### 7.8 AVCC 转 Annex B

VideoToolbox 通常输出 AVCC：

```text
[4-byte big-endian NAL length][NAL bytes]...
```

Web viewer 使用 Annex B：

```text
[00 00 00 01][NAL bytes]...
```

逐个读取 AVCC NAL length，替换为四字节 start code。

关键帧必须在 IDR 前附带 SPS 和 PPS：

```text
00 00 00 01 + SPS
00 00 00 01 + PPS
00 00 00 01 + IDR
```

SPS/PPS 通过 `CMVideoFormatDescriptionGetH264ParameterSetAtIndex` 获取。新浏览器只有收到 decoder configuration 后才能配置 `VideoDecoder`。

### 7.9 Orientation 和分辨率变化

每个 frame 检查 `CVPixelBufferGetWidth/Height`。若尺寸变化：

1. complete 旧 encoder pending frames；
2. invalidate 旧 encoder；
3. 创建新 encoder；
4. 发送新的 metadata；
5. 下一关键帧发送新的 SPS/PPS。

## 8. Helper stdout framing protocol

### 8.1 Metadata line

收到第一帧并确定尺寸后，stdout 首先输出一行 JSON：

```json
{
  "type": "ready",
  "deviceId": "capture-device-id",
  "screenWidth": 750,
  "screenHeight": 1334,
  "videoCodec": "h264"
}
```

JSON 后必须写一个 `0x0a` 换行。metadata 前不能输出日志。

### 8.2 Binary frame envelope

metadata 之后是连续二进制 frame：

| Offset | Size | Encoding | Description |
| --- | ---: | --- | --- |
| 0 | 4 | uint32 big-endian | H.264 payload length |
| 4 | 1 | uint8 | flags |
| 5 | 8 | uint64 big-endian | presentation timestamp in microseconds |
| 13 | N | bytes | one Annex B access unit |

flags：

- `0x01`：关键帧；
- `0x02`：包含 SPS/PPS decoder configuration。

选择 big-endian 是为了让 Swift、Go、Rust、JavaScript 等语言都能明确解析，避免依赖主机字节序。

## 9. Host orchestrator

### 9.1 语言要求

服务端语言只需要支持：

- 启动和停止子进程；
- 分别读取 stdout/stderr；
- 增量解析 byte stream；
- 创建 HTTP/WebSocket server；
- 转发 binary message；
- 处理信号和资源清理。

不需要在服务端解码或重新编码 H.264。

### 9.2 推荐抽象

```text
CaptureLauncher
  buildHelper()
  start(selector, options) -> CaptureSession
  close()

CaptureSession
  metadata: Future/Promise<Metadata>
  frames: AsyncStream<VideoFrameEnvelope>
  diagnostics: Future/Promise<String>
  completion: Future/Promise<ExitStatus>
  close()

ProjectionServer
  startCapture()
  attachViewer(websocket)
  detachViewer()
  close()
```

### 9.3 Selector resolution pseudocode

```text
xctraceOutput = run("xcrun", "xctrace", "list", "devices")
developmentDevices = parseXctrace(xctraceOutput)

mapped = find by:
  exact development UDID
  exact device name
  case-insensitive unique name prefix

if mapped exists:
  helperDeviceId = mapped.developmentUDID
  helperDeviceName = mapped.name
else:
  helperDeviceId = original selector
  helperDeviceName = absent

start helper stream once
```

Swift 会把 development UDID 匹配失败，然后用 name 找到 `AVCaptureDevice`。未映射 selector 则作为可能的 capture ID 直接匹配。

### 9.4 stdout parser

子进程 stdout chunk 不是协议 frame。必须维护增量 buffer：

```text
state = waitingMetadata
buffer = []

onStdoutChunk(chunk):
  append chunk to buffer

  if state == waitingMetadata:
    locate first newline
    if absent: return
    parse bytes before newline as UTF-8 JSON
    remove line and newline from buffer
    state = waitingFrames

  while buffer length >= 13:
    payloadLength = readUInt32BE(buffer, 0)
    envelopeLength = 13 + payloadLength
    if buffer length < envelopeLength: return
    emit exact envelope
    remove envelope from buffer
```

必须测试：

- metadata 被拆成多个 chunk；
- newline 与 frame header 位于同一 chunk；
- 13-byte header 被拆分；
- payload 被拆分；
- 一个 chunk 包含多个 frame；
- helper 在 metadata 前退出；
- payload length 异常或超限。

建议设置单帧上限，例如 16 MiB，防止损坏 length 导致无限等待或内存增长。

### 9.5 stderr 和错误码

stderr 完整收集，用稳定前缀映射错误：

| Code | Meaning |
| --- | --- |
| `capture_dependency_missing` | Swift/Xcode 工具不可用 |
| `capture_permission_denied` | Camera 权限拒绝 |
| `capture_device_not_found` | AVFoundation 未发布或未匹配设备 |
| `capture_device_busy` | 输入被其他应用占用 |
| `capture_start_failed` | Session/output 启动失败 |
| `video_encode_failed` | VideoToolbox 编码失败 |

如果 helper 在 metadata 前退出，优先返回 stderr 中的具体错误，不要只返回“stream truncated”。

### 9.6 Capture 生命周期

capture 属于 server，而不是 viewer：

```text
server start
  -> compile helper
  -> start capture helper once
  -> subscribe frames once

viewer connect
  -> send latest metadata
  -> forward current frames

viewer disconnect
  -> remove viewer sink only
  -> capture keeps running

server stop
  -> stop viewer
  -> cancel frame subscription
  -> terminate helper
  -> remove temporary executable
```

这样浏览器刷新不会重新触发 CoreMediaIO discovery，也不会造成设备反复占用和释放。

### 9.7 Pending startup shutdown

helper 可能已经启动，但在等待首帧，因此 `CaptureSession.metadata` 尚未完成。

server 的 `close()` 不能无条件等待 metadata future，否则永远执行不到 kill helper。

正确处理：

```text
close():
  mark closed
  close currently owned resources immediately
  ask launcher to terminate all child processes

if startup completes later:
  observe closed flag
  close newly returned session immediately
```

### 9.8 Viewer policy

最简单实现只允许一个 viewer。第二个连接返回：

```json
{
  "type": "error",
  "code": "viewer_busy",
  "message": "Another viewer is already attached."
}
```

如需多个 viewer，可维护 WebSocket sink 集合。需要注意：新 viewer 必须等到下一个包含 SPS/PPS 的 IDR 才能开始解码。更成熟的实现可缓存最近的 SPS/PPS 和 IDR。

## 10. WebSocket protocol

建议 endpoint：

```text
ws://127.0.0.1:<port>/session
```

### 10.1 Text messages

ready：

```json
{
  "type": "ready",
  "deviceId": "capture-device-id",
  "screenWidth": 750,
  "screenHeight": 1334,
  "videoCodec": "h264"
}
```

error：

```json
{
  "type": "error",
  "code": "capture_device_not_found",
  "message": "No trusted physical iOS capture device matched the selector."
}
```

### 10.2 Binary messages

每个 binary WebSocket message 对应一个完整的 13-byte header + H.264 payload envelope。

不要把任意 stdout chunk 直接作为 WebSocket message；stdout chunk 可能包含半个 frame 或多个 frame。

## 11. Web viewer

### 11.1 Envelope parsing

```js
function parseEnvelope(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer)
  if (bytes.length < 13) throw new Error('truncated header')

  const view = new DataView(
    bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const length = view.getUint32(0, false)
  if (bytes.length !== 13 + length) {
    throw new Error('payload length mismatch')
  }

  return {
    keyframe: (view.getUint8(4) & 0x01) !== 0,
    hasConfig: (view.getUint8(4) & 0x02) !== 0,
    timestamp: Number(view.getBigUint64(5, false)),
    accessUnit: bytes.subarray(13),
  }
}
```

### 11.2 Annex B inspection

识别 NAL type：

```text
nalType = nal[0] & 0x1f
1 = non-IDR slice
5 = IDR
7 = SPS
8 = PPS
```

从 SPS 的 profile、compatibility、level 字节生成 WebCodecs codec string：

```text
avc1.PPCCLL
```

例如：

```text
avc1.42c01f
```

### 11.3 VideoDecoder

```js
const decoder = new VideoDecoder({
  output(frame) {
    try {
      if (canvas.width !== frame.displayWidth ||
          canvas.height !== frame.displayHeight) {
        canvas.width = frame.displayWidth
        canvas.height = frame.displayHeight
      }
      context.drawImage(frame, 0, 0, canvas.width, canvas.height)
    } finally {
      frame.close()
    }
  },
  error(error) {
    console.error(error)
  },
})
```

收到 SPS/PPS 后：

```js
decoder.configure({
  codec: codecFromSPS,
  optimizeForLatency: true,
})
```

解码：

```js
decoder.decode(new EncodedVideoChunk({
  type: keyframe ? 'key' : 'delta',
  timestamp,
  data: accessUnit,
}))
```

### 11.4 Backpressure

实时投影优先低延迟：

```js
if (!keyframe && decoder.decodeQueueSize > 4) {
  return // drop stale delta frame
}
```

不能丢弃携带 SPS/PPS 的关键帧。Canvas 绘制完成后必须 `frame.close()`，否则浏览器会积累 GPU/native resources。

### 11.5 页面尺寸

使用 metadata 的 screen width/height 设置容器 aspect ratio。Canvas CSS 可 `width: 100%; height: 100%`，但 backing size 必须跟随解码 frame 的真实尺寸。

不要根据 viewport 宽度改变字体或视频像素尺寸，也不要拉伸破坏宽高比。

## 12. 关闭和信号处理

Swift helper 应处理 SIGTERM/SIGINT：

```text
disable sample-buffer delegate
complete pending encoder frames
invalidate VTCompressionSession
stop AVCaptureSession
stop main RunLoop
exit
```

orchestrator 关闭顺序：

```text
stop accepting HTTP/WebSocket
close viewer sockets
cancel frame forwarding
send SIGTERM to helper
wait bounded timeout
send SIGKILL if helper does not exit
delete temporary helper binary
```

必须有 SIGKILL fallback。设备或框架异常时，AVCaptureSession 停止可能卡住。

## 13. 故障诊断

### 13.1 `capture_device_not_found`

检查顺序：

1. iPhone 是否解锁且屏幕亮起；
2. USB trust 是否有效；
3. `xcrun xctrace list devices` 是否在线；
4. Camera 权限；
5. 是否错误运行了独立 helper `list` preflight；
6. stream 进程是否设置 CoreMediaIO property；
7. 设置后是否固定等待 1 秒；
8. 是否在同一 stream 进程内运行 RunLoop discovery；
9. capture ID 和设备名称是否匹配。

### 13.2 `capture_device_busy`

关闭：

- QuickTime Player；
- OBS；
- 旧 orchestrator；
- 残留 helper；
- 其他屏幕录制软件。

检查：

```sh
ps -axo pid,ppid,command | grep 'ios_capture stream'
```

### 13.3 Ready 但没有 binary frame

- 是否有另一个 helper 抢占设备；
- `captureOutput` delegate 是否收到 sample buffer；
- `VTCompressionSessionEncodeFrame` 是否返回 `noErr`；
- compression callback 是否执行；
- stdout 是否被日志污染；
- orchestrator 是否正确处理 pipe chunk boundaries；
- browser 是否错误地在 SPS/PPS 前配置 decoder。

### 13.4 浏览器黑屏但持续收到 frame

- 检查第一关键帧是否包含 SPS/PPS；
- 检查 AVCC 是否完整转换为 Annex B；
- 检查 codec string；
- 检查 timestamp 是否使用微秒；
- 检查 `VideoDecoder.state`；
- 检查浏览器 H.264 WebCodecs 支持；
- 检查是否把 13-byte envelope header 一并交给 decoder。

### 13.5 延迟不断增长

- capture output 是否丢弃 late frames；
- encoder 是否禁止 frame reordering；
- orchestrator 是否无界缓存；
- WebSocket buffered amount 是否持续增长；
- decoder queue 是否无界增长；
- 是否及时 drop delta frames；
- 是否及时关闭 VideoFrame。

## 14. 测试策略

### 14.1 Swift

- source 可编译；
- CoreMediaIO permission error；
- device-not-found timeout；
- session busy error；
- AVCC to Annex B；
- SPS/PPS prepend；
- keyframe/config flags；
- encoder dimension change；
- signal shutdown。

### 14.2 Orchestrator

- xctrace parser；
- development UDID/name mapping；
- unmatched capture ID 原样透传；
- 明确断言没有 helper-list preflight；
- metadata chunking；
- header/payload chunking；
- multiple frames per chunk；
- stderr error precedence；
- viewer reconnect does not restart capture；
- pending startup can be closed；
- late error after viewer close does not crash server。

### 14.3 Browser

- envelope length validation；
- Annex B NAL splitting；
- SPS codec extraction；
- key/delta chunk classification；
- decoder configuration changes；
- decode queue backpressure；
- Canvas resize；
- WebSocket reconnect state。

### 14.4 Physical-device acceptance

自动测试不能替代真实 iPhone。至少记录：

- iPhone model 和 iOS version；
- development UDID；
- capture ID；
- ready metadata；
- 第一个 IDR 到达时间；
- 连续 frame size；
- 浏览器 rendered FPS；
- 端到端延迟；
- viewer refresh 前后 helper PID；
- USB removal 行为；
- lock/unlock 行为；
- Camera permission denied 行为；
- server shutdown 后 helper 是否消失。

## 15. 已验证参考数据

一次物理 iPhone 验证得到：

```text
screenWidth: 750
screenHeight: 1334
codec: h264
first observed frame size: 16233 bytes
following frame sizes: 3039, 1031, 1118, 1419 bytes
```

独立 Swift stream 进程在一次运行中持续输出超过 4 MiB H.264 数据，stderr 为空。通过完整 orchestrator/WebSocket 链路也能连续收到 framed binary messages。

这些数据只作为协议和数量级参考，不能硬编码设备尺寸、DPR、bitrate 或 frame size。

## 16. 语言选择建议

### Go

优势：部署简单、子进程和 WebSocket 成熟、并发模型直接。适合独立本地 daemon。

注意：为 stdout parser 使用显式 byte buffer，不要用默认行扫描器处理 binary frames。

### Rust

优势：资源所有权清晰、二进制解析安全、适合长期运行 helper manager。

注意：异步 child stdout、signal 和 WebSocket runtime 的组合复杂度较高。

### Dart

优势：跨平台、异步 stream 易组合，适合快速实现本地 orchestrator。

注意：不要让 capture-start future 阻塞 shutdown。

### Node.js / TypeScript

优势：WebSocket 与浏览器协议共享类型，原型速度快。

注意：正确处理 `Buffer` slice 的 byteOffset，并避免 event-loop 上做重编码。

### Java/Kotlin/C#

同样可行。关键不是语言，而是遵守 framing、单 helper 生命周期和 backpressure 约束。

## 17. 生产化演进

1. 多 viewer fan-out，并保持唯一 capture owner；
2. 缓存最近 SPS/PPS 和 IDR；
3. 根据 WebSocket backlog 自适应 bitrate/FPS；
4. 增加 orientation/metadata event；
5. 增加 helper startup watchdog；
6. 使用 Unix domain socket 替代 stdout（如需更强双向控制）；
7. 增加 metrics：capture FPS、encode FPS、bytes/sec、drop count、decoder queue；
8. 增加 origin/authentication，避免本地恶意网页连接；
9. 对 helper binary 做签名和权限说明；
10. 将视频投影和设备控制保持为独立接口。

## 18. 核心原则总结

实现时必须保持以下原则：

1. `xctrace` 只负责 USB 开发设备身份，不提供视频；
2. 真正视频源是 CoreMediaIO 发布的 `AVCaptureDevice`；
3. discovery 和 `AVCaptureSession` 必须位于同一个长生命周期 Swift 进程；
4. 不运行独立 helper-list preflight；
5. 使用 VideoToolbox 实时编码，而不是先写 MOV；
6. 将 AVCC 转为带 SPS/PPS 的 Annex B；
7. stdout framing 必须抵抗任意 pipe chunk boundary；
8. capture 属于 server 生命周期，不属于浏览器连接；
9. 遇到 backpressure 时丢旧帧，不积累延迟；
10. 服务端语言可以自由选择，Swift helper 和 wire protocol 保持稳定。
