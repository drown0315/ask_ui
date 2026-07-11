import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ios_screen_mvp_server/flutter_runtime_control.dart';
import 'package:ios_screen_mvp_server/mvp_server.dart';
import 'package:ios_screen_mvp_server/video_stream.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('vm-service-uri', mandatory: true)
    ..addOption('device-id', mandatory: true)
    ..addOption('web-root')
    ..addOption('port', defaultsTo: '8765');
  late final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final mvpRoot = File.fromUri(Platform.script).parent.parent.parent;
  final sourcePath = '${mvpRoot.path}/native/ios_capture.swift';
  final webRoot = options.option('web-root') ?? '${mvpRoot.path}/web/dist';
  final vmServiceUri = Uri.parse(options.option('vm-service-uri')!);
  final deviceId = options.option('device-id')!;
  final port = int.tryParse(options.option('port')!);
  if (port == null || port < 0 || port > 65535) {
    stderr.writeln('--port must be between 0 and 65535.');
    exitCode = 64;
    return;
  }

  final mvp = MvpServer(
    webRoot: webRoot,
    captureFactory: () =>
        NativeCaptureSession.start(sourcePath: sourcePath, deviceId: deviceId),
    controlFactory: (metadata) async => FlutterRuntimeControl(
      metadata: metadata,
      adapter: await LiveVmServiceAdapter.connect(vmServiceUri),
    ),
  );
  final server = await shelf_io.serve(mvp.handler, '127.0.0.1', port);
  stdout.writeln('iOS Screen MVP listening on http://127.0.0.1:${server.port}');

  final stopping = Completer<void>();
  late final StreamSubscription<ProcessSignal> interrupt;
  late final StreamSubscription<ProcessSignal> terminate;
  Future<void> stop(ProcessSignal _) async {
    if (stopping.isCompleted) return;
    await server.close(force: true);
    stopping.complete();
  }

  interrupt = ProcessSignal.sigint.watch().listen(stop);
  terminate = ProcessSignal.sigterm.watch().listen(stop);
  await stopping.future;
  await interrupt.cancel();
  await terminate.cancel();
}
