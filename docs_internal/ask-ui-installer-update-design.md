# Ask UI Installer And Update Design

## Context

Ask UI currently separates its installable parts:

- `ask_ui_bridge` is a Dart global CLI installed through pub.
- `ask_ui_runtime` is a Flutter project dependency.
- `skills/ask-ui` is the coding-agent workflow used by Codex, Claude Code, or
  similar agents.

The `skills` CLI can install agent skills, but it should not be the product
installer for Ask UI. Skill installation alone cannot guarantee that the bridge
CLI, Flutter runtime dependency, and local project setup are present or
compatible.

## Command Boundaries

`npx ask-ui install` is the recommended first-time product setup command.

It owns bootstrapping Ask UI for a Flutter project that does not already have
Ask UI local metadata:

- verify that `dart` and `flutter` are available;
- install the bridge with a manifest-pinned
  `dart pub global activate ask_ui_bridge <version>`;
- install the Ask UI skill through the public Skills CLI;
- run Ask UI diagnostics;
- print the next launch command.

The manual install path remains a floating fallback:

```sh
dart pub global activate ask_ui_bridge
npx skills add https://github.com/drown0315/ask_ui/tree/main/skills/ask-ui
```

The Skills CLI owns skill placement and agent/platform behavior. Ask UI should
not pass a product-specific agent selector to `npx skills add`. The manual
fallback is not the version-locked product install contract; users who need a
compatible Ask UI Version Set should use `npx ask-ui install` or
`npx ask-ui@latest update`.

## Proposed User Flows

Full setup from a Flutter project:

```sh
npx ask-ui install
```

Explicit project:

```sh
npx ask-ui install --project /path/to/flutter_app
```

Preview planned install actions:

```sh
npx ask-ui install --dry-run
```

Other install ways:

```sh
dart pub global activate ask_ui_bridge
npx skills add https://github.com/drown0315/ask_ui/tree/main/skills/ask-ui
```

Update all Ask UI parts:

```sh
npx ask-ui@latest update
```

Update only the coding-agent workflow:

```sh
npx skills update
```

## Installer Responsibilities

The installer should be a thin npm CLI that delegates core behavior to the Dart
bridge where possible. Its job is orchestration, not duplicating bridge logic.

`install` should:

1. Resolve the target Flutter project. Default to the current directory.
2. Check required tools: `dart` and `flutter`.
3. Print the actions it will perform when `--dry-run` is provided.
4. If valid local Ask UI metadata already exists, report that Ask UI is already
   installed and avoid running diagnostics, changing the bridge, skill, or
   metadata. If the metadata file exists but is malformed or incomplete, fail
   with instructions to run `npx ask-ui@latest update` to repair the existing
   setup or remove `.ask-ui/config.json` before reinstalling.
5. Run `dart pub global activate ask_ui_bridge <manifest bridge version>`.
6. Install the Ask UI skill with the manifest-pinned Git tag URL, such as
   `npx skills add https://github.com/drown0315/ask_ui/tree/v0.0.5/skills/ask-ui`.
7. Run `ask_ui_bridge doctor --project <path>` once that command exists.
8. Print `ask_ui_bridge launch --project-root <path>` as the next step.

The installer should not support `--yes`, `--agent`, or `--skill-only`.
`install` is the real first-time install path by default; `--dry-run` is the
only preview mode. `install` should not upgrade an existing Ask UI setup.

## Update Responsibilities

`npx ask-ui update` is the main update command because Ask UI has more than one
versioned part. It should require an existing Ask UI setup, then update and
validate the set together:

- npm installer package;
- `ask_ui_bridge`;
- installed `ask-ui` skill;
- local Ask UI project metadata, if present.

The command should finish by running diagnostics so users know whether the
updated installation is usable. Runtime compatibility should be checked by
diagnostics rather than updated by the npm installer.

If `.ask-ui/config.json` exists but is malformed or incomplete, `update` should
still treat the project as an existing Ask UI setup. It should install the
current installer manifest's Ask UI Version Set, rewrite metadata, and run
diagnostics.

If `.ask-ui/config.json` is missing, `update` should fail and tell the user to
run `npx ask-ui install` first. It should not turn itself into a first-time
install command.

The update target comes from the version manifest embedded in the currently
running npm installer package. `npx ask-ui@latest update` updates to the latest
published npm installer's Ask UI Version Set. `npx ask-ui@0.0.5 update` updates
or switches the existing setup to the 0.0.5 Ask UI Version Set. The update
command should not perform a separate network lookup for a latest manifest.
Because the target is explicit, `update` may switch to an older Ask UI Version
Set when the user runs an older installer such as `npx ask-ui@0.0.5 update`.
Bridge activation must therefore include the manifest bridge version instead of
using pub's floating latest resolution.

## Version Discovery

Ask UI should publish a small version manifest as the compatibility source of
truth. The manifest can live in the npm package, GitHub release assets, or a
stable hosted URL.

Example shape:

```json
{
  "latest": "0.0.5",
  "minimumSupported": "0.0.4",
  "packages": {
    "installer": "0.0.5",
    "bridge": "0.0.5",
    "runtime": "0.0.5",
    "skill": "0.0.5"
  },
  "sources": {
    "skillUrl": "https://github.com/drown0315/ask_ui/tree/v0.0.5/skills/ask-ui"
  }
}
```

The installer should record the installed set in local metadata, for example:

```json
{
  "version": "0.0.4",
  "bridge": "0.0.4",
  "runtime": "0.0.4",
  "skill": "0.0.4"
}
```

This metadata can live under `.ask-ui/config.json` in the target project.

## Update Notifications

Users should discover updates through normal commands they already run:

- `ask_ui_bridge doctor` should report when a newer compatible Ask UI version is
  available.
- `ask_ui_bridge launch` may perform the same check, rate-limited so it does not
  hit the network on every launch.
- The `ask-ui` skill should instruct agents to run diagnostics before launch, so
  agent-driven sessions surface the same update message.

Example message:

```text
Ask UI 0.0.5 is available. Current: 0.0.4.
Run: npx ask-ui update
```

## Compatibility Rules

The Ask UI version set should be treated as a compatible bundle. A given release
must define which bridge, runtime, and skill versions are expected to work
together.

Each Ask UI Version Set corresponds to a repository tag named `v<version>`.
The skill install URL should use that tag, not `main`, so the coding-agent
workflow is bound to the same release as the bridge and runtime expectation.

The installer and doctor command should warn when versions are mixed in a way
that may break the documented launch or agent-poll contract.

## Non-Goals

- Installing Dart, Flutter, Android SDK, Xcode, or device tooling.
- Hiding global environment changes from the user.
- Making `npx skills add https://github.com/drown0315/ask_ui/tree/v0.0.5/skills/ask-ui`
  install Dart or Flutter dependencies.
- Adding Ask UI-specific `--agent`, `--yes`, or `--skill-only` installer modes.
- Duplicating bridge launch behavior in JavaScript.
- Replacing `ask_ui_bridge launch` as the runtime startup contract.

## Implementation Notes

- The npm installer should call the manifest skill URL, for example
  `npx skills add https://github.com/drown0315/ask_ui/tree/v0.0.5/skills/ask-ui`.
- The installer should not pass `--agent`; Skills CLI defaults and Agent Skills
  client behavior own platform selection.
- Release validation should check that `skills/ask-ui`, `ask_ui_bridge`, and
  `ask_ui_runtime` describe the same versioned command contract.
