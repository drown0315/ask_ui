# iPhone 屏幕实时投影到 Web 的独立实施指南

## 1. 文档目的

本文描述一种已经过物理 iPhone 验证的本地屏幕投影方案。读者不需要拥有原项目源码，按照本文即可重新实现以下能力：

- macOS 通过 USB 实时采集受信任 iPhone 的屏幕；
- 使用 VideoToolbox 将屏幕帧编码为低延迟 H.264；
- 通过本地 WebSocket 把视频发送到浏览器；
- 浏览器通过 WebCodecs 解码并绘制到 Canvas；
- 可选地把浏览器点击、长按和单指滑动注入 Flutter debug 应用；
- Flutter 应用重启、浏览器刷新时不重启视频采集。

这是一套实时采集和实时传输方案，不是“先录制 MOV 文件，再读取文件播放”。

## 2. 能力边界

### 2.1 已覆盖

- 主机：macOS；
- 设备：一台通过 USB 连接、已解锁并信任 Mac 的物理 iPhone；
- 视频：iPhone 屏幕，无音频；
- 编码：H.264 Annex B；
- 浏览器：支持 WebCodecs 的 Chromium 系浏览器；
- 控制：仅限集成了 VM Service extension 的 Flutter debug 应用；
- 手势：点击、长按、单指拖动和滚动；
- 会话：一个持续采集进程、最多一个浏览器控制者、零或一个 Flutter 控制连接。

### 2.2 不覆盖

- 任意原生 iOS 应用控制；
- iOS 系统页面控制；
- Bluetooth HID、WebDriverAgent、ReplayKit 或 iPhone Mirroring；
- 音频、多点触控、键盘、Home/音量等硬件按钮；
- 多浏览器视频分发；
- 跨网络暴露服务或生产级认证。

视频采集和控制是两个独立能力。AVFoundation 能提供视频，不代表能够控制手机；Flutter VM Service 能控制特定 Flutter debug 应用，也不能控制系统或其他原生应用。

## 3. 总体架构

```text
物理 iPhone
  │ USB + macOS CoreMediaIO
  ▼
AVCaptureDevice
  ▼
AVCaptureSession + AVCaptureVideoDataOutput
  ▼ CMSampleBuffer / CVPixelBuffer
VideoToolbox VTCompressionSession
  ▼ H.264 Annex B access unit
Swift capture helper stdout
  ▼ 自定义二进制 framing
Dart 本地 server
  ▼ WebSocket binary message
浏览器 WebCodecs VideoDecoder
  ▼ VideoFrame
Canvas 2D
```

可选控制链路：

```text
浏览器 Pointer Events
  ▼ 归一化坐标和单指状态机
WebSocket JSON
  ▼
Dart server
  ▼ Flutter VM Service
自定义 service extension
  ▼ Flutter logical coordinates
PointerEvent 注入 Flutter binding
```

推荐进程划分：

```text
Dart server 生命周期
  ├── 一个持久 CaptureSession
  │    └── 一个 Swift helper 子进程
  ├── 零或一个 BrowserSession
  └── 零或一个可替换 ControlSession
```

不要把 capture 生命周期绑定到浏览器 WebSocket。浏览器刷新只更换接收者，不能停止 Swift helper。

## 4. 设备发现：两个 ID 域必须分开

macOS 上存在两套设备身份：

1. `xcrun xctrace list devices` 返回 Xcode/Flutter 使用的 development UDID，通常是 40 位十六进制字符串；
2. `AVCaptureDevice.uniqueID` 返回 AVFoundation capture ID，通常是 UUID 风格字符串。

示例：

```text
Flutter/Xcode UDID:
269bfd1ccaa634d5f2250efe6a22016b18fd16da

AVFoundation capture ID:
086CB555-1500-48BB-8F7A-51BF5F6C90C5
```

两者不能直接互换。可以通过设备显示名称关联，但名称可能重复，因此多个同名设备时必须要求用户提供 capture ID。

### 4.1 最终验证过的启动流程

