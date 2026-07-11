import 'dart:io';

import 'release_layout_validator.dart';

/// CLI entrypoint for checking the bridge package layout before pub publish.
void main(List<String> args) {
  final String packageRootPath =
      args.isEmpty ? Directory.current.path : args[0];
  final ReleaseLayoutResult result = ReleaseLayoutValidator.validate(
    packageRoot: Directory(packageRootPath),
  );

  if (result.isValid) {
    stdout.writeln('Bridge release layout is valid.');
    return;
  }

  stderr.writeln('Bridge release layout is invalid:');
  for (final String error in result.errors) {
    stderr.writeln('- $error');
  }
  exitCode = 1;
}
