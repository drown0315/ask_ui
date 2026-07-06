# ADR 0003: Agent Chat Long Poll

Ask UI will route Chat messages through the existing Bridge Session instead of opening a separate Chat WebSocket. The Bridge Session already owns the local Flutter app target, Target Device binding, session events stream, and browser read-only boundary, so Chat state belongs beside that session state.

Chat History and Agent Status are in-memory Bridge Session state. Restarting the bridge backend or destroying the Bridge Session clears Chat History and resets Agent Status. This avoids implying durable project history before Ask UI has an explicit persistence model.

The browser loads an initial Chat snapshot with `GET /api/sessions/:sessionId/chat`, then receives `chat_snapshot`, `agent_status_changed`, and `chat_history_changed` events through the existing `/api/sessions/:sessionId/events` Server-Sent Events stream. The same stream continues to carry Select Widget mode events.

The launching Agent Session waits for work with `GET /api/sessions/:sessionId/agent/poll`. Polling is indefinite by default. A `timeoutMs` query parameter exists only for tests and debugging clients. One Bridge Session allows only one active Agent Session poller; a second active poll returns `agent_poll_already_active`.

Agent Status is `waiting_for_agent` when no poller is ready, `agent_ready` while the poller waits, and `agent_working` after a browser user message has been handed to the poller. If the poller disconnects before receiving a message, Agent Status returns to `waiting_for_agent`.

The browser sends plain text through `POST /api/sessions/:sessionId/chat/messages`. The bridge validates non-empty text and a 4000-character limit, then delivers the message only when an active poller accepts it. There is no offline queue; `agent_not_ready` leaves the browser composer draft intact for manual retry.

Agent-authored output uses `POST /api/sessions/:sessionId/agent/reply` for normal agent replies and `POST /api/sessions/:sessionId/agent/error` for command-level system messages. Both store plain text messages in Chat History and return Agent Status to `waiting_for_agent`.

Selection Comments are not part of the Chat message payload in the current slice. Attachment payloads, snapshots, sent attachment summaries, reply correlation, and combined reply-then-poll command ergonomics remain later Selection Chat work.