```text
1. 执行 xcrun xctrace list devices
2. 如果 selector 是 development UDID 或设备名，解析出设备名
3. 启动唯一的 Swift stream helper
4. Swift helper 在自己的进程内启用 CoreMediaIO iOS screen devices
5. 同一个 Swift 进程完成 AVCaptureDevice discovery、选择、采集和编码
```

### 4.2 重要禁忌：不要先运行 helper list 再运行 helper stream

真机验证发现以下流程不稳定：

```text
错误流程：
Dart -> helper list 进程 -> 退出
     -> helper stream 新进程 -> capture_device_not_found
```

即使 `list` 已经打印出 iPhone，新的 `stream` 进程仍可能无法看到同一设备。CoreMediaIO 的设备发布与进程内 opt-in/discovery 生命周期有关。

正确做法是让最终持有 `AVCaptureSession` 的 stream 进程自行完成 discovery。`xctrace` 只用于确认 USB/Xcode 设备和把 Flutter UDID 映射到设备名，不用于提供视频。

如果用户直接传入 capture ID，而 xctrace 中没有这个 ID，Dart 应把 selector 原样交给 Swift，不能在启动前拒绝它。

## 5. Swift 采集 helper

### 5.1 依赖框架

```swift
import AVFoundation
import CoreMediaIO
import Foundation
import VideoToolbox
```

编译：

```sh
swiftc -parse-as-library ios_capture.swift -o ios_capture
```

### 5.2 启用 iOS 屏幕采集设备

设置 CoreMediaIO 全局属性：

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

    // 物理设备验证表明该 settle 不能省略。
    Thread.sleep(forTimeInterval: 1.0)
}
```

设置属性后设备是异步发布的。固定等待 1 秒后，仍应在当前进程的 RunLoop 上做有界轮询，例如最多 10 秒、每次 250 ms。

```swift
func waitForCaptureDeviceEvents(until deadline: Date) {
    RunLoop.current.run(
        until: min(deadline, Date().addingTimeInterval(0.25))
    )
}
```

不要只执行一次 `DiscoverySession` 后立即判定 not found。

### 5.3 枚举和选择 iPhone

```swift
let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.external, .builtInWideAngleCamera],
    mediaType: nil,
    position: .unspecified
)

let iosDevices = discovery.devices.filter {
    $0.modelID == "iOS Device" &&
    $0.manufacturer == "Apple Inc."
}
```

选择顺序：

1. 精确匹配 `uniqueID`；
2. 如果传入了 `--device-name`，精确匹配 `localizedName`；
3. 同名多设备时报歧义错误；
4. 超时后输出稳定错误码 `capture_device_not_found`。

推荐 CLI：

```text
ios_capture stream \
  --device-id '<capture-id-or-development-id>' \
  [--device-name '<exact-name>'] \
  --max-fps 30 \
  --bit-rate 6000000
```

当 Dart 已知 development UDID 和设备名时，Swift 可以忽略无法匹配的 development ID，回退到精确名称。直接使用 capture ID 时不需要设备名。

### 5.4 AVCaptureSession 配置

```swift
session.beginConfiguration()
session.sessionPreset = .high

let input = try AVCaptureDeviceInput(device: device)
guard session.canAddInput(input) else {
    throw CaptureError("capture_device_busy: cannot add capture input")
}
session.addInput(input)

output.alwaysDiscardsLateVideoFrames = true
output.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
]
output.setSampleBufferDelegate(self, queue: encodeQueue)

guard session.canAddOutput(output) else {
    throw CaptureError("capture_start_failed: cannot add video output")
}
session.addOutput(output)
session.commitConfiguration()
session.startRunning()
```

`alwaysDiscardsLateVideoFrames` 很重要。实时投影应丢弃旧帧，不能通过积压队列换取“每帧都编码”，否则延迟会持续增长。

### 5.5 VideoToolbox 实时 H.264

首次收到 `CVPixelBuffer` 后，根据真实 width/height 创建 encoder：

```swift
VTCompressionSessionCreate(
    allocator: kCFAllocatorDefault,
    width: Int32(width),
    height: Int32(height),
    codecType: kCMVideoCodecType_H264,
    encoderSpecification: nil,
    imageBufferAttributes: nil,
    compressedDataAllocator: nil,
    outputCallback: compressionCallback,
    refcon: Unmanaged.passUnretained(self).toOpaque(),
    compressionSessionOut: &encoder
)
```

低延迟属性：

```swift
VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_RealTime,
                     value: kCFBooleanTrue)
VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AllowFrameReordering,
                     value: kCFBooleanFalse)
VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_ProfileLevel,
                     value: kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel)
VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                     value: 30 as CFNumber)
VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_AverageBitRate,
                     value: 6_000_000 as CFNumber)
VTSessionSetProperty(encoder, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                     value: 30 as CFNumber)
```

关键设计：

- 禁用 B-frame，避免重排序延迟；
- 最大关键帧间隔约 1 秒，浏览器重连后能较快解码；
- 首帧或分辨率变化时重新创建 encoder；
- PTS 使用微秒整数传输；
- 编码失败写 stderr，绝不能混入 stdout 二进制流。

### 5.6 AVCC 转 Annex B

VideoToolbox 输出的 H.264 sample 通常采用 AVCC length-prefixed NAL。浏览器管线采用 Annex B，因此需要转换：

```text
AVCC:    [4-byte NAL length][NAL][4-byte NAL length][NAL]
Annex B: [00 00 00 01][NAL][00 00 00 01][NAL]
```

对关键帧，从 `CMVideoFormatDescriptionGetH264ParameterSetAtIndex` 提取 SPS 和 PPS，并放到 IDR 之前：

```text
00 00 00 01 + SPS
00 00 00 01 + PPS
00 00 00 01 + IDR
```

没有 SPS/PPS，新的浏览器 decoder 无法从中途加入。

## 6. Swift stdout 协议

stdout 只允许协议数据，stderr 只允许诊断。

### 6.1 首行 metadata

helper 在获得第一帧实际尺寸后输出一行 UTF-8 JSON，以换行结束：

```json
{
  "type": "ready",
  "deviceId": "086CB555-1500-48BB-8F7A-51BF5F6C90C5",
  "screenWidth": 750,
  "screenHeight": 1334,
  "logicalWidth": 250.0,
  "logicalHeight": 444.6666666667,
  "devicePixelRatio": 3.0,
  "videoCodec": "h264",
  "controlBackend": "flutterRuntime"
}
```

这里的 logical size 只是视频侧估值。Flutter control 连接后，应查询 Flutter view 并发送更新后的准确 logical size。

### 6.2 视频 frame envelope

metadata 换行后，stdout 是连续二进制 envelope：

| Offset | Length | Type | 含义 |
| --- | ---: | --- | --- |
| 0 | 4 | uint32 big-endian | payload 字节数 |
| 4 | 1 | uint8 | flags |
| 5 | 8 | uint64 big-endian | PTS，微秒 |
| 13 | payloadLength | bytes | 一个 Annex B access unit |

flags：

- bit 0 (`0x01`)：关键帧；
- bit 1 (`0x02`)：access unit 包含 SPS/PPS decoder configuration。

每个 WebSocket binary message 建议对应一个完整 envelope。不要让浏览器处理任意 stdout chunk，因为管道 chunk 边界不等于协议 frame 边界。

## 7. Dart server

### 7.1 为什么使用 Dart

Dart 不是视频编码层，只负责：

- 编译和管理 Swift helper；
- 解析 helper stdout framing；
- WebSocket 转发二进制消息；
- 管理生命周期和错误；
- 使用官方 `vm_service` 包连接 Flutter。

该负载下二进制转发不是主要瓶颈。使用 Dart 可以避免为了控制链路再引入一个 Go 到 Dart 的桥。

### 7.2 启动 helper

伪代码：

```dart
final xctrace = await Process.run(
  'xcrun', ['xctrace', 'list', 'devices']);

