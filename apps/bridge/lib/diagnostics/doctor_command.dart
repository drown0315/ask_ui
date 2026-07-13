import 'dart:convert';
import 'dart:io';

import '../versions/ask_ui_versions.dart';

/// Result returned by the Ask UI doctor command.
class DoctorCommandResult {
  const DoctorCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Reads the installed `ask-ui` skill state for diagnostics.
abstract interface class AskUiSkillProbe {
  Future<AskUiSkillInstallation> inspect();
}

/// Local installation state for the `ask-ui` coding-agent skill.
class AskUiSkillInstallation {
  const AskUiSkillInstallation({
    required this.isInstalled,
    this.version,
  });

  final bool isInstalled;
  final String? version;
}

/// Filesystem-backed skill probe for common project-local and Codex locations.
class FileSystemAskUiSkillProbe implements AskUiSkillProbe {
  const FileSystemAskUiSkillProbe({
    required this.projectRoot,
    Map<String, String>? environment,
  }) : environment = environment ?? const <String, String>{};

  final String projectRoot;
  final Map<String, String> environment;

  @override
  Future<AskUiSkillInstallation> inspect() async {
    final List<File> candidates = <File>[
      File('$projectRoot/.agents/skills/ask-ui/SKILL.md'),
      if (_homeDirectory != null)
        File('$_homeDirectory/.codex/skills/ask-ui/SKILL.md'),
    ];
    for (final File candidate in candidates) {
      if (candidate.existsSync()) {
        return const AskUiSkillInstallation(isInstalled: true);
      }
    }
    return const AskUiSkillInstallation(isInstalled: false);
  }

