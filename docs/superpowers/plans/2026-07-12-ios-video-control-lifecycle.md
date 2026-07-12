# iOS Video And Control Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep iPhone video capture alive across Flutter and browser restarts, and attach a relaunched Flutter demo through a replaceable VM Service control session.

**Architecture:** `MvpServer` owns one hot `CaptureSession` for its full lifetime and forwards frames to at most one current browser. A separate control slot is attached through loopback `PUT /control`, replaced atomically, and removed through `DELETE /control`; control failures never close capture. The CLI makes the initial VM Service URI optional, and the web client renders video and control states independently.

**Tech Stack:** Dart (`shelf`, `shelf_web_socket`, `vm_service`), Swift AVFoundation/VideoToolbox helper, Vite + React + TypeScript, Flutter debug VM Service extension.

---

## File Map

- Modify `ios_screen_mvp/server/lib/mvp_server.dart`: persistent capture owner, browser sink, control slot, and `/control` HTTP handler.
- Modify `ios_screen_mvp/server/bin/server.dart`: optional initial VM URI and ordered shutdown.
- Modify `ios_screen_mvp/server/test/mvp_server_test.dart`: capture/browser/control lifecycle contracts.
- Create `ios_screen_mvp/web/src/session/sessionState.ts`: pure ready/control/error state reduction.
- Create `ios_screen_mvp/web/src/session/sessionState.test.ts`: browser state tests.
- Modify `ios_screen_mvp/web/src/IosScreenDemo.tsx`: consume independent video/control messages and gate pointer input.
- Modify `ios_screen_mvp/web/src/IosScreenDemo.css`: control-state presentation without changing canvas dimensions.
- Modify `ios_screen_mvp/README.md`: capture-first launch and dynamic control attachment workflow.

### Task 1: Move Capture Ownership To The Server Lifetime

**Files:**
- Modify: `ios_screen_mvp/server/lib/mvp_server.dart`
- Modify: `ios_screen_mvp/server/test/mvp_server_test.dart`

- [ ] **Step 1: Write failing persistent-capture tests**

Add tests using the existing `FakeCaptureSession` and real loopback WebSockets:

```dart
test('starts capture once and reuses it across browser reconnects', () async {
  final first = await connectSession(server.port);
  await expectReady(first);
  await first.sink.close();

  final second = await connectSession(server.port);
  await expectReady(second);

  expect(captureFactoryCalls, 1);
  expect(capture.closed, isFalse);
  await second.sink.close();
});

test('server close releases persistent capture and control', () async {
  await mvp.close();
  expect(capture.closed, isTrue);
  expect(control.closed, isTrue);
});
```

Update the existing disconnect assertion so browser close expects pointer `cancel` but does not expect capture/control closure.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
cd ios_screen_mvp/server
dart test test/mvp_server_test.dart
```

Expected: FAIL because each WebSocket still calls `captureFactory` and closes capture in its `finally` block, and `MvpServer.close()` does not exist.

- [ ] **Step 3: Implement a hot server-owned capture session**

Refactor `MvpServer` around these ownership fields and methods:

```dart
final class MvpServer {
  late final Handler handler;
  late final Future<void> _captureStarted;
  CaptureSession? _capture;
  StreamSubscription<VideoFrameEnvelope>? _frameSubscription;
  DeviceMetadata? _captureMetadata;
  Object? _captureError;
  WebSocketChannel? _browser;
  PointerMessage? _activePointer;
  ControlBackend? _control;
  bool _closed = false;

  MvpServer({
    required String webRoot,
    required CaptureSessionFactory captureFactory,
    required ControlBackendFactory controlFactory,
  }) : _controlFactory = controlFactory {
    handler = Cascade()
        .add(_controlHandler)
        .add(_sessionHandler)
        .add(createStaticHandler(webRoot, defaultDocument: 'index.html'))
        .handler;
    _captureStarted = _startCapture(captureFactory);
  }