final mapped = resolveDevelopmentSelector(selector, xctrace.stdout);
final arguments = <String>[
  'stream',
  '--device-id', mapped?.developmentId ?? selector,
  if (mapped != null) ...['--device-name', mapped.name],
  '--max-fps', '30',
  '--bit-rate', '6000000',
];

final process = await Process.start(helperPath, arguments);
```

再次强调：这里不要调用 `helper list` 做启动前验证。

### 7.3 stdout 增量解析

解析器维护一个 byte buffer：

1. metadata 未完成时查找第一个 `0x0a`；
2. 解码换行前 JSON；
3. 之后只要 buffer 至少 13 bytes，就读取 payload length；
4. buffer 达到 `13 + payloadLength` 后产出一个 frame；
5. 保留剩余 bytes，等待下一管道 chunk。

需要覆盖以下测试：

- metadata 被拆成多个 stdout chunk；
- header 被拆分；
- payload 被拆分；
- 一次 chunk 包含多个 frame；
- helper 在 metadata 前退出；
- stderr 的稳定错误码优先于笼统的 truncated stream 错误。

### 7.4 持久 capture 生命周期

server 构造或显式 start 时只创建一次 capture：

```dart
capture = await captureFactory();
metadata = await capture.metadata;
frameSubscription = capture.frames.listen((frame) {
  currentBrowser?.sink.add(frame.encode());
});
```

浏览器断开时：

- 发送/注入 pointer cancel；
- 清空 browser slot；
- 不取消 frame subscription；
- 不关闭 control；
- 不关闭 capture/helper。

server 退出时才按顺序关闭：

```text
HTTP listener
-> active pointer
-> browser socket
-> frame subscription
-> control backend
-> capture session
-> helper launcher temporary directory
```

`close()` 不能无条件等待尚未完成的 capture start future。helper 可能已启动却一直没有首帧，如果 close 等待同一个 future，程序永远无法执行到 kill helper。正确做法：

- 标记 server closed；
- 立即关闭当前已拥有的资源；
- capture factory 以后才返回时，看到 closed 标志后立即关闭新资源。

### 7.5 单浏览器策略

MVP 可以限制一个 browser session：

```json
{
  "type": "error",
  "code": "controller_busy",
  "message": "Another browser already controls this session."
}
```

收到该错误时先检查是否存在第二个标签页或残留 WebSocket。生产方案若要多 viewer，应拆分“视频订阅者集合”和“唯一控制 owner”，而不是把所有 viewer 都称为 controller。

## 8. 浏览器视频解码

### 8.1 WebSocket 消息分类

- `string`：JSON metadata、control state 或 error；
- `ArrayBuffer`：13-byte header + Annex B access unit。

浏览器必须检查 payload length，不能直接把整个 envelope 交给 decoder。

### 8.2 推导 WebCodecs codec string

解析 Annex B NAL type：

- type 7：SPS；
- type 8：PPS；
- type 5：IDR；
- type 1：非 IDR slice。

从 SPS 的 profile/compatibility/level 三个字节生成：

```text
avc1.PPCCLL
```

例如：

```text
avc1.42c01f
```

只有收到包含 SPS/PPS 的 access unit 后才调用：

```ts
decoder.configure({ codec, optimizeForLatency: true })
```

随后：

```ts
decoder.decode(new EncodedVideoChunk({
  type: isKeyframe ? 'key' : 'delta',
  timestamp: ptsMicros,
  data: annexBAccessUnit,
}))
```

### 8.3 延迟控制

- `decodeQueueSize > 4` 时丢弃非关键帧；
- 不丢 SPS/PPS 或关键帧；
- decoder 输出后立即 `VideoFrame.close()`；
- Canvas backing size 跟随 `frame.displayWidth/displayHeight`；
- 不使用 CSS 拉伸破坏宽高比。

## 9. Flutter debug 控制

### 9.1 独立生命周期的原因

首次激活 iPhone capture 可能终止或断开正在运行的 Flutter debug 应用。因此正确顺序是：

```text
1. 启动 server 和 capture
2. 等视频稳定
3. 启动或重启 Flutter demo
4. 用新的 VM Service URI attach control
```

Flutter 每次重启 URI 都可能变化，不能把 URI 固化到 capture 启动参数中。

### 9.2 动态 control API

```http
PUT /control
Content-Type: application/json

