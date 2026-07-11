# Ask UI Launch PRD

## Problem Statement

Ask UI is intended to be started from the same Codex, Claude Code, or similar coding-agent session that will later receive UI-targeted feedback. Today that startup path is still a set of manual local steps: choose a Flutter device, run the target Flutter app, start the Dart Bridge, start or build the Web workbench, open the browser with the right parameters, then separately enter the Agent Session Command polling loop.

That manual chain is fragile. It exposes implementation details such as the React/Vite development server to installed users, makes the Agent Session depend on browser-created session state, and leaves too much room for mismatched device, flavor, VM Service, Bridge Session, and poll command parameters.

Ask UI needs a single launch contract that coding agents can run reliably. The installed-user path should work from a Flutter project that integrates `ask_ui_runtime`, use a globally activated `ask_ui_bridge` CLI, serve the packaged Web workbench from the local bridge, open the browser, and return the exact Agent Session Command needed to keep receiving Chat messages from Ask UI.

## Solution

Add a first-class `launch` command to the Ask UI bridge CLI.

The launch command discovers or accepts a Target Device, supports Flutter flavor-related app startup options, runs the target Flutter app, captures the VM Service URI, starts or reuses the local Bridge Server, creates a Bridge Session, serves the packaged Web workbench, opens a browser URL that attaches to the created Bridge Session, and returns machine-readable JSON containing the workbench URL and Agent Session Command.

Installed users should run Ask UI through the pub package:

- Add the runtime package to the Flutter app.
- Register the runtime before `runApp`.
- Globally activate the bridge package.
- Run the `ask_ui_bridge` executable from the Flutter project.

The React/TypeScript Web app remains the implementation of the workbench, but users do not install or run the Web source. Release preparation builds the Web app into static files and includes those files inside the bridge package artifact. The Bridge Server serves those static files from the same local origin as the API.

The coding-agent skills stay thin. They call `launch`, handle `needs_device_selection` JSON by asking the user to choose a device, run the returned Agent Session Command when launch is ready, treat polled Ask UI messages as current task input, write replies through the Agent Session Command, and continue polling until the user stops.

## User Stories

