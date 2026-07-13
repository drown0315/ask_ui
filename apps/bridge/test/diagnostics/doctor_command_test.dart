import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/diagnostics/doctor_command.dart';
import 'package:ask_ui_bridge/versions/ask_ui_versions.dart';
import 'package:file_testkit/file_testkit.dart';
import 'package:test/test.dart';

void main() {
  group('Ask UI doctor command', () {
    test('reports a ready project with compatible local metadata', () async {
      await FileTestkit.runZoned(() async {
        final Directory projectRoot = Directory('/workspace/flutter_app');
        await _writeProject(
          projectRoot: projectRoot,
          pubspec: '''
name: flutter_app
dependencies:
  flutter:
    sdk: flutter
  ask_ui_runtime: ^0.0.5
''',
          metadata: {
            'version': '0.0.5',
            'bridge': '0.0.5',
            'runtime': '0.0.5',
            'skill': '0.0.5',
          },
        );

        final DoctorCommandResult result = await runDoctorCommand(
          ['doctor', '--project', projectRoot.path],
          manifest: _manifest(),
          bridgeVersion: '0.0.5',
          skillProbe: const _FakeSkillProbe(
            isInstalled: true,
            version: '0.0.5',
          ),
        );

        expect(result.exitCode, 0);
        expect(result.stderr, isEmpty);
        expect(jsonDecode(result.stdout), {
          'status': 'ready',
          'projectRoot': projectRoot.path,
          'checks': [
            {
              'name': 'bridge',
              'status': 'ok',
              'version': '0.0.5',
              'message': 'ask_ui_bridge is installed.',
            },
            {
              'name': 'runtime',
              'status': 'ok',
              'version': '^0.0.5',
              'message': 'ask_ui_runtime is declared in pubspec.yaml.',
            },
            {
              'name': 'skill',
              'status': 'ok',
              'version': '0.0.5',
              'message': 'ask-ui skill is installed.',
            },
            {
              'name': 'metadata',
              'status': 'ok',
              'version': '0.0.5',
              'message': 'Ask UI local metadata is compatible.',
            },
          ],
        });
      });
    });

    test(
        'reports missing runtime, skill, and metadata without mutating project',
        () async {
      await FileTestkit.runZoned(() async {
        final Directory projectRoot = Directory('/workspace/flutter_app');
        await _writeProject(
          projectRoot: projectRoot,
          pubspec: '''
name: flutter_app
dependencies:
  flutter:
    sdk: flutter
''',
        );

        final DoctorCommandResult result = await runDoctorCommand(
          ['doctor', '--project', projectRoot.path],
          manifest: _manifest(),
          bridgeVersion: '0.0.5',
          skillProbe: const _FakeSkillProbe(isInstalled: false),
        );

        expect(result.exitCode, 1);
        expect(result.stderr, isEmpty);
        expect(jsonDecode(result.stdout), {
          'status': 'needs_setup',
          'projectRoot': projectRoot.path,
          'checks': [
            {
              'name': 'bridge',
              'status': 'ok',
              'version': '0.0.5',
              'message': 'ask_ui_bridge is installed.',
            },
            {
              'name': 'runtime',
              'status': 'missing',
              'version': null,
              'message': 'Add ask_ui_runtime to pubspec.yaml.',
            },
            {
              'name': 'skill',
              'status': 'missing',
              'version': null,
              'message': 'Install the ask-ui skill.',
            },
            {
              'name': 'metadata',
              'status': 'missing',
              'version': null,
              'message': 'Run npx ask-ui install to record local metadata.',
            },
          ],
        });
        expect(
          File('${projectRoot.path}/.ask-ui/config.json').existsSync(),
          isFalse,
        );
      });
    });

    test('reports malformed metadata and mixed component versions', () async {
      await FileTestkit.runZoned(() async {
        final Directory malformedProject = Directory('/workspace/malformed');
        await _writeProject(
          projectRoot: malformedProject,
          pubspec: '''
name: malformed
dependencies:
  ask_ui_runtime: ^0.0.5
''',
          metadataSource: '{"version":"0.0.5","bridge":true}',
        );

        final DoctorCommandResult malformed = await runDoctorCommand(
          ['doctor', '--project', malformedProject.path],
          manifest: _manifest(),
          bridgeVersion: '0.0.5',
          skillProbe: const _FakeSkillProbe(isInstalled: true),
        );

        expect(malformed.exitCode, 1);
        expect(
          _namedCheck(malformed.stdout, 'metadata'),
          {
            'name': 'metadata',
            'status': 'invalid',
            'version': null,
            'message':
                'bridge must be a non-empty string. runtime must be a non-empty string. skill must be a non-empty string.',
          },
        );

        final Directory mixedProject = Directory('/workspace/mixed');
        await _writeProject(
          projectRoot: mixedProject,
          pubspec: '''
name: mixed
dependencies:
  ask_ui_runtime: ^0.0.5
''',
          metadata: {
            'version': '0.0.5',
            'bridge': '0.0.4',
            'runtime': '0.0.5',
            'skill': '0.0.3',
          },
        );

        final DoctorCommandResult mixed = await runDoctorCommand(
          ['doctor', '--project', mixedProject.path],
          manifest: _manifest(),
          bridgeVersion: '0.0.5',
          skillProbe: const _FakeSkillProbe(
            isInstalled: true,
            version: '0.0.3',
          ),
        );

        expect(mixed.exitCode, 1);
        expect(
          _namedCheck(mixed.stdout, 'metadata'),
          {
            'name': 'metadata',
            'status': 'incompatible',
            'version': '0.0.5',
            'message':
                'bridge is 0.0.4 but expected 0.0.5. skill is 0.0.3 but expected 0.0.5.',
          },
        );
      });
    });

    test('fails with JSON when arguments are invalid', () async {
      final DoctorCommandResult result = await runDoctorCommand(
        const ['doctor', '--unknown'],
        manifest: _manifest(),
        bridgeVersion: '0.0.5',
        skillProbe: const _FakeSkillProbe(isInstalled: true),
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'invalid_arguments',
      });
    });
  });
}

