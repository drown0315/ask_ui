# scrcpy Capability Calibration

Date: 2026-07-03

## Product Expectations

- Show the Android Target Device screen inside the Ask UI Live App Surface.
- Forward pointer input from the Live App Surface to the same Android Target Device.
- Bind all Android screen and input work to the `deviceId` provided in the page URL.

## Technical Approach

- Local tools: `adb` and `scrcpy`.
- Observed versions:
  - `adb`: Android Debug Bridge 1.0.41, version 35.0.1-11580240.
  - `scrcpy`: 4.0.
- Observed device:
  - ADB serial: `19271FDF6007TY`.
  - Model: `Pixel_6`.
  - Android: 14.
  - Display 0: `1080x2400`.

## Evidence

- `adb devices -l` listed one authorized USB device: `19271FDF6007TY device ... model:Pixel_6`.
- `scrcpy -s 19271FDF6007TY --list-displays` reported display `--display-id=0 (1080x2400)`.
- `scrcpy -s 19271FDF6007TY --no-window --no-audio --time-limit=2` connected to the device but logged `No video playback, no recording, no V4L2 sink: video disabled`.
- `scrcpy -s 19271FDF6007TY --no-video-playback --no-audio --record=/private/tmp/ask-ui-scrcpy-calibration.mp4 --time-limit=2` recorded an MP4 file.
- `ffprobe /private/tmp/ask-ui-scrcpy-calibration.mp4` reported H.264 video at `1080x2400`.
- `adb -s 19271FDF6007TY shell input` reported support for `tap`, `swipe`, `draganddrop`, `motionevent`, `scroll`, and display targeting with `-d DISPLAY_ID`.
- `/Users/drown/ai_project/bridge-rs` exposes `/bridge/` as a WebSocket that forwards browser binary packets to the local ADB server and ADB binary packets back to the browser.
- `/Users/drown/ai_project/ws-scrcpy` does not use the desktop `scrcpy` CLI for browser embedding. It pushes a `scrcpy-server.jar`, runs it with `app_process`, forwards device port `8886` through ADB, proxies that WebSocket to the browser, decodes H.264 frames in the browser, and sends scrcpy control messages back over the same stream.
- The local official scrcpy 4.0 install includes `/opt/homebrew/Cellar/scrcpy/4.0/share/scrcpy/scrcpy-server`, which differs from the `ws-scrcpy` vendored jar. The official server should be calibrated separately before committing to wire protocol details.
- `test_scrcpy/` contains a minimal local demo using the official scrcpy CLI/server pair. It starts a browser page, captures short official scrcpy recording segments, converts them to JPEG frames with `ffmpeg`, and sends clicks back with `adb shell input tap`.
- Official scrcpy 4.0 source shows the default client path uses `adb reverse`: the desktop listens first, then the Android server connects to `localabstract:scrcpy_<scid>`. The `adb forward` fallback requires `tunnel_forward=true`.
- Official scrcpy 4.0 source shows `raw_stream=true` disables device metadata, frame metadata, dummy byte, and stream metadata. The video socket then carries raw H.264 Annex B NAL bytes.
- `test_scrcpy/raw_stream_probe.mjs` validated the default reverse path on device `19271FDF6007TY`: it received `402129` bytes with H.264 NAL types `1`, `5`, `7`, and `8`, so SPS/PPS/IDR are present.
- The same probe validated the forward fallback path with `tunnel_forward=true`: it received `706081` bytes with SPS/PPS/IDR present.
- `ffprobe /private/tmp/ask-ui-scrcpy-raw-probe.h264` recognized the sample as H.264 video at `486x1080`, and `ffmpeg` extracted a JPEG frame.
- `ffprobe -show_streams /private/tmp/ask-ui-scrcpy-raw-probe.h264` reported H.264 High Profile with `mime_codec_string=avc1.640034`, `is_avc=false`, and no B-frames.
- W3C WebCodecs AVC registration states that AVC `EncodedVideoChunk` data may be Annex B, and that absence of `VideoDecoderConfig.description` means the bitstream is treated as `annexb`.
- MDN documents `VideoDecoder` as a secure-context WebCodecs API for decoding video chunks, with `VideoDecoder.isConfigSupported()` for capability checks.
- Local Chrome headless at `http://127.0.0.1` reported `isSecureContext=true`, `VideoDecoder=function`, `EncodedVideoChunk=function`, and `VideoDecoder.isConfigSupported({ codec: "avc1.640034", optimizeForLatency: true }).supported=true`.
- MDN documents `MediaSource.isTypeSupported()` as a MIME/codec support check whose `true` result means the user agent can probably play that media type.
- Local Chrome headless at `http://127.0.0.1` reported `MediaSource=function`, `MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E"')=true`, and `MediaSource.isTypeSupported('video/mp4; codecs="avc1.640034"')=true`.
- W3C MSE ISO BMFF byte stream format defines initialization segments and media segments for ISO BMFF; this implies the current raw Annex B stream must be packaged before being appended to MSE.
- `/Users/drown/ai_project/ws-scrcpy` confirms the same split in practice: its WebCodecs player parses SPS and configures `VideoDecoder`, while its MSE player uses `h264-converter` to create MP4 containers from NALU before feeding `MediaSource`.
- `test_scrcpy/webcodecs.html` now verifies the live route end to end: official scrcpy 4.0 raw H.264 over WebSocket, WebCodecs decode to canvas, and pointer down/move/up sent through the official scrcpy control socket.