  Future<void> _startCapture(CaptureSessionFactory factory) async {
    try {
      final capture = await factory();
      _capture = capture;
      _captureMetadata = await capture.metadata;
      _frameSubscription = capture.frames.listen(
        (frame) => _browser?.sink.add(frame.encode()),
        onError: _handleCaptureError,
      );
    } catch (error) {
      _captureError = error;
      _sendErrorToBrowser(error);
    }
  }
}
```

WebSocket connect waits for `_captureStarted`, sends capture error or current metadata, then installs only the browser sink. Its `finally` path cancels the active pointer and clears `_browser`; it does not cancel `_frameSubscription`, `_control`, or `_capture`.

Implement ordered server cleanup:

```dart
Future<void> close() async {
  if (_closed) return;
  _closed = true;
  await _cancelActivePointer();
  await _browser?.sink.close();
  await _frameSubscription?.cancel();
  await _control?.close();
  await _capture?.close();
}
```

- [ ] **Step 4: Run focused and full server verification**

Run:

```sh
dart test test/mvp_server_test.dart
dart test
dart analyze
```

Expected: all server tests pass and analyzer reports no issues.

- [ ] **Step 5: Commit the persistent capture slice**

```sh
git add ios_screen_mvp/server/lib/mvp_server.dart ios_screen_mvp/server/test/mvp_server_test.dart
git commit -m "fix: keep ios capture alive across browser sessions"
```

### Task 2: Add Replaceable VM Service Control Attachment

**Files:**
- Modify: `ios_screen_mvp/server/lib/mvp_server.dart`
- Modify: `ios_screen_mvp/server/test/mvp_server_test.dart`

- [ ] **Step 1: Write failing control endpoint tests**

Change the injected factory contract to accept the requested URI:

```dart
typedef ControlBackendFactory = Future<ControlBackend> Function(
  DeviceMetadata metadata,
  Uri vmServiceUri,
);
```

Add loopback HTTP tests:

```dart
test('PUT control attaches after capture and updates ready metadata', () async {
  final response = await putControl(server.port, 'http://127.0.0.1:62076/token=/');
  expect(response.statusCode, 200);
  expect(controlUris, [Uri.parse('http://127.0.0.1:62076/token=/')]);
  expect(await nextTextMessage(browser), contains('"state":"ready"'));
  expect(await nextTextMessage(browser), contains('"logicalWidth":375.0'));
});

test('failed replacement preserves the previous ready control', () async {
  await putControl(server.port, firstUri);
  controlFactoryError = StateError('new VM unavailable');
  final response = await putControl(server.port, secondUri);
  expect(response.statusCode, 503);
  expect(firstControl.closed, isFalse);
});

test('DELETE control cancels the pointer and closes only VM control', () async {
  await sendPointerDown(browser);
  final response = await deleteControl(server.port);
  expect(response.statusCode, 200);
  expect(control.messages.last.action, 'cancel');
  expect(control.closed, isTrue);
  expect(capture.closed, isFalse);
});
```

Also assert pointer JSON received without a ready control returns `runtime_control_unavailable` while binary frames continue.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
cd ios_screen_mvp/server
dart test test/mvp_server_test.dart
```

Expected: compile or assertion failure because `/control`, URI-aware factory calls, and independent control state do not exist.

- [ ] **Step 3: Implement atomic attach, detach, and state messages**

Add a loopback handler that accepts only JSON object bodies with a non-empty HTTP/HTTPS/WS/WSS `vmServiceUri`:

```dart
Future<Response> _controlHandler(Request request) async {
  if (request.url.path != 'control') return Response.notFound('');
  if (request.method == 'PUT') {
    final decoded = jsonDecode(await request.readAsString());
    if (decoded is! Map<String, Object?> || decoded['vmServiceUri'] is! String) {
      return _jsonResponse(400, {'state': 'error', 'code': 'invalid_control_message'});
    }
    return _attachControl(Uri.parse(decoded['vmServiceUri'] as String));
  }
  if (request.method == 'DELETE') {
    await _detachControl();
    return _jsonResponse(200, {'state': 'unavailable'});
  }
  return Response(405, headers: {'allow': 'PUT, DELETE'});
}
```

Build a candidate backend before replacing the old backend. Resolve Flutter metadata through the candidate, then cancel the active pointer, swap `_control` and `_captureMetadata`, send updated `ready` followed by `control ready`, and finally close the old backend. If candidate creation or metadata resolution fails, close only the candidate, retain the old backend, restore its ready/unavailable state, and return HTTP 503.

Control state JSON is always:

```dart
{'type': 'control', 'state': 'unavailable' | 'connecting' | 'ready'}
```

Pointer handling checks `_control`; when null it sends a `ControlError` with code `runtime_control_unavailable` and leaves browser/capture active.

- [ ] **Step 4: Run focused and full server verification**

Run:

```sh
dart test test/mvp_server_test.dart
dart test
dart analyze
```

Expected: all server tests pass and analyzer reports no issues.

- [ ] **Step 5: Commit the dynamic control slice**

```sh
git add ios_screen_mvp/server/lib/mvp_server.dart ios_screen_mvp/server/test/mvp_server_test.dart
git commit -m "feat: attach flutter control without restarting video"
```

### Task 3: Wire CLI, Browser State, Documentation, And Real Device Flow

**Files:**
- Modify: `ios_screen_mvp/server/bin/server.dart`
- Create: `ios_screen_mvp/web/src/session/sessionState.ts`
- Create: `ios_screen_mvp/web/src/session/sessionState.test.ts`
- Modify: `ios_screen_mvp/web/src/IosScreenDemo.tsx`
- Modify: `ios_screen_mvp/web/src/IosScreenDemo.css`
- Modify: `ios_screen_mvp/README.md`

