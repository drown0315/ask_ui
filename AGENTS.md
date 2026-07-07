# AGENTS.md

## Project Context

Ask UI is a Flutter developer workbench for selecting precise UI targets, collecting comments, and handing that context to a coding agent.

Current web frontend lives in `apps/web` and uses Vite + React + TypeScript.

## Development Guidelines

- Keep changes scoped to the current issue or user request.
- Prefer existing project structure and documented plans in `docs_internal/`.
- Do not commit generated or local-only artifacts such as `node_modules/`, `dist/`, `.npm-cache/`, `.DS_Store`, or build info files.
- When changing the web app, verify with `npm run build` from `apps/web` before claiming completion when practical.

## React Component Boundaries

For non-trivial React UI, keep components separated by responsibility:

- Page and panel components compose hooks and section components.
- Custom hooks own workflow state, refs, async effects, and event handlers.
- Section components render focused UI regions.
- Pure domain rules live outside JSX and should have focused tests.

Do not keep adding behavior to a component that already mixes large JSX,
multiple state/ref values, async calls, and business workflows. Extract a hook
or section component in the same change.

For detailed guidance, see
`docs_internal/web-frontend-stack.md#react-component-boundaries`.

## Commit Message Constraint

Commit messages must use one of these prefixes:

- `feat:` for new user-facing functionality or product capability.
- `fix:` for bug fixes or behavior corrections.
- `chore:` for documentation, tooling, refactors, or maintenance work that does not add user-facing functionality.

Examples:

- `feat: add web app shell`
- `fix: correct workbench layout overflow`
- `chore: add agent contribution guidelines`
