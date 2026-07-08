# Bridge Server Decomposition Plan

## Background

`AskUiBridgeServer` has grown into a large bridge module that mixes transport, route dispatch, protocol parsing, workflow state, and response formatting. The file currently handles Bridge Session creation, Chat ingress, Agent Session long-polling, Live App Surface Device WebSocket lifecycle, Bridge Session events, Flutter Inspector actions, hot actions, CORS, JSON responses, and SSE framing.

The goal is not to reduce line count by mechanically moving code. The goal is to extract deeper modules: small, stable interfaces that hide substantial behavior and improve locality for future changes.

Related artifacts:

- Product PRD: `docs/product/bridge-server-decomposition-prd.md`
- Issue set: `issues/0.0.3-bridge-server-decomposition.md`
- GitHub PRD issue: https://github.com/drown0315/ask_ui/issues/24
- Implementation issues:
  - https://github.com/drown0315/ask_ui/issues/19
  - https://github.com/drown0315/ask_ui/issues/20
  - https://github.com/drown0315/ask_ui/issues/21
  - https://github.com/drown0315/ask_ui/issues/22
  - https://github.com/drown0315/ask_ui/issues/23

## Constraints

- Preserve all existing HTTP, WebSocket, and SSE contracts.
- Keep `AskUiBridgeServer` as the public local server entrypoint.
- Keep behavior aligned with:
  - `docs/adr/0001-bridge-owned-android-device.md`
  - `docs/adr/0002-live-app-surface-websocket-protocol.md`
  - `docs/adr/0003-agent-chat-long-poll.md`
- Prefer workflow modules over generic routing abstractions.
- Add focused tests for new module seams while keeping existing server behavior tests as compatibility coverage.
- Do not introduce a broad router until the workflow modules have been extracted and the remaining adapter duplication is visible.

## Current Friction

The server module is shallow because callers and tests cross one large interface while unrelated behavior is implemented behind private route handlers.

High-friction areas:

- Chat request parsing owns Selection Comment validation, snapshot ownership checks, limits, and normalized message construction inside a server handler.
- Device WebSocket lifecycle owns one-active-session state, control validation, stream startup, debug fixtures, sink formatting, and cleanup inside a server handler.
- Bridge Session events owns SSE snapshots, Chat and Inspector subscriptions, heartbeat, write serialization, and disconnect cleanup inside a server handler.
- Bridge Session creation owns Target Device startup validation, project root validation, device checker errors, and SessionStore calls inside a server handler.
- Repeated route mechanics make the server harder to scan, but extracting route helpers first would likely create a shallow abstraction.

## Target Shape

After decomposition, `AskUiBridgeServer` should read as a transport adapter:

- start and close the local HTTP server
- apply CORS and `OPTIONS`
- match routes
- decode JSON at the transport edge
- resolve Bridge Sessions where needed
- upgrade WebSocket or prepare SSE response where needed
- call workflow modules
- map typed workflow results to HTTP/WebSocket/SSE responses

Domain-heavy behavior should sit behind the following modules.

## Module 1: Chat Ingress

Recommended first extraction.

### Responsibility

Own browser Chat request validation and normalization before accepted messages enter Bridge Session Chat state.

### Interface Shape

The interface should accept decoded request data plus Bridge Session context and return either:

- an accepted Chat command with normalized text, context, and ordered parts
- a typed rejection reason that the HTTP adapter maps to the existing public error code

### Behavior To Move

- Plain text Chat validation.
- Ordered `parts` validation.
- Selection Comment attachment validation.
- Selected-widget metadata validation.
- Snapshot status validation.
- Snapshot file existence and Bridge Session ownership checks.
- Chat text, Selection Comment text, metadata, and batch limits.
- JSON object normalization that belongs to Chat payload interpretation.

### Why First

This extraction has the best risk/reward ratio. It is mostly parsing and normalization, has strong existing behavior coverage through Chat server tests, and can gain focused pure/module tests without touching sockets, scrcpy, VM Service, or long-lived streams.

### Tests

Add focused module tests for:

- accepted plain text
- accepted Selection Comment attachments
- invalid part shapes
- invalid selected-widget metadata
- invalid snapshot status
- over-limit text and metadata
- too many Selection Comments
- missing snapshot file
- unowned snapshot path

Keep existing Chat server tests passing.

## Module 2: Device WebSocket Session

### Responsibility

Own Live App Surface Device WebSocket lifecycle after the server has resolved the Bridge Session and upgraded or prepared the WebSocket transport.

### Interface Shape

The interface should accept:

- Bridge Session
- WebSocket transport adapter or socket context
- Device stream factory
- logger
- debug options

It should own startup, message handling, and cleanup until the session ends.

