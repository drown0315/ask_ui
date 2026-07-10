import 'dart:io';
import 'dart:isolate';

import 'package:ask_ui_bridge/agent_command/agent_session_command.dart';
import 'package:ask_ui_bridge/app_controller/flutter_app_controller.dart';
import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/logging/bridge_logger.dart';
import 'package:ask_ui_bridge/server/ask_ui_bridge_server.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';

Future<void> main(List<String> args) async {
  if (_isAgentCommand(args)) {
    final AgentCommandResult result = await runAgentSessionCommand(
      args,
      environment: Platform.environment,
      transport: AgentHttpCommandTransport(),
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
    return;
  }

  final host = _readOption(args, '--host') ?? InternetAddress.loopbackIPv4.host;
  final port = int.tryParse(_readOption(args, '--port') ?? '') ?? 8787;
  final logger = BridgeLogger(write: stdout.writeln);
  final packagedWebRoot = await _resolvePackagedWebRoot();

  final server = AskUiBridgeServer(
    sessionStore: SessionStore(),
    inspectorClient: VmServiceFlutterInspectorClient(
      vmServiceFactory: VmServiceFactory(),
    ),
    appController: VmServiceFlutterAppController(
      vmServiceFactory: VmServiceFactory(),
      logger: logger,
    ),
    packagedWebRoot: packagedWebRoot,
    logger: logger,
  );
  final boundPort = await server.start(host: host, port: port);

  stdout.writeln('Ask UI bridge listening at http://$host:$boundPort');
}

bool _isAgentCommand(List<String> args) {
  return args.isNotEmpty && args.first == 'agent';
}

String? _readOption(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
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
