import 'dart:io';

/// Validation result for the files required by the published bridge package.
///
/// A valid bridge package contains the Web workbench files copied from the
/// Vite build into `web/`. Installed users rely on those files because the
/// bridge serves the workbench from the pub package at launch time.
class ReleaseLayoutResult {
  const ReleaseLayoutResult(this.errors);

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// Checks that the bridge package contains the packaged Web workbench.
class ReleaseLayoutValidator {
  ReleaseLayoutValidator._();

  /// Validate required packaged Web files under [packageRoot].
  ///
  /// The validator expects:
  /// - `web/index.html`
  /// - at least one JavaScript asset under `web/assets`
  /// - at least one CSS asset under `web/assets`
  ///
  /// Missing files are reported together so release scripts can print one
  /// complete failure message instead of failing one file at a time.
  static ReleaseLayoutResult validate({required Directory packageRoot}) {
    final List<String> errors = <String>[];
    final File indexFile = File('${packageRoot.path}/web/index.html');
    final Directory assetsDirectory = Directory(
      '${packageRoot.path}/web/assets',
    );

    if (!indexFile.existsSync()) {
      errors.add('Missing web/index.html.');
    }

    final List<File> assetFiles = assetsDirectory.existsSync()
        ? assetsDirectory.listSync(recursive: true).whereType<File>().toList()
        : <File>[];

    if (!assetFiles.any((File file) => file.path.endsWith('.js'))) {
      errors.add('Missing JavaScript asset under web/assets.');
    }

    if (!assetFiles.any((File file) => file.path.endsWith('.css'))) {
      errors.add('Missing CSS asset under web/assets.');
    }

    return ReleaseLayoutResult(errors);
  }
}