- [ ] **Step 1: Write failing browser session-state tests**

Define the intended pure reducer API in `sessionState.test.ts`:

```typescript
expect(reduceSessionMessage(initialSessionState, {
  type: 'control', state: 'unavailable',
})).toMatchObject({ videoState: 'connecting', controlState: 'unavailable' })

expect(reduceSessionMessage(initialSessionState, readyMetadata)).toMatchObject({
  videoState: 'live', metadata: readyMetadata,
})

expect(reduceSessionMessage(liveState, {
  type: 'control', state: 'ready',
})).toMatchObject({ videoState: 'live', controlState: 'ready' })
```

Run:

```sh
cd ios_screen_mvp/web
npm test -- --run src/session/sessionState.test.ts
```

Expected: FAIL because the reducer module does not exist.

- [ ] **Step 2: Implement independent browser video and control state**

Create these types and reducer in `sessionState.ts`:

```typescript
export interface SessionState {
  videoState: 'connecting' | 'live' | 'error' | 'disconnected'
  controlState: 'unavailable' | 'connecting' | 'ready'
  metadata?: ReadyMetadata
  error?: ErrorMessage
}

export const initialSessionState: SessionState = {
  videoState: 'connecting',
  controlState: 'unavailable',
}
```

Update `IosScreenDemo.tsx` so ready/error/control messages reduce into one state. Keep rendering video when control is unavailable, display separate `Video: Live` and `Control: Ready/Unavailable` telemetry, and create `PointerGestureState` only when `controlState === 'ready'`. A transition away from ready calls `socketClosed()` to cancel/reset the local gesture.

- [ ] **Step 3: Make the initial VM URI optional and close resources in order**

In `server.dart`, define the CLI option without `mandatory: true`:

```dart
..addOption('vm-service-uri')
```

Create `MvpServer` with a URI-aware control factory. Start HTTP and capture even when the option is absent. When it is present, call `mvp.attachControl(Uri.parse(value))` and print a diagnostic on failure without closing HTTP/capture. Shutdown order is:

```dart
await server.close(force: true);
await mvp.close();
await captureLauncher.close();
```

- [ ] **Step 4: Update reproducible commands and failure semantics**

Document this exact sequence in `ios_screen_mvp/README.md`:

```sh
dart run bin/server.dart --device-id '<selector>' --web-root ../web/dist --port 8765
flutter run -d '<flutter-device-id>'
curl -X PUT http://127.0.0.1:8765/control \
  -H 'content-type: application/json' \
  -d '{"vmServiceUri":"http://127.0.0.1:<port>/<token>=/"}'
```

State that a Flutter restart requires only another `PUT /control`, browser close does not release capture, and server `Ctrl+C` releases capture. Record the first-activation app termination as the reason for this ordering.

- [ ] **Step 5: Run all automated verification**

Run:

```sh
cd ios_screen_mvp/server && dart test && dart analyze
cd ../web && npm test -- --run && npm run build
cd ../flutter_demo && flutter test && flutter analyze
cd ../../ && swiftc -parse-as-library ios_screen_mvp/native/ios_capture.swift -o /tmp/ios_screen_mvp_capture
```

Expected: all tests pass, analyzers report no issues, web production build succeeds, and Swift compilation exits zero.

- [ ] **Step 6: Run the real-device restart acceptance flow**

On the connected iPhone:

1. start server without `--vm-service-uri` and open the browser;
2. confirm live video remains after the first Flutter debug app exits;
3. relaunch Flutter and attach its new URI through `PUT /control`;
4. verify click changes `_clicks`, 700 ms hold changes `_longPresses`, and upward swipe increases scroll pixels;
5. close and reopen browser and confirm capture helper PID remains unchanged;
6. relaunch Flutter again, attach the second new URI, and confirm control returns without restarting helper;
7. stop server and confirm port 8765 and the helper process are gone.

- [ ] **Step 7: Commit the integrated lifecycle**

```sh
git add ios_screen_mvp/server/bin/server.dart ios_screen_mvp/web ios_screen_mvp/README.md
git commit -m "feat: keep ios video live while control reconnects"
```

## Self-Review

- Every browser, capture, and control resource has one explicit owner and shutdown boundary.
- Capture failure remains visible through HTTP/WebSocket diagnostics without coupling to VM Service.
- Control replacement is atomic and cannot destroy a working backend when a new URI fails.
- Updated ready metadata precedes control ready, so pointer mapping uses Flutter dimensions.
- The plan contains complete commands, expected failures, and concrete implementation signatures.