  String? get _homeDirectory {
    final String? explicitHome = environment['HOME'];
    if (explicitHome != null && explicitHome.trim().isNotEmpty) {
      return explicitHome;
    }
    final String platformHome = Platform.environment['HOME'] ?? '';
    if (platformHome.trim().isEmpty) {
      return null;
    }
    return platformHome;
  }
}

/// Runs setup diagnostics for a Flutter project that should use Ask UI.
Future<DoctorCommandResult> runDoctorCommand(
  List<String> args, {
  AskUiVersionManifest manifest = defaultAskUiVersionManifest,
  String bridgeVersion = defaultAskUiBridgeVersion,
  AskUiSkillProbe? skillProbe,
}) async {
  late final _DoctorOptions options;
  try {
    options = _DoctorOptions.parse(args);
  } on _DoctorValidationError {
    return _doctorFailure('invalid_arguments');
  }

  final String projectRoot = options.projectRoot ?? Directory.current.path;
  final AskUiSkillProbe effectiveSkillProbe =
      skillProbe ?? FileSystemAskUiSkillProbe(projectRoot: projectRoot);
  final List<_DoctorCheck> checks = <_DoctorCheck>[
    _DoctorCheck.ok(
      name: 'bridge',
      version: bridgeVersion,
      message: 'ask_ui_bridge is installed.',
    ),
    _runtimeCheck(projectRoot),
    await _skillCheck(effectiveSkillProbe),
    _metadataCheck(projectRoot, manifest),
  ];
  final bool isReady = checks.every(
    (_DoctorCheck check) => check.status == 'ok',
  );

  return DoctorCommandResult(
    exitCode: isReady ? 0 : 1,
    stdout: jsonEncode(<String, Object?>{
      'status': isReady ? 'ready' : 'needs_setup',
      'projectRoot': projectRoot,
      'checks': checks
          .map((_DoctorCheck check) => check.toJson())
          .toList(growable: false),
    }),
    stderr: '',
  );
}

const String defaultAskUiBridgeVersion = '0.0.4';

const AskUiVersionManifest defaultAskUiVersionManifest = AskUiVersionManifest(
  latest: '0.0.4',
  minimumSupported: '0.0.4',
  packages: AskUiComponentVersions(
    installer: '0.0.4',
    bridge: '0.0.4',
    runtime: '0.0.1',
    skill: '0.0.4',
  ),
);

DoctorCommandResult _doctorFailure(String error) {
  return DoctorCommandResult(
    exitCode: 1,
    stdout: '',
    stderr: jsonEncode(<String, Object?>{
      'status': 'error',
      'error': error,
    }),
  );
}

_DoctorCheck _runtimeCheck(String projectRoot) {
  final File pubspec = File('$projectRoot/pubspec.yaml');
  if (!pubspec.existsSync()) {
    return _DoctorCheck.missing(
      name: 'runtime',
      message: 'Add ask_ui_runtime to pubspec.yaml.',
    );
  }
  final String source = pubspec.readAsStringSync();
  final RegExpMatch? match = RegExp(
    r'^\s*ask_ui_runtime\s*:\s*([^\s#]+)\s*$',
    multiLine: true,
  ).firstMatch(source);
  if (match == null) {
    return _DoctorCheck.missing(
      name: 'runtime',
      message: 'Add ask_ui_runtime to pubspec.yaml.',
    );
  }
  return _DoctorCheck.ok(
    name: 'runtime',
    version: match.group(1),
    message: 'ask_ui_runtime is declared in pubspec.yaml.',
  );
}

Future<_DoctorCheck> _skillCheck(AskUiSkillProbe skillProbe) async {
  final AskUiSkillInstallation installation = await skillProbe.inspect();
  if (!installation.isInstalled) {
    return _DoctorCheck.missing(
      name: 'skill',
      message: 'Install the ask-ui skill.',
    );
  }
  return _DoctorCheck.ok(
    name: 'skill',
    version: installation.version,
    message: 'ask-ui skill is installed.',
  );
}

_DoctorCheck _metadataCheck(
  String projectRoot,
  AskUiVersionManifest manifest,
) {
  final File metadataFile = File('$projectRoot/.ask-ui/config.json');
  if (!metadataFile.existsSync()) {
    return _DoctorCheck.missing(
      name: 'metadata',
      message: 'Run npx ask-ui install to record local metadata.',
    );
  }

  late final AskUiProjectMetadata metadata;
  try {
    metadata = AskUiProjectMetadata.fromJson(metadataFile.readAsStringSync());
  } on AskUiVersionValidationException catch (error) {
    return _DoctorCheck(
      name: 'metadata',
      status: 'invalid',
      version: null,
      message: error.errors.join(' '),
    );
  } on FormatException catch (error) {
    return _DoctorCheck(
      name: 'metadata',
      status: 'invalid',
      version: null,
      message: error.message,
    );
  }

  final AskUiVersionCompatibility compatibility =
      AskUiVersionCompatibility.check(
    manifest: manifest,
    metadata: metadata,
  );
  if (compatibility.status == AskUiVersionCompatibilityStatus.compatible) {
    return _DoctorCheck.ok(
      name: 'metadata',
      version: metadata.version,
      message: 'Ask UI local metadata is compatible.',
    );
  }
  return _DoctorCheck(
    name: 'metadata',
    status: 'incompatible',
    version: metadata.version,
    message: compatibility.messages.join(' '),
  );
}

class _DoctorOptions {
  const _DoctorOptions({this.projectRoot});

  final String? projectRoot;

  static _DoctorOptions parse(List<String> args) {
    final List<String> rest = args.isNotEmpty && args.first == 'doctor'
        ? args.skip(1).toList(growable: false)
        : args;
    String? projectRoot;
    int index = 0;
    while (index < rest.length) {
      final String argument = rest[index];
      if (argument == '--project' || argument == '--project-root') {
        if (index + 1 >= rest.length) {
          throw const _DoctorValidationError();
        }
        projectRoot = rest[index + 1];
        index += 2;
      } else {
        throw const _DoctorValidationError();
      }
    }
    return _DoctorOptions(projectRoot: projectRoot);
  }
}

class _DoctorCheck {
  const _DoctorCheck({
    required this.name,
    required this.status,
    required this.version,
    required this.message,
  });

  factory _DoctorCheck.ok({
    required String name,
    required String? version,
    required String message,
  }) {
    return _DoctorCheck(
      name: name,
      status: 'ok',
      version: version,
      message: message,
    );
  }

  factory _DoctorCheck.missing({
    required String name,
    required String message,
  }) {
    return _DoctorCheck(
      name: name,
      status: 'missing',
      version: null,
      message: message,
    );
  }

  final String name;
  final String status;
  final String? version;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'status': status,
      'version': version,
      'message': message,
    };
  }
}

class _DoctorValidationError {
  const _DoctorValidationError();
}