{"vmServiceUri":"http://127.0.0.1:62076/token=/"}
```

也可接受 `ws://.../ws`。服务端把 HTTP URI 转换为 VM Service WebSocket URI。

解绑：

```http
DELETE /control
```

控制替换必须原子化：

1. 创建 candidate backend；
2. 连接 VM Service；
3. 查询 Flutter logical view metadata；
4. candidate 全部成功后才替换 old backend；
5. cancel active pointer；
6. 广播新的 ready metadata；
7. 广播 control ready；
8. 最后关闭 old backend。

candidate 失败时必须保留原来的可用 backend。

### 9.3 浏览器控制状态

```json
{"type":"control","state":"unavailable"}
{"type":"control","state":"connecting"}
{"type":"control","state":"ready"}
```

视频状态与 control 状态必须分开。control unavailable 时继续显示视频，只禁用 pointer 注入。

### 9.4 Pointer 协议

```json
{
  "type": "pointer",
  "action": "down",
  "x": 0.25,
  "y": 0.60,
  "pointerId": 0
}
```

约束：

- action：`down | move | up | cancel`；
- x/y：视频有效内容区域内的 `[0, 1]` 归一化坐标；
- MVP 只接受 `pointerId = 0`；
- move 最多约 30 Hz；
- 浏览器断开、control detach 或替换时必须发送 cancel。

如果 Canvas 使用 contain/letterbox，归一化必须基于实际视频矩形，而不是整个 Canvas DOM 矩形，否则点击会偏移。

Flutter 侧使用 runtime 查询得到的 logical width/height：

```text
flutterX = normalizedX * logicalWidth
flutterY = normalizedY * logicalHeight
```

不要长期使用视频像素除以硬编码 DPR 代替 Flutter view metadata。

## 10. 启动和验收流程

### 10.1 前置检查

```sh
xcrun xctrace list devices
```

确认 iPhone 位于 `== Devices ==` 而不是 `== Devices Offline ==`。

系统条件：

- iPhone 已解锁、屏幕亮起；
- 已选择“信任此电脑”；
- Terminal 或运行 server 的宿主具有 Camera 权限；
- QuickTime、OBS 等没有占用 iPhone capture；
- 使用满足项目 SDK 约束的新 Dart，而不是系统中较旧的 Dart。

### 10.2 启动视频 server

```sh
dart run bin/server.dart \
  --device-id '<capture-id-or-flutter-udid-or-device-name>' \
  --web-root ../web/dist \
  --port 8765
```

打开：

```text
http://127.0.0.1:8765
```

### 10.3 接入 Flutter 控制

```sh
flutter run -d '<flutter-device-id>'
```

复制 VM Service URI：

```sh
curl -X PUT http://127.0.0.1:8765/control \
  -H 'content-type: application/json' \
  -d '{"vmServiceUri":"http://127.0.0.1:<port>/<token>=/"}'
```

### 10.4 最小验收清单

视频：

- WebSocket 首先收到 ready metadata；
- 随后收到 `control: unavailable` 或 `ready`；
- 连续收到 binary frame；
- 首个可解码 access unit 包含 SPS、PPS、IDR；
- Canvas 内容持续变化；
- 浏览器刷新后 helper PID 不变；
- 只有 server 退出才停止 helper。

控制：

- click 触发 Flutter button；
- 按住至少 600 ms 触发 long press；
- 单指上划使 Flutter scroll position 增加；
- Flutter 重启后重新 PUT 新 URI，无需重启 capture；
- control 断开时视频继续。

## 11. 错误诊断

### `capture_device_not_found`

依次检查：

1. `xcrun xctrace list devices` 是否在线；
2. iPhone 是否解锁和亮屏；
3. Camera 权限；
4. 是否错误地在 stream 前运行了独立 helper `list`；
5. stream helper 是否在设置 CoreMediaIO property 后等待至少 1 秒；
6. 是否在同一个 stream 进程内轮询 discovery；
7. 直接传 capture ID 是否成功。

