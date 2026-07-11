---
name: ask-ui-dev
description: Start Ask UI from the source checkout while developing the Ask UI repository, with optional Web dev server support.
---

# Ask UI Dev

Use this skill when working inside the Ask UI repository itself to dogfood the
launcher, bridge, packaged workbench, or React/Vite workbench.

Normal Flutter app users should install the `ask-ui` skill instead.

## Start Ask UI From Source

From `apps/bridge`, run the source entrypoint:

```sh
dart run bin/ask_ui_bridge.dart launch
```

Pass Flutter launch options through the launcher when the test project needs a
specific target:

```sh
dart run bin/ask_ui_bridge.dart launch \
  --device <device-id-or-name> \
  --flavor <flavor> \
  --target <path> \
  --dart-define <key=value> \
  --project-root <flutter-project-root>
```

Use packaged Web by default when validating the release-style path.

Add `--web-dev` only when developing the React/Vite workbench itself and Vite
hot reload is useful:

```sh
dart run bin/ask_ui_bridge.dart launch --web-dev
```

## Handle Launch Output

Read the launch command JSON from stdout. Keep process logs and diagnostics out
of JSON parsing decisions unless the command exits with an error.

If `status` is `needs_device_selection`, ask the user to choose from the
returned devices. Use the matching `suggestedCommand` for the selected device so
the launcher preserves flavor, target, Dart defines, project root, open/no-open,
Web development intent, and other launch intent. Do not guess when the launcher
asks for device selection.

If `status` is `ready`, run the returned `agentCommand` exactly. This command
enters the Agent Session Command loop for the Bridge Session that the workbench
is using.

If `status` is `error`, explain the stable launch error to the user. Retry only
when the user has fixed the underlying problem or explicitly asks you to retry.

## Process Ask UI Messages

Treat each message returned by `agent poll` as current-session task input. The
message may include selected widgets, comments, snapshots, or other workbench
context. Handle it like any other user request in the active coding-agent
session: inspect the project, edit files when needed, run appropriate
verification, and prepare a concise response.

Reply through the Agent Session Command so Chat History stays synchronized with
the Ask UI workbench:

```sh
agent poll --reply-to <message-id> --agent-reply <text>
```

Use the full returned command shape when it includes bridge connection flags.
The launcher normally returns the installed executable form:

```sh
ask_ui_bridge agent poll \
  --base-url <bridge-url> \
  --session-id <session-id> \
  --reply-to <message-id> \
  --agent-reply <text>
```

When debugging source-only Agent Session Command changes, run the same `agent
poll` subcommand through the source entrypoint from `apps/bridge` and preserve
the returned flags:

```sh
dart run bin/ask_ui_bridge.dart agent poll \
  --base-url <bridge-url> \
  --session-id <session-id> \
  --reply-to <message-id> \
  --agent-reply <text>
```

For command-level workflow errors, report the problem with `--agent-error`
instead of presenting it as a normal agent reply:

```sh
agent poll --reply-to <message-id> --agent-error <text>
```

Use `--agent-error` for failures such as missing local tooling, failed command
execution, invalid launch state, or a verification command that cannot be run.
Use `--agent-reply` for normal task answers, summaries, and completed work.

After each reply or error, continue polling unless the user asks you to stop,
the session ends, or the Agent Session Command returns a workflow error that
prevents continuation.

## Boundaries

Do not duplicate fragile Flutter, bridge, Web, or browser orchestration details
inside this skill. The launcher owns device discovery, Flutter startup, VM
Service parsing, Bridge Server startup, Bridge Session creation, packaged Web
serving, Web development serving, browser opening, and generated Agent Session
Command arguments.

When launch behavior needs to change, update and test the CLI contract rather
than scripting those internals here.
