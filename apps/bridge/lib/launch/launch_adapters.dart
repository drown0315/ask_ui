part of 'launch_command.dart';

class _FlutterRunAppLauncher implements LaunchAppLauncher {
  const _FlutterRunAppLauncher();

  @override
  Future<LaunchAppResult> launch({
    required List<String> flutterRunArguments,
    required String projectRoot,
  }) async {
    late final Process process;
    try {
      process = await Process.start(
        'flutter',
        flutterRunArguments,
        workingDirectory: projectRoot,
      );
    } catch (_) {
      throw const LaunchAppException('flutter_run_failed');
    }

    final Completer<LaunchAppResult> vmServiceCompleter =
        Completer<LaunchAppResult>();
    final StringBuffer startupOutput = StringBuffer();

    void observeOutput(List<int> data) {
      final String text = utf8.decode(data, allowMalformed: true);
      startupOutput.write(text);
      final String? vmServiceUri =
          parseFlutterVmServiceUriFromOutput(startupOutput.toString());
      if (vmServiceUri != null && !vmServiceCompleter.isCompleted) {
        vmServiceCompleter
            .complete(LaunchAppResult(vmServiceUri: vmServiceUri));
      }
    }

    process.stdout.listen(observeOutput);
    process.stderr.listen(observeOutput);
    process.exitCode.then((int exitCode) {
      if (!vmServiceCompleter.isCompleted) {
        vmServiceCompleter.completeError(
          const LaunchAppException('flutter_run_failed'),
        );
      }
    });

    try {
      return await vmServiceCompleter.future.timeout(
        const Duration(minutes: 2),
      );
    } on LaunchAppException {
      rethrow;
    } on TimeoutException {
      process.kill();
      throw const LaunchAppException('flutter_vm_service_not_found');
    } catch (_) {
      throw const LaunchAppException('flutter_run_failed');
    }
  }
}

/// Extract the VM Service WebSocket URI from Flutter startup output.
///
/// Flutter commonly prints an HTTP service URI ending in the auth-code path,
/// while the existing Bridge Session contract stores the WebSocket URI. Already
/// normalized `ws` and `wss` URIs are returned unchanged.
String? parseFlutterVmServiceUriFromOutput(String output) {
  final RegExp uriPattern = RegExp(r'(wss?|https?)://[^\s]+');
  for (final RegExpMatch match in uriPattern.allMatches(output)) {
    final String rawUri = match.group(0)!.replaceFirst(RegExp(r'[),.;]+$'), '');
    final Uri? uri = Uri.tryParse(rawUri);
    if (uri == null || uri.host.isEmpty) {
      continue;
    }
    if (uri.scheme == 'ws' || uri.scheme == 'wss') {
      return uri.toString();
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final String websocketScheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final String normalizedPath = uri.path.endsWith('/ws')
          ? uri.path
          : '${uri.path.endsWith('/') ? uri.path : '${uri.path}/'}ws';
      return uri
          .replace(
            scheme: websocketScheme,
            path: normalizedPath,
          )
          .toString();
    }
  }

  return null;
}

/// Starts the local Bridge Server and posts the launch session request to it.
class LocalBridgeLauncher implements LaunchBridgeLauncher {
  LocalBridgeLauncher({
    HttpClient? httpClient,
    Directory? packagedWebRoot,
  })  : _httpClient = httpClient ?? HttpClient(),
        _packagedWebRoot = packagedWebRoot;

  final HttpClient _httpClient;
  final Directory? _packagedWebRoot;
  AskUiBridgeServer? _server;

  @override
  Future<LaunchBridgeSession> createSession({
    required String vmServiceUri,
    required String projectRoot,
    required String deviceId,
    required bool requirePackagedWeb,
  }) async {
    final Uri bridgeUrl = await _startOrReuseServer(
      requirePackagedWeb: requirePackagedWeb,
    );
    final Uri sessionUri = bridgeUrl.resolve('/api/sessions');

    try {
      final HttpClientRequest request = await _httpClient.postUrl(sessionUri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'vmServiceUri': vmServiceUri,
          'projectRoot': projectRoot,
          'deviceId': deviceId,
        }),
      );
      final HttpClientResponse response = await request.close();
      final String responseBody = await utf8.decodeStream(response);
      final Object? decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Expected session JSON object');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const LaunchBridgeException('session_creation_failed');
      }
      final Object? sessionId = decoded['sessionId'];
      if (sessionId is! String || sessionId.trim().isEmpty) {
        throw const LaunchBridgeException('session_creation_failed');
      }
      return LaunchBridgeSession(
        bridgeUrl: bridgeUrl,
        sessionId: sessionId,
      );
    } on LaunchBridgeException {
      rethrow;
    } catch (_) {
      throw const LaunchBridgeException('session_creation_failed');
    }
  }

  Future<Uri> _startOrReuseServer({required bool requirePackagedWeb}) async {
    final Uri bridgeUrl = Uri.parse('http://127.0.0.1:8787');
    if (_server != null) {
      return bridgeUrl;
    }

    final BridgeLogger logger = BridgeLogger(write: stderr.writeln);
    final Directory packagedWebRoot =
        _packagedWebRoot ?? await _resolvePackagedWebRoot();
    final bool hasPackagedWeb =
        await File('${packagedWebRoot.path}/index.html').exists();
    if (requirePackagedWeb && !hasPackagedWeb) {
      throw const LaunchBridgeException('packaged_web_not_found');
    }
    final AskUiBridgeServer server = AskUiBridgeServer(
      sessionStore: SessionStore(),
      inspectorClient: VmServiceFlutterInspectorClient(
        vmServiceFactory: VmServiceFactory(),
      ),
      appController: VmServiceFlutterAppController(
        vmServiceFactory: VmServiceFactory(),
        logger: logger,
      ),
      packagedWebRoot: hasPackagedWeb ? packagedWebRoot : null,
      logger: logger,
    );

    try {
      await server.start(host: '127.0.0.1', port: 8787);
      _server = server;
      return bridgeUrl;
    } on SocketException {
      return bridgeUrl;
    } catch (_) {
      throw const LaunchBridgeException('bridge_start_failed');
    }
  }
}

class _PlatformBrowserOpener implements LaunchBrowserOpener {
  const _PlatformBrowserOpener();

  @override
  Future<void> open(Uri url) async {
    final List<String> command = _browserOpenCommand(url);
    try {
      await Process.start(command.first, command.sublist(1));
    } catch (_) {
      throw const LaunchBrowserOpenException('browser_open_failed');
    }
  }

  List<String> _browserOpenCommand(Uri url) {
    if (Platform.isMacOS) {
      return <String>['open', url.toString()];
    }
    if (Platform.isWindows) {
      return <String>['cmd', '/c', 'start', '', url.toString()];
    }
    return <String>['xdg-open', url.toString()];
  }
}

Future<Directory> _resolvePackagedWebRoot() async {
  final Uri? serverLibraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:ask_ui_bridge/server/ask_ui_bridge_server.dart'),
  );
  if (serverLibraryUri == null) {
    return Directory('web');
  }

  return Directory.fromUri(serverLibraryUri.resolve('../../web'));
}
