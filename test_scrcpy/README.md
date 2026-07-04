# Official scrcpy Server Calibration Demo

This is a throwaway capability demo for Ask UI Android device surface work.

It verifies a minimal path using the official scrcpy toolchain:

- Start official `scrcpy` in headless recording mode.
- Let official `scrcpy` push and supervise its matching `scrcpy-server`.
- Convert short recording segments through `ffmpeg` in the local bridge to expose browser-friendly JPEG frames.
- Send browser clicks back to the Android device with `adb shell input tap`.
- Send browser drag gestures back to the Android device with `adb shell input swipe`.
- Probe the official scrcpy 4.0 server raw H.264 stream through ADB reverse/forward.
- Send WebCodecs page pointer down/move/up events through the official scrcpy 4.0 control socket.

This is not product code and intentionally has no unit tests.

## Run

```sh
DEVICE_ID=19271FDF6007TY node test_scrcpy/server.mjs
```

Then open:

```text
http://127.0.0.1:3010
```

For the WebCodecs raw H.264 MVP, open:

```text
http://127.0.0.1:3010/webcodecs.html
```

Optional environment variables:

- `DEVICE_ID`: Android ADB serial. Required unless exactly one device is attached.
- `SCRCPY`: Path to the official scrcpy CLI. Defaults to `scrcpy`.
- `PORT`: HTTP port for this demo. Defaults to `3010`.
- `MAX_SIZE`: Maximum mirrored video size. Defaults to `1080`.
- `MAX_FPS`: Maximum mirrored frame rate. Defaults to `60` for the WebCodecs low-latency spike.
- `VIDEO_BIT_RATE`: H.264 bit rate. Defaults to `8000000`.
- `SEGMENT_SECONDS`: Length of each scrcpy capture segment. Defaults to `3`.
- `SCRCPY_SERVER`: Path to the official `scrcpy-server` binary. Defaults to the Homebrew scrcpy 4.0 path.
- `RAW_PORT`: Local TCP port used by the raw H.264 WebSocket bridge. Defaults to `27184`.
- `SCID`: scrcpy socket id suffix for raw streaming. Defaults to `2b3c4d5e`.

## Boundaries

- Video uses repeated short official scrcpy CLI/server capture segments, but browser playback is refreshed JPEG frames via `ffmpeg`, not the final Ask UI transport.
- The original JPEG demo still uses ADB input for clicks and drag gestures.
- The WebCodecs page uses the official scrcpy 4.0 raw H.264 Annex B stream through a local WebSocket and decodes it in the browser with `VideoDecoder`.
- The WebCodecs page uses a minimal access-unit grouping heuristic for calibration. It is not yet the production parser.
- The WebCodecs page is tuned for low latency rather than complete playback. It aggressively drops delta access units when `VideoDecoder.decodeQueueSize` grows, and it reports decoded frames, dropped frames, queue size, input bytes, and approximate FPS in the header.
- Server log rendering is throttled in the page so DOM logging does not dominate decode/render work.
- The WebCodecs page sends pointer events over the same browser WebSocket as JSON control messages. The Node bridge encodes them as official scrcpy touch control messages and writes them to the scrcpy control socket. This replaces the earlier `adb shell input tap/swipe` path for the WebCodecs page.

## Raw Stream Probe

Run:

```sh
DEVICE_ID=19271FDF6007TY node test_scrcpy/raw_stream_probe.mjs
```

The default probe path mirrors the official client socket direction:

1. Push the official `scrcpy-server` to `/data/local/tmp/scrcpy-server.jar`.
2. Open `adb reverse localabstract:scrcpy_<scid> tcp:<port>`.
3. Listen on `127.0.0.1:<port>` from Node.
4. Start the server with `app_process` and `raw_stream=true`.
5. Capture the video socket bytes into `/private/tmp/ask-ui-scrcpy-raw-probe.h264`.

Useful environment variables:

- `SCRCPY_SERVER`: official server binary path. Defaults to Homebrew scrcpy 4.0.
- `TUNNEL_MODE`: `reverse` by default; set `forward` to test `tunnel_forward=true`.
- `SCID`: socket suffix. Defaults to `1a2b3c4d`, yielding `scrcpy_1a2b3c4d`.
- `CAPTURE_MS`: capture duration. Defaults to `5000`.
- `OUTPUT`: output `.h264` sample path.

Expected success output includes `hasSps: true`, `hasPps: true`, and `hasIdr: true`.
