part of 'launch_command.dart';

typedef FlutterDevicesRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef ViteDevServerProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Starts the target Flutter app and returns the VM Service URI it exposes.
abstract interface class LaunchAppLauncher {
  Future<LaunchAppResult> launch({
    required List<String> flutterRunArguments,
    required String projectRoot,
  });
}

/// VM Service details captured from a successful Flutter app startup.
class LaunchAppResult {
  const LaunchAppResult({required this.vmServiceUri});

  final String vmServiceUri;
}

/// Normalized Flutter startup failure for launch command JSON output.
class LaunchAppException implements Exception {
  const LaunchAppException(this.code);

  final String code;
}

/// Starts or reuses the local Bridge Server and creates a Bridge Session.
abstract interface class LaunchBridgeLauncher {
  Future<LaunchBridgeSession> createSession({
    required String vmServiceUri,
    required String projectRoot,
    required String deviceId,
    required bool requirePackagedWeb,
  });
}

/// Bridge Session connection details returned to the launcher.
class LaunchBridgeSession {
  const LaunchBridgeSession({
    required this.bridgeUrl,
    required this.sessionId,
  });

  final Uri bridgeUrl;
  final String sessionId;
}

/// Normalized Bridge startup/session failure for launch command JSON output.
class LaunchBridgeException implements Exception {
  const LaunchBridgeException(this.code);

  final String code;
}

/// Opens the workbench URL after launch creates a Bridge Session.
abstract interface class LaunchBrowserOpener {
  Future<void> open(Uri url);
}

/// Normalized browser-open failure recorded in successful launch output.
class LaunchBrowserOpenException implements Exception {
  const LaunchBrowserOpenException(this.code);

  final String code;
}

/// Starts or reuses the Vite workbench server for monorepo development.
abstract interface class LaunchWebDevServer {
  Future<Uri> start({required String projectRoot});
}

/// Normalized Web development server failure for launch command JSON output.
class LaunchWebDevException implements Exception {
  const LaunchWebDevException(this.code);

  final String code;
}

/// Result returned by the launch command runner.
///
/// The binary writes `stdout`, `stderr`, and `exitCode` directly. Tests use the
/// same object to verify the JSON contract without spawning a subprocess.
class LaunchCommandResult {
  const LaunchCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