## Capability Matrix

| Product capability | Technical evidence | Status | Decision |
| --- | --- | --- | --- |
| Target Android device by URL `deviceId` | `scrcpy -s <serial>` and `adb -s <serial>` both work | Supported | Current contract |
| Discover mirrored display size | `scrcpy --list-displays` and `adb shell wm size` report `1080x2400` | Supported | Current contract |
| Send basic click input | WebCodecs page sends pointer down/up over official scrcpy control socket | Supported | Current contract, bridge-owned |
| Send drag/swipe input | WebCodecs page sends pointer down/move/up over official scrcpy control socket | Supported | Current contract, bridge-owned |
| Embed scrcpy CLI directly as a browser live stream | scrcpy CLI help exposes SDL playback, recording, Linux-only V4L2 sink, and no browser stream endpoint | Unsupported | Do not expose as current contract |
| Run scrcpy without native playback and still receive video | `--no-window` disables video unless recording or another sink exists | Partial | Spike required for browser live stream |
| Record device screen to file | `--record=...mp4` produced H.264 MP4 | Supported | Adapter-internal evidence only, not enough for live surface |
| Embed scrcpy-server stream in Web | `test_scrcpy/webcodecs.html` decodes official raw H.264 with WebCodecs and renders to canvas | Supported | Current bridge video transport candidate |
| Send input over scrcpy control protocol | Node encodes official scrcpy touch messages and writes them to the control socket | Supported | Current bridge input candidate |
| Use official scrcpy server binary | Homebrew provides official `scrcpy-server` for scrcpy 4.0; raw stream probe pushed and ran it with `app_process` | Supported | Current bridge implementation target |
| Receive official raw H.264 in Node | `test_scrcpy/raw_stream_probe.mjs` received SPS/PPS/IDR over both reverse and forward tunnel paths | Supported | Current bridge video transport candidate |
| Embed official scrcpy output in a Web page as refreshed frames | `test_scrcpy/` returns JPEG frames produced from short official scrcpy recording segments | Supported | Calibration demo only |
| Decode official raw H.264 with WebCodecs | Local Chrome supports `VideoDecoder`; `test_scrcpy/webcodecs.html` renders the live stream | Supported | Preferred current implementation direction |
| Decode official raw H.264 with MSE | Local Chrome supports `video/mp4` AVC MIME strings, but MSE ISO BMFF requires init/media segments | Partial | Compatibility path after fMP4 packaging spike |
| Append raw Annex B bytes directly to MSE | MSE ISO BMFF byte stream format expects ISO BMFF segments, not arbitrary raw Annex B NAL bytes | Unsupported | Do not implement directly |
| Use Broadway/TinyH264 software decode | `ws-scrcpy` includes working references, but this adds CPU/package/maintenance cost | Future | Fallback candidate only |

## Contract Changes

- Current: `deviceId` should be an ADB/scrcpy serial and must target the same Android device as the Flutter `vmServiceUri`.
- Current: bridge should inject touch through the official scrcpy control socket after mapping Live App Surface coordinates to video/display coordinates. ADB input remains a fallback/debug path only.
- Current direction: use the official scrcpy server binary as the first implementation target. Use the reverse tunnel path first, matching the official client, with forward/tunnel_forward as fallback.
- Current video transport candidate: official raw H.264 Annex B stream from `raw_stream=true`.
- Current Web playback direction: WebCodecs first. Feed Annex B access units to `VideoDecoder` without `VideoDecoderConfig.description`, after parsing SPS for `avc1.xxxxxx`, dimensions, and keyframe readiness.
- Compatibility direction: MSE requires fMP4 packaging (`ftyp`/`moov` init segment plus `moof`/`mdat` media segments) before `SourceBuffer.appendBuffer()`.
- Current demo: `test_scrcpy/` verifies official scrcpy 4.0 raw H.264 live streaming, WebCodecs canvas rendering, and scrcpy control socket touch input.
- Production work required: replace the calibration parser/session code with bounded buffers, explicit backpressure, tested access-unit assembly, and bridge-owned lifecycle APIs.
- Removed: the desktop `scrcpy` CLI window should not be the primary browser embedding mechanism.
