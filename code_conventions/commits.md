# Commit Message Conventions

Use this convention when writing, reviewing, or recommending commit messages.
Keep commit messages compact, searchable, and useful for release notes.

## Format

```text
<type>(<scope>): <summary>
```

Examples:

```text
feat(parser): support capture labels
fix(runner): clean up launched app on failure
test(cli): cover validate command stderr
docs(prd): clarify run diff boundaries
chore(deps): update yaml package
refactor(progress): simplify step renderer
```

## Types

- `feat`: User-visible feature or capability.
- `fix`: Bug fix or incorrect behavior correction.
- `test`: Test-only change.
- `docs`: Documentation-only change.
- `refactor`: Internal restructuring with no intended behavior change.
- `chore`: Repository maintenance, tooling, generated metadata, or config.
- `perf`: Performance improvement.
- `ci`: Continuous integration configuration.

## Scopes

Prefer scopes that match project vocabulary and ownership boundaries.

Recommended scopes:

- `cli`
- `parser`
- `scenario`
- `runner`
- `runtime`
- `progress`
- `diff`
- `recording`
- `docs`
- `deps`
- `ci`

Use a different scope only when it names the changed subsystem more clearly.
Omit the scope only when the change genuinely crosses the whole repository.

## Summary

- Use a short imperative phrase.
- Start with a lowercase word unless a proper noun is required.
- Do not end with a period.
- Keep the first line at or below 72 characters when practical.
- Describe the observable change, not the mechanics of editing files.

Prefer:

```text
fix(cli): report validation errors on stderr
```

Avoid:

```text
fix(cli): changed command.dart
```

## Body

Use a body when the reason, tradeoff, migration note, or behavioral boundary is
not obvious from the summary.

Wrap body text at a readable width. Explain why the change exists and what
behavior changed. Avoid restating the diff.

## Breaking Changes

Mark breaking changes with `!` after the type or scope:

```text
feat(scenario)!: rename waitFor timeout field
```

Also include a footer that explains the migration:

```text
BREAKING CHANGE: waitFor.timeout is now waitFor.timeoutMs.
```

## Multi-Area Changes

If one commit touches several areas, choose the scope that best describes the
primary user-facing or architectural effect. Prefer smaller commits when the
areas can be reviewed independently.

## Agent Guidance

Before recommending commits, inspect staged content with:

```bash
git status --short
git diff --cached --stat
git diff --cached --name-status
```

Only describe content as staged when `git diff --cached` is non-empty.