不要因为 xctrace 能发现设备就认为 AVFoundation 一定已发布视频设备。xctrace 不是视频采集 API。

### `capture_device_busy`

关闭 QuickTime、OBS、旧 server 和残留 helper。可检查：

```sh
ps -axo pid,ppid,command | grep 'ios_capture stream'
```

### `controller_busy`

已有一个 `/session` WebSocket。关闭其他标签页或旧 probe。该错误与 capture 无关。

### 页面 ready 但没有视频 frame

- 检查是否有另一个 helper 占用设备；
- 检查 Swift encoder callback 是否触发；
- 检查 stdout 是否只有 metadata、没有 frame bytes；
- 检查 Dart framing parser 是否等待了错误的 payload length；
- 检查浏览器是否在收到 SPS/PPS 前调用 decoder；
- 检查 decoder queue 是否积压。

### Flutter 启动后 control unavailable

- VM Service URI 是否为本次启动的新 URI；
- service extension 是否注册在 main isolate；
- HTTP URI 是否正确转换为 WebSocket URI；
- Flutter app 是否为 debug build；
- control attach 失败不能关闭 capture。

## 12. 测试策略

采用纵向 TDD：每个行为先观察失败，再做最小实现。

Swift/协议层：

- AVCC 到 Annex B；
- SPS/PPS/IDR flags；
- big-endian header；
- metadata 和 binary 严格分流；
- Swift 编译 gate；
- 真实设备 direct stream probe。

Dart：

- xctrace parser；
- development UDID/name 映射；
- capture ID 未出现在 xctrace 时原样透传；
- 明确断言启动过程中没有 helper `list` preflight；
- stdout 任意 chunk 边界解析；
- capture 只启动一次；
- 浏览器重连不关闭 capture/control；
- server close 能处理 pending capture start；
- PUT control 成功替换；
- replacement 失败保留旧 backend；
- DELETE control 只关闭控制；
- closed browser 上的迟到错误不能逃逸。

Web：

- Annex B NAL 切分；
- SPS codec string；
- decoder key/delta 分类；
- video/control reducer 独立；
- pointer 归一化和 letterbox；
- long press 计时；
- move throttle；
- socket close cancel。

自动测试不能替代真实 iPhone。最终必须记录：设备/iOS 版本、capture ID、ready metadata、连续 frame 大小、浏览器 FPS、helper PID、Flutter click/long press/scroll 结果。

## 13. 已验证参考数据

一次物理设备验证结果：

```text
设备：iPhone, iOS 15.8.8
capture ID：086CB555-1500-48BB-8F7A-51BF5F6C90C5
视频尺寸：750 x 1334
WebSocket 状态：ready -> control unavailable
连续 H.264 frame：16233, 3039, 1031, 1118, 1419 bytes
```

直接 Swift stream probe 曾在一次运行中输出超过 4 MB 的 H.264 数据，stderr 为空。这验证了链路是持续实时采集，而不是录制文件完成后的回放。

## 14. 后续演进建议

1. 把单 browser slot 拆成多个只读 video subscribers 和一个 control owner；
2. 缓存最近 SPS/PPS 与 IDR，缩短新 viewer 加入时间；
3. 根据网络/decoder backlog 动态调整 bitrate 和 FPS；
4. 从硬编码 DPR 估值升级为方向/尺寸变化 metadata 事件；
5. 增加 helper startup timeout 和结构化 stderr event；
6. 增加 capture process watchdog，但避免自动重启造成设备争用循环；
7. 如果要控制任意 iOS 界面，独立评估 Bluetooth HID 或 WDA，不要修改已稳定的视频协议；
8. 生产化时增加认证、origin 检查、端口冲突处理和进程托管。

这套架构最重要的原则是：视频采集、浏览器观看和应用控制分别拥有清晰的生命周期；单一 Swift stream 进程独占 AVFoundation discovery 与 capture；所有重连都只替换必要的那一层。
