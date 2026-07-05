# Code Review Principles

Use this checklist when reviewing code changes. Focus on observable behavior,
failure modes, public contracts, and long-term maintainability instead of style
preferences.

## Review Control Flow, Not Just Local Code

- Check which layer owns the workflow.
- Exceptions that should stop the workflow must be handled at the workflow
  boundary.
- Lower-level helpers should not silently change whether the caller continues.

## Treat Failure Paths As First-Class Behavior

- If success produces a result, report, or log, expected failures should produce
  one too.
- A non-zero exit, thrown exception, or failed status should leave enough
  context to diagnose the cause.
- Cleanup or secondary failures must not erase the primary failure.

## Make Continuation After Failure Intentional

- Verify whether later operations should run after an earlier failure.
- Tests should cover that forbidden follow-up work does not happen.
- Catching an exception must not accidentally mean the workflow keeps going.

## Test Final Behavior

- Do not encode placeholder behavior just because implementation is incomplete.
- Avoid testing private structure when public behavior can prove the same rule.
- Add test seams only when they are valid production design seams.

## Make Public APIs Defend Their Contracts

- Public methods should validate inputs or clearly document and enforce
  preconditions.
- Prefer explicit errors over silently returning misleading results.

## Catch Only Owned Failures

- Public API argument errors are contract violations. Throw clear exceptions
  such as `ArgumentError` or `RangeError`; do not turn them into business
  results just to avoid throwing.
- CLI user input errors should become usage errors because the CLI owns that
  user-facing boundary.
- Internal helpers usually trust validated inputs from their caller. Rechecking
  every private method parameter adds noise unless the helper is its own
  contract boundary.
- Runtime, environment, and business-rule failures should be caught at the
  workflow boundary and recorded in the report, log, or command output.

## Ensure Arguments Affect Behavior

- Validate CLI and API parameters against their real semantic contract, not only
  parseability.
- After validation, confirm the parameter actually changes execution as
  promised.
- Treat accepted-but-ignored options as bugs.

## Isolate Side Effects

- File, network, clock, process, environment, and global state interactions
  should be isolated in tests.
- Use fake, in-memory, or testkit tools where appropriate.
- Be careful with subprocess tests: in-process mocks and zones usually do not
  cross process boundaries.

## Use Names That Reduce Explanation

- Prefer business-intent names over implementation-mechanics names.
- If a name repeatedly needs explanation, improve the name.
- Comments should clarify contracts and edge cases, not excuse confusing code.

## Review Observable Outcomes

- Ask what the user, caller, log, report, or downstream system sees.
- Check happy path, failure path, boundary input, duplicate or retry behavior,
  and cleanup behavior.
- Prioritize concrete behavioral risks over style preferences.

## Short Version

Review the contract under stress: control flow, failure reporting, continuation
rules, public API boundaries, parameter semantics, and side effects.
