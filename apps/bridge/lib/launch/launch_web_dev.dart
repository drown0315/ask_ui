part of 'launch_command.dart';

/// Extract the browser URL printed by Vite for the local dev server.
///
/// Vite may choose an alternate port when the default is busy. The launch
/// command uses the printed `Local:` URL so the browser opens the actual server.
Uri? parseViteDevServerUrlFromOutput(String output) {
  final RegExp localUrlPattern = RegExp(
    r'Local:\s+(https?://[^\s]+)',
    multiLine: true,
  );
  final RegExpMatch? match = localUrlPattern.firstMatch(output);
  if (match == null) {
    return null;
  }

  final Uri? uri = Uri.tryParse(match.group(1)!);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }

  return uri;
}

/// Starts the monorepo React/Vite workbench used by Ask UI contributors.
class NpmViteWebDevServer implements LaunchWebDevServer {
  NpmViteWebDevServer({
    Directory? webAppRoot,
    ViteDevServerProcessStarter startProcess = Process.start,
  })  : _webAppRoot = webAppRoot,
        _startProcess = startProcess;

  final Directory? _webAppRoot;
  final ViteDevServerProcessStarter _startProcess;

  @override
  Future<Uri> start({required String projectRoot}) async {
    final Directory webAppRoot = _webAppRoot ?? await _resolveWebAppRoot();
    late final Process process;
    try {
      process = await _startProcess(
        'npm',
        const ['run', 'dev', '--', '--host', '127.0.0.1'],
        workingDirectory: webAppRoot.path,
      );
    } catch (_) {
      throw const LaunchWebDevException('web_dev_start_failed');
    }

    final Completer<Uri> urlCompleter = Completer<Uri>();
    final StringBuffer startupOutput = StringBuffer();

    void observeOutput(List<int> data) {
      final String text = utf8.decode(data, allowMalformed: true);
      startupOutput.write(text);
      final Uri? devServerUrl =
          parseViteDevServerUrlFromOutput(startupOutput.toString());
      if (devServerUrl != null && !urlCompleter.isCompleted) {
        urlCompleter.complete(devServerUrl);
      }
    }

    process.stdout.listen(observeOutput);
    process.stderr.listen(observeOutput);
    process.exitCode.then((int exitCode) {
      if (!urlCompleter.isCompleted) {
        urlCompleter.completeError(
          const LaunchWebDevException('web_dev_start_failed'),
        );
      }
    });

    try {
      return await urlCompleter.future.timeout(const Duration(seconds: 30));
    } on LaunchWebDevException {
      rethrow;
    } on TimeoutException {
      process.kill();
      throw const LaunchWebDevException('web_dev_url_not_found');
    } catch (_) {
      throw const LaunchWebDevException('web_dev_start_failed');
    }
  }
}

Future<Directory> _resolveWebAppRoot() async {
  final Uri? launchLibraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:ask_ui_bridge/launch/launch_command.dart'),
  );
  if (launchLibraryUri == null) {
    return Directory('../web');
  }

  return Directory.fromUri(launchLibraryUri.resolve('../../../web'));
}