Map<String, Object?> _namedCheck(String stdout, String name) {
  final Map<String, Object?> output =
      jsonDecode(stdout) as Map<String, Object?>;
  final List<Object?> checks = output['checks'] as List<Object?>;
  return checks.cast<Map<String, Object?>>().singleWhere(
        (Map<String, Object?> check) => check['name'] == name,
      );
}

Future<void> _writeProject({
  required Directory projectRoot,
  required String pubspec,
  Map<String, Object?>? metadata,
  String? metadataSource,
}) async {
  await projectRoot.create(recursive: true);
  await File('${projectRoot.path}/pubspec.yaml').writeAsString(pubspec);
  if (metadata != null || metadataSource != null) {
    await Directory('${projectRoot.path}/.ask-ui').create(recursive: true);
    await File('${projectRoot.path}/.ask-ui/config.json').writeAsString(
      metadataSource ?? jsonEncode(metadata),
    );
  }
}

AskUiVersionManifest _manifest() {
  return const AskUiVersionManifest(
    latest: '0.0.5',
    minimumSupported: '0.0.4',
    packages: AskUiComponentVersions(
      installer: '0.0.5',
      bridge: '0.0.5',
      runtime: '0.0.5',
      skill: '0.0.5',
    ),
  );
}

class _FakeSkillProbe implements AskUiSkillProbe {
  const _FakeSkillProbe({
    required this.isInstalled,
    this.version,
  });

  final bool isInstalled;

  final String? version;

  @override
  Future<AskUiSkillInstallation> inspect() async {
    return AskUiSkillInstallation(
      isInstalled: isInstalled,
      version: version,
    );
  }
}
