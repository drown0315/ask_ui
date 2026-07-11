import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:test/test.dart';

import '../../tool/release_layout_validator.dart';

void main() {
  group('ReleaseLayoutValidator', () {
    test('accepts packaged Web files required by installed launch', () async {
      await FileTestkit.runZoned(() async {
        final Directory packageRoot = Directory('/ask-ui-bridge-package');
        await Directory('${packageRoot.path}/web/assets').create(
          recursive: true,
        );
        await File('${packageRoot.path}/web/index.html').writeAsString(
          '<!doctype html><div id="root"></div>',
        );
        await File('${packageRoot.path}/web/assets/index.js').writeAsString(
          'console.log("ask ui");',
        );
        await File('${packageRoot.path}/web/assets/index.css').writeAsString(
          'body { margin: 0; }',
        );

        final ReleaseLayoutResult result = ReleaseLayoutValidator.validate(
          packageRoot: packageRoot,
        );

        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });
    });

    test('reports every missing packaged Web requirement', () async {
      await FileTestkit.runZoned(() async {
        final Directory packageRoot = Directory('/ask-ui-bridge-package');
        await Directory('${packageRoot.path}/web/assets').create(
          recursive: true,
        );

        final ReleaseLayoutResult result = ReleaseLayoutValidator.validate(
          packageRoot: packageRoot,
        );

        expect(result.isValid, isFalse);
        expect(
          result.errors,
          containsAll(<String>[
            'Missing web/index.html.',
            'Missing JavaScript asset under web/assets.',
            'Missing CSS asset under web/assets.',
          ]),
        );
      });
    });
  });
}
