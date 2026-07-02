# Issue 001: App Shell And Layout

Status: ready for implementation.

## Goal

Create the initial Ask UI Workbench web app shell.

This issue only establishes the page skeleton and layout regions. It should make the future three-column workbench visible, but it should not implement detailed panel content or real product behavior.

## User-Facing Result

Opening the web app should show a stable development-tool style layout:

```text
TopBar
------------------------------------------------
WidgetTreePanel | DeviceStage | SelectionNotesPanel
```

The page should clearly reserve space for:

- Top toolbar.
- Left widget tree panel.
- Center device stage.
- Right selection notes panel.

## Scope

Implement:

- `apps/web` Vite + React + TypeScript app structure.
- `AskUiWorkbench` root component.
- Full viewport workbench layout.
- Placeholder `TopBar`.
- Placeholder `WidgetTreePanel`.
- Placeholder `DeviceStage`.
- Placeholder `SelectionNotesPanel`.
- Basic CSS for:
  - zero body margin.
  - full viewport app.
  - top bar fixed height.
  - three-column content area.
  - fixed left panel width.
  - fixed right panel width.
  - center panel filling remaining space.
  - panel borders/backgrounds.
  - overflow constraints.

Placeholder text is enough:

- `Ask UI`
- `Widget Tree`
- `Device Stage`
- `Selection Notes`

## Out Of Scope

Do not implement:

- Real TopBar buttons.
- Widget tree hierarchy.
- Device phone frame.
- Device preview placeholder.
- Selection overlay.
- Selection notes cards.
- Current selection card.
- Comment editor.
- Agent composer.
- Mock product data.
- Flutter VM Service integration.
- Bridge/server.
- WebSocket or HTTP APIs.
- Hot reload/hot restart behavior.
- Agent communication.

## Suggested Files

```text
apps/
  web/
    package.json
    index.html
    tsconfig.json
    vite.config.ts
    src/
      main.tsx
      app/
        AskUiWorkbench.tsx
        AskUiWorkbench.css
      components/
        top-bar/
          TopBar.tsx
        widget-tree/
          WidgetTreePanel.tsx
        device-stage/
          DeviceStage.tsx
        selection-notes/
          SelectionNotesPanel.tsx
```

## Acceptance Criteria

- The app can be started locally with the chosen Vite dev command.
- The page fills the browser viewport.
- The top bar spans the full width.
- The area below the top bar is split into three columns.
- The left and right columns keep stable widths.
- The center column expands to fill remaining space.
- The layout does not rely on the future device preview being implemented.
- No panel content overflows in a way that breaks the skeleton layout.
- The implementation does not introduce runtime dependencies unrelated to this shell.

## Notes

This issue intentionally keeps the layout slice small. Future issues should fill each region independently.