1. As a Flutter developer, I want to start Ask UI with one command from my coding-agent session, so that I do not manually coordinate several local processes.
2. As a Flutter developer, I want the launch command to use the same Agent Session that will later edit code, so that UI feedback returns to the right coding agent.
3. As a Flutter developer, I want the installed-user command to run from my Flutter project, so that Ask UI starts against the app I am inspecting.
4. As a Flutter developer, I want the bridge as a globally activated development CLI, so that my app only needs the runtime integration.
5. As a Flutter developer, I want the runtime package to remain separate from the bridge dev tool, so that production app dependencies stay minimal.
6. As a Flutter developer, I want launch to discover Flutter devices when I do not specify one, so that I can choose from the devices currently visible to Flutter.
7. As a Flutter developer, I want launch to proceed automatically when exactly one usable device exists, so that common single-device setups are fast.
8. As a Flutter developer, I want launch to ask me when multiple devices are available, so that it does not guess the wrong Target Device.
9. As a Flutter developer, I want launch to accept a device id, so that I can start a known emulator or physical device directly.
10. As a Flutter developer, I want launch to accept an unambiguous device name, so that I can use human-friendly device references.
11. As a Flutter developer, I want ambiguous device names to return a selection prompt, so that launch does not silently bind to the wrong device.
12. As a Flutter developer, I want launch errors for missing devices to be clear, so that I know whether to connect a device or start an emulator.
13. As a Flutter developer, I want launch to support Flutter flavors, so that I can inspect the same app variant I normally develop.
14. As a Flutter developer, I want launch to support Flutter target files, so that flavor-specific entrypoints work.
15. As a Flutter developer, I want launch to support Dart defines, so that local app configuration works without editing code.
16. As a Flutter developer, I want flavor and target values to appear in launch output, so that I can verify which app variant is running.
17. As a Flutter developer, I want launch to run the Flutter app for me, so that Ask UI starts from a real VM Service session.
18. As a Flutter developer, I want launch to capture the VM Service URI automatically, so that I do not copy it from Flutter logs.
19. As a Flutter developer, I want Flutter startup failures returned as structured launch errors, so that the agent can explain or retry the correct step.
20. As a Flutter developer, I want launch to create the Bridge Session before opening the browser, so that the Agent Session Command already has a session id.
21. As a Flutter developer, I want the browser to attach to the existing Bridge Session, so that it does not create a duplicate session.
22. As a Flutter developer, I want the launch command to return the exact Agent Session Command, so that Codex or Claude Code can enter the polling loop immediately.
23. As a Flutter developer, I want the returned Agent Session Command to include the bridge URL and session id, so that it does not rely on port scanning or local state guessing.
24. As a Flutter developer, I want Chat to become Agent ready after launch, so that I can send UI-targeted work from the workbench.
25. As a Flutter developer, I want the Web workbench to open automatically after launch, so that I do not manually assemble a URL.
26. As a Flutter developer, I want a no-open option, so that automated or remote workflows can print the URL without opening a browser.
27. As a Flutter developer, I want the printed workbench URL to remain usable when browser opening fails, so that I can open it manually.
28. As a Flutter developer, I want the same local origin to serve the Web workbench and Bridge API, so that installed startup has fewer moving parts.
29. As a Flutter developer, I do not want to install Node dependencies just to use Ask UI, so that React and Vite remain implementation details.
30. As a Flutter developer, I want the packaged Web workbench to be included in the bridge package, so that `launch` works after pub installation.
31. As an Ask UI maintainer, I want release preparation to build Web assets into the bridge package, so that pub publishing contains all runtime workbench files.
32. As an Ask UI maintainer, I want bridge package publish rules to include packaged Web assets, so that the published artifact is complete.
33. As an Ask UI maintainer, I want development-only generated files excluded from normal commits, so that package hygiene stays clean.
34. As an Ask UI contributor, I want an explicit Web development mode, so that I can use Vite hot reload while working on the workbench.
35. As an Ask UI contributor, I want packaged Web to be the default launch path, so that development conveniences do not leak into installed-user behavior.
36. As an Ask UI contributor, I want launch to capture the actual Web dev server URL, so that alternate Vite ports work.
37. As a coding agent, I want launch output to be JSON, so that I can parse status, errors, URLs, and next steps reliably.
38. As a coding agent, I want device-selection output to include the command to rerun with the selected device, so that I can preserve flavor and target options.
39. As a coding agent, I want launch success output to include a clear next step, so that I run the Agent Session Command rather than replying too early.
40. As a coding agent, I want launch failures to use stable error codes, so that I can decide whether to ask the user, retry, or stop.
41. As a coding agent, I want the launch skill to stay thin, so that fragile process orchestration lives in tested CLI code.
42. As a coding agent, I want the skill to prefer the installed bridge command, so that the documented CLI contract is honored.
43. As a coding agent, I want the skill to support the monorepo development fallback, so that Ask UI can dogfood its own source checkout.
44. As a coding agent, I want the skill to ask the user only when device selection is needed, so that startup remains mostly automatic.
45. As a coding agent, I want polled Ask UI messages to become current task input, so that selected widgets, comments, and snapshots drive normal code edits.
46. As a coding agent, I want to write replies through the Agent Session Command, so that Chat History stays synchronized with the browser.
47. As a coding agent, I want to continue polling after each reply, so that the browser feedback loop remains live.
48. As a coding agent, I want command-level workflow errors to be reported through the agent error path, so that the user sees failures in Chat without confusing them with normal replies.
49. As a Flutter developer, I want launch to cleanly stop its child processes when interrupted, so that Flutter, bridge, and Web dev processes do not linger unexpectedly.
50. As a Flutter developer, I want launch logs and JSON output separated, so that agents can parse output without filtering noisy process logs.
51. As a Flutter developer, I want launch to preserve existing Bridge Session API behavior, so that current Web features continue working.
52. As a Flutter developer, I want existing URL bootstrap by VM Service, project root, and device id to keep working, so that current development and tests are not broken.
53. As a Flutter developer, I want the new session attach URL to be additive, so that launch can improve startup without removing the older bootstrap path.
54. As a Flutter developer, I want the bridge CLI to stay separate from my app dependencies, so that production dependency graphs stay focused on runtime code.
55. As a Flutter developer, I want the global bridge command to be explicit, so that installation and upgrade behavior is easy to explain.
56. As an Ask UI maintainer, I want launch modules to be deep and testable, so that device discovery, Flutter startup, static serving, and browser opening can evolve independently.
57. As an Ask UI maintainer, I want packaging validation, so that releases do not accidentally omit the Web workbench.
58. As an Ask UI maintainer, I want launch to match the existing Agent Chat Long-Poll model, so that browser feedback keeps flowing through the original Agent Session.