### Behavior To Move

- One-active-Device-WebSocket enforcement.
- Device stream startup.
- WebSocket stream sink message formatting.
- Ready, metadata, video chunk, error, and log forwarding.
- Device control message validation.
- Accepted control logging.
- Debug fixture selection.
- Debug metadata update.
- Startup failure mapping.
- WebSocket close and error cleanup.
- Underlying Device stream cleanup.

### Tests

Add or preserve focused tests for:

- ready metadata
- binary H.264 chunks
- one-active-session rejection
- reconnect after close
- startup failure
- socket close cleanup
- socket error cleanup
- invalid control messages
- accepted touch logging
- accepted system key logging
- debug fixture video
- debug metadata

Keep existing Device WebSocket server tests passing.

## Module 3: Bridge Session Event Stream

### Responsibility

Own the Bridge Session SSE workflow as one state machine.

### Interface Shape

The interface should accept:

- Bridge Session
- SSE/event sink adapter
- Inspector status source
- Chat event source
- heartbeat interval
- logger

It should open the stream, emit initial snapshots, subscribe to changes, serialize writes, heartbeat, and clean up on disconnect or failure.

### Behavior To Move

- Initial Select Widget mode snapshot.
- Initial Chat snapshot.
- Select Widget mode subscription.
- Chat event subscription.
- SSE event payload construction.
- Heartbeat.
- Serialized write queue.
- Write failure handling.
- Browser disconnect cleanup.
- Subscription cancellation.

### Tests

Add or preserve focused tests for:

- initial Select Widget snapshot
- initial Chat snapshot
- Select Widget mode changes
- Chat History and Agent Status changes
- heartbeat writes
- serialized writes
- snapshot failure
- write failure
- browser disconnect cleanup
- subscription cancellation

Keep existing Chat and Select Widget event server tests passing.

## Module 4: Bridge Session Creator

### Responsibility

Own the Bridge Session startup contract and Target Device binding rules.

### Interface Shape

The interface should accept normalized session creation request data and return either:

- a creation success payload
- a typed rejection reason

The HTTP adapter maps the typed result to existing response status and JSON body.

### Behavior To Move

- Required startup parameter validation.
- Blank startup parameter validation.
- Project root existence validation.
- Target Device checker invocation.
- Target Device check failure classification.
- Target Device not-found classification.
- Target Device unavailable classification.
- SessionStore creation.
- Repeated Flutter app session / Target Device mismatch handling.
- Successful response payload data.

### Tests

Add focused module tests for:

- missing parameters
- blank parameters
- invalid project root
- Target Device checker failure
- Target Device not found
- Target Device unavailable
- existing-session device mismatch
- successful creation
- target device display name
- read-only client behavior

Keep existing session server tests passing.

## Module 5: Thin Bridge HTTP Adapter

This should be the final step, after the four workflow modules are extracted.

### Responsibility

Keep transport concerns in `AskUiBridgeServer` and delegate workflow behavior to the deeper modules.

### Behavior To Keep

- Public server entrypoint.
- Server start and close.
- Route matching.
- CORS and `OPTIONS`.
- JSON response writing.
- WebSocket upgrade transport.
- SSE response setup.
- Mapping typed workflow outcomes to HTTP/WebSocket/SSE responses.

### Behavior To Consolidate Carefully

- JSON object decoding where it reduces handler noise.
- Bridge Session lookup where it preserves clear `session_not_found` behavior.
- Shared response helpers that do not hide endpoint-specific contracts.

### What To Avoid

- A broad generic router as a standalone refactor.
- Pass-through modules with interfaces nearly as complex as their implementation.
- Moving code into files without reducing caller knowledge.
- Tests that assert private helper names instead of observable route behavior.

### Tests

Use existing server behavior tests as the main compatibility suite. Add only focused tests for any new adapter helper that has meaningful external behavior.

Final verification should include:

```text
dart test
```

from `apps/bridge`.

## Recommended Execution Order

1. Extract Chat ingress parsing.
2. Extract Device WebSocket session lifecycle.
3. Extract Bridge Session event stream.
4. Extract Bridge Session creation.
5. Thin the bridge HTTP adapter.

The first four slices can proceed independently. The final adapter thinning should wait until the first four modules exist.

## Definition Of Done

- Existing public bridge contracts remain compatible.
- New modules expose narrow, stable interfaces.
- New modules have focused tests at their seams.
- Existing bridge server tests still pass.
- `AskUiBridgeServer` no longer owns Chat parsing, Device WebSocket lifecycle, Bridge Session event stream orchestration, or Bridge Session creation rules.
- The remaining server code reads as transport adaptation rather than domain workflow implementation.
