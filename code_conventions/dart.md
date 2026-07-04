# Dart Code Conventions

## 1. Explicit Types

Local variables should use explicit types when the value participates in public
behavior, validation, command output, or error handling.

Prefer:

```dart
final bool jsonOutput = argResults!.flag('json');
final Scenario scenario = ScenarioParser.parseFile(path);
final String? until = argResults!.option('until');
```

Avoid:

```dart
final jsonOutput = argResults!.flag('json');
final result = ScenarioParser.parseFile(path);
final until = argResults!.option('until');
```

Use explicit types especially for:

- parsed CLI flags and options
- parsed YAML values after type narrowing
- validation results and exceptions
- domain model objects such as `Scenario`, `ScenarioStep`, and `Finder`
- loop variables when they become part of validation paths

## 2. Stateless Utilities

If a class has no member state, prefer static methods and a private constructor.

Prefer:

```dart
class ScenarioParser {
  ScenarioParser._();

  static Scenario parseFile(String filePath) {
    ...
  }
}
```

Callers should then use:

```dart
final Scenario scenario = ScenarioParser.parseFile(path);
```

Avoid requiring callers to allocate an object with no state:

```dart
final Scenario scenario = ScenarioParser().parseFile(path);
```

Use an instance only when the object carries configuration, injected
dependencies, caches, or runtime state.

## 3. Parser Error Shape

Parser APIs should not return one object that contains both success data and
validation errors.

Prefer:

- return the typed domain object on success
- throw a domain validation exception on failure
- include structured validation errors inside that exception

Example:

```dart
class ScenarioValidationException implements Exception {
  const ScenarioValidationException(this.errors);

  final List<ScenarioValidationError> errors;
}

static Scenario parseFile(String filePath) {
  ...
  if (errors.isNotEmpty) {
    throw ScenarioValidationException(errors);
  }
  return Scenario(...);
}
```

Callers that need CLI output or JSON should catch the exception and decide how
to present it:

```dart
try {
  final Scenario scenario = ScenarioParser.parseFile(path);
  ...
} on ScenarioValidationException catch (error) {
  writeValidationErrors(error.errors);
}
```

Avoid:

```dart
final ScenarioParseResult result = ScenarioParser.parseFile(path);
if (!result.isValid) {
  ...
}
```

This keeps the parser interface clear: success returns a usable model; failure
is represented as an exception with structured details.

## 4. CLI Flags

Boolean flags should avoid generated negative forms when the negative form does
not express a meaningful user choice.

Prefer:

```dart
argParser.addFlag(
  'json',
  negatable: false,
  help: 'Print machine-readable validation output.',
);
```

This allows `--json` but avoids exposing `--no-json` when the default output is
already non-JSON.

## 5. Code Comments

Every code file should contain useful comments or doc comments that explain the
role of the file, class, method, or rule being implemented.

Follow `code_conventions/comments.md`:

- explain what the object or method represents
- describe important arguments and return values
- document validation and missing-input behavior
- prefer concrete domain language over abstract planning language

Do not add comments that merely repeat the code.