## Implementation Decisions

- Add `launch` as a bridge CLI command alongside the existing server start path and Agent Session Command.
- Keep `agent poll` as the canonical command for receiving Ask UI Chat messages and writing replies or command-level errors.
- Make the installed-user default command the globally activated `ask_ui_bridge` executable.
- Keep the source entrypoint as the Ask UI maintainer development fallback.
- Keep the coding-agent skill thin; it calls the launcher and follows returned next-step instructions.
- Use machine-readable JSON as the launch command output contract.
- Use stable launch statuses such as ready, needs-device-selection, and error.
- Include stable launch error codes for missing devices, ambiguous device selection, Flutter startup failure, bridge startup failure, session creation failure, packaged Web missing, browser open failure where appropriate, and invalid arguments.
- Discover devices through Flutter's machine-readable device listing.
- Match explicit device ids exactly after trimming.
- Allow unambiguous device-name matching, but do not guess when names match multiple devices.
- Preserve flavor, target, Dart defines, project root, and open/no-open intent in device-selection continuation output.
- Treat Flutter flavor as app launch metadata, not Bridge Session identity.
- Pass flavor, target, and Dart defines to Flutter run without hardcoding project-specific flavor maps.
- Allow future optional configuration for flavor-to-target defaults, but keep first-version launch explicit.
- Capture the VM Service URI from Flutter run output.
- Keep Flutter app process management inside a dedicated launcher module with a small interface.
- Start or reuse the local Bridge Server before creating the Bridge Session.
- Create the Bridge Session from launch after VM Service URI, project root, and device id are known.
- Return the session id from launch success output.
- Return an executable Agent Session Command string from launch success output.
- Return the bridge URL from launch success output and avoid port scanning in the Agent Session Command.
- Add Web attach bootstrap using bridge URL and session id.
- Preserve the existing Web create bootstrap using VM Service URI, project root, and device id.
- Make attach bootstrap avoid creating a second Bridge Session.
- Make Web clients use the attached bridge origin for Chat, Widget Tree, events, Live App Surface, snapshots, inspector actions, and hot actions.
- Serve packaged Web static files from the Bridge Server in installed-user mode.
- Keep `/api` routing distinct from Web static fallback.
- Return Web `index.html` for non-API workbench routes so refresh and deep links work.
- Keep unknown API routes as JSON API failures rather than Web fallback.
- Build the React/TypeScript Web app before publishing the bridge package.
- Copy the Web build output into the bridge package artifact before publishing.
- Ensure publish ignore rules include required packaged Web files and exclude local-only artifacts.
- Add a release preparation command or script that validates the packaged Web layout.
- Default launch to packaged Web.
- Add explicit Web development mode for contributors who want Vite hot reload.
- Web development mode should capture the actual dev server URL rather than assuming a fixed port.
- Browser opening should be best-effort; launch output must always include the workbench URL when the session is otherwise ready.
- Keep process logs off stdout when stdout is used for JSON.
- Use stderr or log files for child process diagnostics where needed.
- Keep launch foreground in the first version so Ctrl-C can clean up child processes.
- Consider detached launch, status, and stop commands as later extensions.
- Use deep modules for launch parsing, device discovery, Flutter app launch, Bridge Server launch, packaged Web serving, Web session bootstrap, browser opening, release packaging, and skill workflow.
- Avoid duplicating complex Flutter, bridge, Web, or browser orchestration inside the skill body.

