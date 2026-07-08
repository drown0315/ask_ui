# Agent Session Command PRD

## Problem Statement

Ask UI Selection Chat can deliver user Chat messages from the Chat Panel to a waiting Agent Session, but the agent-facing command contract is still underspecified. The existing Bridge Session HTTP endpoints prove the poll, reply, and error paths, but Codex, Claude Code, or a similar launching agent needs a stable CLI contract that is natural to run in the Agent Session loop.

Without a precise Agent Session Command contract, agents can accidentally lose the reply-to relationship, retry a reply that was already written, expose transport details as workflow behavior, or leave Chat stuck in `Waiting for agent` when the standard loop should continue polling.

## Solution

Define the Agent Session Command as the formal agent-facing CLI contract for the Selection Chat loop. The command lets the Agent Session poll for the next user Chat message, write an agent reply or command-level system error, and normally continue long-polling for the next Chat message in one flow.

HTTP agent endpoints remain the underlying transport. The CLI owns the machine-readable command contract: argument validation, JSON-only output, continuation behavior, partial-success reporting, and scenario-specific next-step guidance for the Agent Session.

## User Stories

1. As a Flutter developer, I want the launching Agent Session to enter Chat polling automatically, so that Chat becomes ready without a second manual command.
2. As a Flutter developer, I want Agent Status to become `Agent ready` while the Agent Session Command is waiting, so that I know Send can deliver my next message.
3. As a Flutter developer, I want the Agent Session to reply and continue polling by default, so that Chat feels continuous.
4. As a Flutter developer, I want command-level agent errors to appear as system messages, so that workflow failures are visible without pretending to be normal agent replies.
5. As a Flutter developer, I want normal explanations of failed work to remain agent replies, so that the conversation stays readable.
6. As a Flutter developer, I want agent replies correlated with the user Chat message they answer, so that Chat History and logs can connect work to requests.
7. As a Flutter developer, I want command-level system errors correlated with a user Chat message when applicable, so that failures can be traced to the request being processed.
8. As a Flutter developer, I want a successful agent reply to remain in Chat History even if continued polling fails, so that completed feedback is not lost.
9. As a Flutter developer, I want Ask UI to avoid duplicate agent replies after a partial command failure, so that Chat History does not repeat the same response.
10. As a Flutter developer, I want no Chat UI command terminology exposed in the product, so that the Chat Panel remains focused on Agent Status and messages.
11. As an Agent Session, I want one command to poll for the next Chat message, so that I can wait for user work without calling browser APIs directly.
12. As an Agent Session, I want one command to write an agent reply and continue polling, so that the standard loop is poll, process, reply, poll again.
13. As an Agent Session, I want one command to write a system error and continue polling, so that workflow-level failures can be reported and the conversation can continue.
14. As an Agent Session, I want an explicit one-shot mode, so that I can poll or write without continuing the loop when the launcher is intentionally stopping.
15. As an Agent Session, I want reply text passed by explicit flags, so that command invocation stays visible and auditable.
16. As an Agent Session, I want success output to be a single JSON object on stdout, so that I can parse it without filtering human text.
17. As an Agent Session, I want failure output to be a single JSON object on stderr with a non-zero exit code, so that command failures are unambiguous.
18. As an Agent Session, I want the command output to include the current Chat message payload, so that I can process the user's selected-widget context.
19. As an Agent Session, I want the command output to include a short next-step instruction, so that I know whether to process, reply, retry polling, or avoid rewriting a message.
20. As an Agent Session, I want write-and-continue output to include the message that was written, so that I can distinguish written feedback from the next user request.
21. As an Agent Session, I want a poll continuation failure to include the written message, so that I do not retry the reply or error and create duplicates.
22. As an Agent Session, I want the reply-to message ID required for agent replies, so that replies cannot be stored without correlation.
23. As an Agent Session, I want reply-to validation to reject missing, unknown, or non-user messages, so that Chat History relationships remain coherent.
24. As an Agent Session, I want system errors to optionally carry a reply-to message ID, so that session-level failures and message-level workflow failures can both be represented.
25. As an Agent Session, I want multiple agent or system messages to be allowed for one user message, so that retries, follow-up explanations, and workflow errors are not blocked.
26. As an Agent Session, I want command configuration to come from explicit flags or environment variables, so that launchers can pass connection context without repo-local state files.
27. As an Agent Session, I want no command-level timeout option in the formal CLI contract, so that the standard Chat readiness loop remains indefinite.
28. As an Agent Session, I want a second active poller to fail clearly, so that competing Agent Sessions do not fight for one Bridge Session.
29. As a bridge maintainer, I want the CLI to reuse the existing agent HTTP endpoints, so that the server API surface stays small.
30. As a bridge maintainer, I want reply-to correlation represented as a first-class Chat message field, so that tests, logs, and UI behavior can depend on a clear relationship.
31. As a bridge maintainer, I want command text validation to match Chat limits, so that agent-authored messages stay within existing Chat History constraints.
32. As a bridge maintainer, I want command output scenarios tested at module boundaries, so that the Agent Session Command can evolve without brittle private-helper tests.

