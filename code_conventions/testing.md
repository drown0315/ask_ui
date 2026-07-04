# Testing Conventions

Use this convention when adding or reorganizing tests.

## Test File Organization

Split test files by the dominant reason a reader would open or change them,
not mechanically by production class name.

A good split reduces future cognitive load. When a behavior, protocol,
lifecycle phase, dependency boundary, or test type changes, the relevant tests
should be easy to find without scanning unrelated workflows.

Common split axes:

- Behavior or product capability: useful for endpoint-style classes that own
  multiple workflows.
- Protocol area: useful when message types, request/response shapes, or wire
  contracts dominate the risk.
- Lifecycle phase: useful for startup, ready/running, failure, cleanup, and
  retry-heavy code.
- Dependency boundary: useful when a module coordinates several adapters or
  external systems.
- Test type: useful when pure logic tests, contract tests, and
  integration-style tests would otherwise obscure each other.

Avoid continuing to append to a generic `<class>_test.dart` once the class owns
multiple unrelated workflows. A class can be one implementation unit while its
tests need several reader-oriented entry points.

Split before adding new tests when any of these are true:

- The file covers three or more unrelated workflows.
- The file requires shared helpers that unrelated tests depend on.
- The file is long enough that finding the relevant setup or assertions
  requires scanning.
- Upcoming work will add another cluster of tests with a different reason to
  change.

Shared helpers should live in a non-`*_test.dart` harness file near the tests
that use them. Keep harnesses boring and specific: server lifecycle setup,
fake dependencies, and request helpers are good; generic mini-framework
abstractions are not.

For endpoint-style bridge server tests, prefer:

- `test/server/session_test.dart`
- `test/server/device_test.dart`
- `test/server/widget_tree_test.dart`
- `test/server/select_widget_test.dart`
- `test/server/hot_action_test.dart`
- `test/server/bridge_server_test_harness.dart`

If one of those files grows around a new dominant concern, split again by the
new concern instead of preserving the first split forever.
