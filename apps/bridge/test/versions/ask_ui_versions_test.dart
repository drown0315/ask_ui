import 'dart:convert';

import 'package:ask_ui_bridge/versions/ask_ui_versions.dart';
import 'package:test/test.dart';

void main() {
  group('Ask UI version manifest', () {
    test('parses the compatible Ask UI version set', () {
      final AskUiVersionManifest manifest = AskUiVersionManifest.fromJson(
        jsonEncode({
          'latest': '0.0.5',
          'minimumSupported': '0.0.4',
          'packages': {
            'installer': '0.0.5',
            'bridge': '0.0.5',
            'runtime': '0.0.5',
            'skill': '0.0.5',
          },
        }),
      );

      expect(manifest.latest, '0.0.5');
      expect(manifest.minimumSupported, '0.0.4');
      expect(manifest.packages.installer, '0.0.5');
      expect(manifest.packages.bridge, '0.0.5');
      expect(manifest.packages.runtime, '0.0.5');
      expect(manifest.packages.skill, '0.0.5');
      expect(manifest.toJson(), {
        'latest': '0.0.5',
        'minimumSupported': '0.0.4',
        'packages': {
          'installer': '0.0.5',
          'bridge': '0.0.5',
          'runtime': '0.0.5',
          'skill': '0.0.5',
        },
      });
    });

    test('rejects malformed manifests with structured validation errors', () {
      expect(
        () => AskUiVersionManifest.fromJson(
          jsonEncode({
            'latest': '0.0.5',
            'packages': {'bridge': '0.0.5'},
          }),
        ),
        throwsA(
          isA<AskUiVersionValidationException>().having(
            (AskUiVersionValidationException error) => error.errors,
            'errors',
            containsAll(<String>[
              'minimumSupported must be a non-empty string.',
              'packages.installer must be a non-empty string.',
              'packages.runtime must be a non-empty string.',
              'packages.skill must be a non-empty string.',
            ]),
          ),
        ),
      );
    });
  });

  group('Ask UI project metadata', () {
    test('parses the installed Ask UI version set', () {
      final AskUiProjectMetadata metadata = AskUiProjectMetadata.fromJson(
        jsonEncode({
          'version': '0.0.5',
          'bridge': '0.0.5',
          'runtime': '0.0.5',
          'skill': '0.0.5',
        }),
      );

      expect(metadata.version, '0.0.5');
      expect(metadata.bridge, '0.0.5');
      expect(metadata.runtime, '0.0.5');
      expect(metadata.skill, '0.0.5');
      expect(metadata.toJson(), {
        'version': '0.0.5',
        'bridge': '0.0.5',
        'runtime': '0.0.5',
        'skill': '0.0.5',
      });
    });

    test('rejects malformed metadata with structured validation errors', () {
      expect(
        () => AskUiProjectMetadata.fromJson(
          jsonEncode({
            'version': '0.0.5',
            'runtime': '',
          }),
        ),
        throwsA(
          isA<AskUiVersionValidationException>().having(
            (AskUiVersionValidationException error) => error.errors,
            'errors',
            containsAll(<String>[
              'bridge must be a non-empty string.',
              'runtime must be a non-empty string.',
              'skill must be a non-empty string.',
            ]),
          ),
        ),
      );
    });
  });

  group('Ask UI version compatibility', () {
    test('accepts metadata matching the manifest package set', () {
      final AskUiVersionCompatibility compatibility =
          AskUiVersionCompatibility.check(
        manifest: _manifest(),
        metadata: AskUiProjectMetadata(
          version: '0.0.5',
          bridge: '0.0.5',
          runtime: '0.0.5',
          skill: '0.0.5',
        ),
      );

      expect(compatibility.status, AskUiVersionCompatibilityStatus.compatible);
      expect(compatibility.messages, isEmpty);
    });

    test('reports mixed installed versions against the manifest package set',
        () {
      final AskUiVersionCompatibility compatibility =
          AskUiVersionCompatibility.check(
        manifest: _manifest(),
        metadata: AskUiProjectMetadata(
          version: '0.0.5',
          bridge: '0.0.4',
          runtime: '0.0.5',
          skill: '0.0.3',
        ),
      );

      expect(compatibility.status, AskUiVersionCompatibilityStatus.mixed);
      expect(compatibility.messages, [
        'bridge is 0.0.4 but expected 0.0.5.',
        'skill is 0.0.3 but expected 0.0.5.',
      ]);
    });
  });
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
