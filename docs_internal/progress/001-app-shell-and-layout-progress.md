# Progress: Issue 001 App Shell And Layout

Status: completed.

Related issue:

- [Issue 001: App Shell And Layout](../issues/001-app-shell-and-layout.md)

## Current Goal

Create the initial Vite + React + TypeScript web app shell for Ask UI Workbench.

This round only establishes the top-level layout and placeholder regions:

```text
TopBar
------------------------------------------------
WidgetTreePanel | LiveAppSurface | SelectionNotesPanel
```

## Progress Checklist

- [x] Create `apps/web` Vite + React + TypeScript app structure.
- [x] Add `AskUiWorkbench` root component.
- [x] Add placeholder `TopBar`.
- [x] Add placeholder `WidgetTreePanel`.
- [x] Add placeholder `LiveAppSurface`.
- [x] Add placeholder `SelectionNotesPanel`.
- [x] Add full viewport layout CSS.
- [x] Verify local dev server starts.
- [x] Verify skeleton layout in browser.
- [x] Update this progress file with final status.

## Out Of Scope For This Round

- Real toolbar controls.
- Widget tree hierarchy.
- Device phone frame or preview.
- Selection overlay.
- Selection notes cards.
- Comment editor.
- Agent composer.
- Mock product data.
- Flutter VM Service integration.
- Bridge/server.
- Agent communication.

## Acceptance Tracking

- [x] App starts locally with the Vite dev command.
- [x] Page fills browser viewport.
- [x] Top bar spans full width.
- [x] Below top bar is split into three columns.
- [x] Left and right columns keep stable widths.
- [x] Center column expands to fill remaining space.
- [x] Layout does not depend on device preview implementation.
- [x] Placeholder content does not overflow or break the layout.

## Notes

Keep this file updated during the implementation round. It is an internal working record, not a final product document.

## Work Log

- Created the minimal `apps/web` Vite + React + TypeScript shell.
- Added the `AskUiWorkbench` root component with `TopBar`, `WidgetTreePanel`, `LiveAppSurface`, and `SelectionNotesPanel` placeholders.
- Added viewport-level CSS for the top bar and three-column workbench layout.
- Installed local web dependencies using a project-local npm cache because the user-level npm cache has permission errors.
- Verified `npm run build` succeeds.
- Simplified the build script to `tsc --noEmit && vite build` so TypeScript checking does not emit config artifacts.
- Started the local Vite dev server at `http://127.0.0.1:5173/`.
- Verified the rendered skeleton with Chrome headless screenshot and DOM dump.
