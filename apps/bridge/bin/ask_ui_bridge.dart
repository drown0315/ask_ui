import 'dart:io';

import 'package:ask_ui_bridge/app_controller/flutter_app_controller.dart';
import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/logging/bridge_logger.dart';
import 'package:ask_ui_bridge/server/ask_ui_bridge_server.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';

Future<void> main(List<String> args) async {
  final host = _readOption(args, '--host') ?? InternetAddress.loopbackIPv4.host;
  final port = int.tryParse(_readOption(args, '--port') ?? '') ?? 8787;
  final logger = BridgeLogger(write: stdout.writeln);

  final server = AskUiBridgeServer(
    sessionStore: SessionStore(),
    inspectorClient: VmServiceFlutterInspectorClient(
      vmServiceFactory: VmServiceFactory(),
    ),
    appController: VmServiceFlutterAppController(
      vmServiceFactory: VmServiceFactory(),
      logger: logger,
    ),
    logger: logger,
  );
  final boundPort = await server.start(host: host, port: port);

  stdout.writeln('Ask UI bridge listening at http://$host:$boundPort');
}

String? _readOption(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}