## Testing Decisions

- Tests should verify externally observable contracts: command arguments, JSON output, selected device behavior, spawned Flutter command shape, VM Service parsing, Bridge Session creation calls, static HTTP responses, Web bootstrap states, generated URLs, and skill workflow text.
- Avoid tests that depend on private helper names or incidental implementation state.
- Launch command tests should cover existing command compatibility, argument parsing, invalid arguments, flavor and target preservation, repeatable Dart defines, no-open behavior, and Web dev flag behavior.
- Device discovery tests should use fake Flutter machine output covering no devices, one usable device, multiple devices, explicit id match, unambiguous name match, ambiguous name match, unsupported devices, malformed output, and Flutter command failure.
- Flutter app launcher tests should cover command construction, flavor and target pass-through, Dart define pass-through, VM Service URI parsing, startup failure before VM Service, and process cleanup on interruption.
- Bridge Server launcher tests should cover start, reuse, port conflict, bridge URL output, and session creation failure propagation.
- Packaged Web serving tests should cover serving index, serving assets, API route preservation, unknown API JSON errors, Web fallback behavior, and missing packaged Web behavior.
- Web session bootstrap tests should cover attach mode, existing create mode, incomplete attach parameters, incomplete create parameters, bridge origin resolution, and no duplicate session creation in attach mode.
- Browser launcher tests should cover generated workbench URL parameters, no-open behavior, successful open, failed open with URL retained, and metadata such as device id and flavor in the URL.
- Release packaging validation should check that Web build output exists in the bridge package artifact layout and that required files are not ignored by publish rules.
- Skill workflow validation should cover launch success, device-selection rerun, launch error handling, running the returned Agent Session Command, replying with reply-to correlation, command-level error reporting, and continuing to poll.
- Existing bridge server tests are prior art for HTTP routing and JSON response behavior.
- Existing Web session bootstrap tests are prior art for focused URL parsing and session state tests.
- Existing Agent Session Command tests are prior art for machine-readable CLI output and poll/reply loop contracts.
- First-version tests do not need to run against a real physical device, real browser, real pub publish, or real coding-agent runtime.

## Out of Scope

- Remote or hosted Ask UI service startup.
- Multi-user shared browser sessions.
- Multiple active Agent Session pollers for one Bridge Session.
- Automatic installation of Flutter, Dart, Node, or platform device tooling.
- Project-specific flavor-to-target configuration in the first version.
- Project-local `ask_ui_bridge` dev dependency as the default documented skill path.
- Detached daemon lifecycle, launch status, and launch stop commands.
- Automatic recovery from Flutter process crashes after a successful launch.
- Port scanning by the Agent Session Command.
- Browser-created session id discovery by the Agent Session.
- Replacing the existing Agent Session Command protocol.
- Requiring installed users to run the React/Vite development server.
- Publishing the Web source as a separate user-installed package.
- Persisting launch sessions across bridge backend restart.

## Further Notes

- This PRD follows the same architectural shape proven by Lavish Editor: a thin skill delegates process orchestration and long-poll mechanics to a tested CLI/server contract.
- The React/TypeScript Web app remains source code for maintainers, while installed users receive compiled static assets inside the bridge package.
- The Bridge Session remains the owner of Chat History, Agent Status, device binding, and Agent Session poller handoff.
- The Agent Session remains the owner of code editing authority and communicates through the poll/reply loop.
- Published GitHub issue: https://github.com/drown0315/ask_ui/issues/28
