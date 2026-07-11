# Changelog

## 0.0.4

- Add the `ask_ui_bridge` executable for `ask_ui_bridge launch` after global activation.
- Add the launch workflow that starts Flutter, creates a Bridge Session, opens
  the workbench, and returns the Agent Session Command.
- Add `--web-dev` for Ask UI contributors who need the Vite workbench during
  local development.
- Package the built Ask UI Web workbench under the bridge package `web/`
  directory for installed users.
- Add bridge release layout validation for pub publishing.