## Implementation Decisions

- Use `Agent Session Command` as the canonical term. Avoid `Skill Command`; a skill may launch the loop, but the command belongs to the Agent Session contract.
- The formal agent-facing contract is a CLI command. HTTP endpoints are the underlying transport used by that command.
- The current implementation should add an `agent poll` command to the existing bridge command entrypoint while keeping the current server-start path compatible. A future packaging layer may expose the same shape as `ask-ui agent poll`.
- The command receives Bridge Session connection context from `--base-url` or `ASK_UI_BRIDGE_URL`, and `--session-id` or `ASK_UI_SESSION_ID`. Explicit flags take precedence over environment variables.
- The command must fail with JSON errors when the bridge URL or session ID is missing. It must not scan ports, read browser URLs, or use repo-local state files.
- The command supports pure polling:
  - `agent poll`
  - `agent poll --once`
- The command supports agent replies:
  - `agent poll --reply-to <message-id> --agent-reply <text>`
  - `agent poll --reply-to <message-id> --agent-reply <text> --once`
- The command supports command-level system errors:
  - `agent poll --agent-error <text>`
  - `agent poll --reply-to <message-id> --agent-error <text>`
  - `agent poll --agent-error <text> --once`
- `--agent-reply` and `--agent-error` are mutually exclusive.
- Reply and error text are supplied only by explicit flags. The command does not support stdin variants for message text.
- The CLI does not expose a timeout option. The underlying HTTP transport may keep its test/debug timeout behavior, but timeout is not part of the Agent Session Command contract.
- Without `--once`, the command uses the continuous long-poll model. When a reply or error is supplied, the command writes it first, starts the next poll in the same process, waits until the next user Chat message arrives, outputs JSON, and exits.
- With `--once`, the command completes only the current action. Pure poll waits for one message and exits. Reply or error writes the message and exits without continued polling.
- Success output is a single JSON object on stdout. Failure output is a single JSON object on stderr with a non-zero exit code. The command does not support a `--json` flag because JSON is the only output mode.
- Pure poll success returns `status`, `message`, and `nextStep`.
- Reply or error plus continued poll success returns `status`, `writtenMessage`, `message`, and `nextStep`.
- Reply or error plus `--once` success returns `status`, `writtenMessage`, `message: null`, and `nextStep`.
- If writing a reply or error fails, the command must not continue polling.
- If writing succeeds but continued polling fails, the written message remains in Chat History. The command fails with `poll_continuation_failed`, includes `writtenMessage`, and instructs the Agent Session not to retry the written message.
- `nextStep` is a short scenario-specific instruction. For poll success, it should identify the message ID to process and tell the Agent Session to reply with `--reply-to` and either `--agent-reply` or `--agent-error`.
- Add `replyToMessageId` as a top-level optional Chat message field. It is not stored in message context.
- User messages do not carry `replyToMessageId`.
- Agent messages must carry `replyToMessageId`.
- System messages may carry `replyToMessageId` when the error applies to a specific user message.
- `--agent-reply` requires `--reply-to`.
- `--agent-error` may omit `--reply-to`.
- When `--reply-to` is provided, it must identify an existing user message in the current Bridge Session Chat History. Missing, unknown, or non-user targets fail before writing.
- Multiple agent or system messages may point to the same user message. The bridge should not enforce one reply per user message.
- Agent reply and system error text validation uses `trim()` for non-empty checks but stores the original text. The existing 4000-character Chat message text limit applies.
- The command reuses the existing HTTP agent poll, reply, and error endpoints instead of adding a write-and-poll endpoint.
- The HTTP reply endpoint should accept required `replyToMessageId`; the HTTP error endpoint should accept optional `replyToMessageId`. Both should perform the same validation as the command contract when a value is present.
- The command should treat `agent_poll_already_active` as a failure, not a recoverable status. It must not write a system message or attempt to replace the active poller.
- The minimum CLI error code set is:
  - `missing_bridge_url`
  - `missing_session_id`
  - `invalid_arguments`
  - `invalid_reply_to_message`
  - `empty_chat_message`
  - `chat_message_too_long`
  - `session_not_found`
  - `agent_poll_already_active`
  - `bridge_request_failed`
  - `poll_continuation_failed`
