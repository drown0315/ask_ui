import 'dart:convert';

/// Compatible Ask UI component versions published for one release.
///
/// The manifest records the installer, bridge, runtime, and skill versions that
/// are expected to work together. Installers and diagnostics use this set to
/// detect mixed local installations.
class AskUiComponentVersions {
  const AskUiComponentVersions({
    required this.installer,
    required this.bridge,
    required this.runtime,
    required this.skill,
  });

  final String installer;
  final String bridge;
  final String runtime;
  final String skill;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'installer': installer,
      'bridge': bridge,
      'runtime': runtime,
      'skill': skill,
    };
  }
}

/// Published Ask UI version manifest used as the compatibility source of truth.
class AskUiVersionManifest {
  const AskUiVersionManifest({
    required this.latest,
    required this.minimumSupported,
    required this.packages,
  });

  final String latest;
  final String minimumSupported;
  final AskUiComponentVersions packages;

  static AskUiVersionManifest fromJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const AskUiVersionValidationException(<String>[
        'manifest must be a JSON object.',
      ]);
    }
    return fromMap(decoded);
  }

  static AskUiVersionManifest fromMap(Map<String, Object?> map) {
    final List<String> errors = <String>[];
    final String? latest = _readNonEmptyString(
      map,
      'latest',
      errors,
      label: 'latest',
    );
    final String? minimumSupported = _readNonEmptyString(
      map,
      'minimumSupported',
      errors,
      label: 'minimumSupported',
    );

    final Object? packagesValue = map['packages'];
    final Map<String, Object?> packagesMap;
    if (packagesValue is Map<String, Object?>) {
      packagesMap = packagesValue;
    } else {
      packagesMap = const <String, Object?>{};
      errors.add('packages must be a JSON object.');
    }

    final String? installer = _readNonEmptyString(
      packagesMap,
      'installer',
      errors,
      label: 'packages.installer',
    );
    final String? bridge = _readNonEmptyString(
      packagesMap,
      'bridge',
      errors,
      label: 'packages.bridge',
    );
    final String? runtime = _readNonEmptyString(
      packagesMap,
      'runtime',
      errors,
      label: 'packages.runtime',
    );
    final String? skill = _readNonEmptyString(
      packagesMap,
      'skill',
      errors,
      label: 'packages.skill',
    );

    if (errors.isNotEmpty) {
      throw AskUiVersionValidationException(errors);
    }

    return AskUiVersionManifest(
      latest: latest!,
      minimumSupported: minimumSupported!,
      packages: AskUiComponentVersions(
        installer: installer!,
        bridge: bridge!,
        runtime: runtime!,
        skill: skill!,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'latest': latest,
      'minimumSupported': minimumSupported,
      'packages': packages.toJson(),
    };
  }
}

/// Ask UI versions recorded for one local Flutter project.
class AskUiProjectMetadata {
  const AskUiProjectMetadata({
    required this.version,
    required this.bridge,
    required this.runtime,
    required this.skill,
  });

  final String version;
  final String bridge;
  final String runtime;
  final String skill;

  static AskUiProjectMetadata fromJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const AskUiVersionValidationException(<String>[
        'metadata must be a JSON object.',
      ]);
    }
    return fromMap(decoded);
  }

  static AskUiProjectMetadata fromMap(Map<String, Object?> map) {
    final List<String> errors = <String>[];
    final String? version = _readNonEmptyString(
      map,
      'version',
      errors,
      label: 'version',
    );
    final String? bridge = _readNonEmptyString(
      map,
      'bridge',
      errors,
      label: 'bridge',
    );
    final String? runtime = _readNonEmptyString(
      map,
      'runtime',
      errors,
      label: 'runtime',
    );
    final String? skill = _readNonEmptyString(
      map,
      'skill',
      errors,
      label: 'skill',
    );

    if (errors.isNotEmpty) {
      throw AskUiVersionValidationException(errors);
    }

    return AskUiProjectMetadata(
      version: version!,
      bridge: bridge!,
      runtime: runtime!,
      skill: skill!,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'bridge': bridge,
      'runtime': runtime,
      'skill': skill,
    };
  }
}

/// Result of comparing local project metadata with a published manifest.
class AskUiVersionCompatibility {
  const AskUiVersionCompatibility({
    required this.status,
    required this.messages,
  });

  final AskUiVersionCompatibilityStatus status;
  final List<String> messages;

  static AskUiVersionCompatibility check({
    required AskUiVersionManifest manifest,
    required AskUiProjectMetadata metadata,
  }) {
    final List<String> messages = <String>[];
    _addMismatch(
      messages,
      name: 'bridge',
      actual: metadata.bridge,
      expected: manifest.packages.bridge,
    );
    _addMismatch(
      messages,
      name: 'runtime',
      actual: metadata.runtime,
      expected: manifest.packages.runtime,
    );
    _addMismatch(
      messages,
      name: 'skill',
      actual: metadata.skill,
      expected: manifest.packages.skill,
    );

    return AskUiVersionCompatibility(
      status: messages.isEmpty
          ? AskUiVersionCompatibilityStatus.compatible
          : AskUiVersionCompatibilityStatus.mixed,
      messages: List<String>.unmodifiable(messages),
    );
  }

  static void _addMismatch(
    List<String> messages, {
    required String name,
    required String actual,
    required String expected,
  }) {
    if (actual == expected) {
      return;
    }
    messages.add('$name is $actual but expected $expected.');
  }
}

enum AskUiVersionCompatibilityStatus {
  compatible,
  mixed,
}

/// Validation error thrown when version JSON cannot become a typed model.
class AskUiVersionValidationException implements Exception {
  const AskUiVersionValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() {
    return 'AskUiVersionValidationException: ${errors.join(' ')}';
  }
}

String? _readNonEmptyString(
  Map<String, Object?> map,
  String key,
  List<String> errors, {
  required String label,
}) {
  final Object? value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  errors.add('$label must be a non-empty string.');
  return null;
}