- Build a deep command-contract module that parses arguments, resolves configuration, validates mutually exclusive options, and returns a typed command request.
- Build a deep transport client module that wraps the underlying bridge HTTP calls and normalizes transport errors into command errors.
- Build a deep output module that serializes success and failure objects consistently without leaking logs or human text to stdout.
- Extend the Chat session domain module to support reply-to correlation and validation against existing Chat History.

## Testing Decisions

- Tests should verify externally observable command and bridge behavior rather than private helper names.
- CLI argument tests should cover flag and environment variable precedence, missing configuration, invalid argument combinations, `--once`, reply/error mutual exclusion, and absence of stdin or timeout support.
- CLI output tests should assert exact success and error JSON shapes for pure poll, write-and-continue, write-once, validation failure, transport failure, active-poller conflict, and poll continuation failure.
- Transport client tests should use fake bridge responses rather than requiring a live Flutter app, real browser, or real device.
- Bridge Chat session tests should cover top-level `replyToMessageId` serialization, required agent reply correlation, optional system error correlation, invalid reply-to rejection, and multiple follow-up messages for one user message.
- Bridge server tests should cover HTTP reply and error endpoint validation, response shapes, and preservation of existing poll behavior.
- Agent Status tests should verify that continued polling moves the session back to ready while waiting and returns to waiting when the poll cannot continue.
- Existing Bridge Session Chat tests are prior art for poller lifecycle, send handoff, reply/error recording, and Agent Status transitions.
- Existing bridge server tests are prior art for HTTP status codes, JSON error bodies, and fake dependency injection.
- Existing web Chat tests do not need broad changes unless UI behavior depends on `replyToMessageId`; the command terminology must remain absent from product UI.
- Tests do not need to run against a real coding-agent CLI, real Flutter app, real Android Target Device, or real screenshot capture path.

## Out of Scope

- A separate installed `ask-ui` packaging project.
- Command stdin support for reply or error bodies.
- CLI timeout flags.
- Human-readable command output.
- A `--json` flag.
- Repo-local session state files.
- Port scanning or automatic Bridge Session discovery.
- A new write-and-poll HTTP endpoint.
- Multiple active Agent Session pollers for one Bridge Session.
- Enforcing one agent reply per user message.
- Chat Panel controls for starting, stopping, or ending the Agent Session loop.
- Exposing command, poller, or transport terminology in product UI.
- Persisting Chat History or command state across bridge backend restart.
- Remote/shared-agent security design.

## Further Notes

- This PRD follows the accepted Agent Chat Long-Poll ADR and refines the command contract implied by the Selection Chat PRD.
- The Agent Session Command should preserve the current responsibility split: the Bridge Session owns Chat History, Agent Status, and poller handoff; the Agent Session owns code editing authority.
- The `ready-for-agent` triage label should be applied when this PRD is published to the issue tracker.
