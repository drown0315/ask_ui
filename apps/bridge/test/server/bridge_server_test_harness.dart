import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/app_controller/flutter_app_controller.dart';
import 'package:ask_ui_bridge/device/device_stream.dart';
import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/logging/bridge_logger.dart';
import 'package:ask_ui_bridge/server/ask_ui_bridge_server.dart';
import 'package:ask_ui_bridge/sessions/flutter_device_checker.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:ask_ui_bridge/widget_tree/widget_tree_snapshot.dart';

class BridgeServerFixture {
  late AskUiBridgeServer server;
  late RecordingFlutterInspectorClient inspectorClient;
  late RecordingFlutterAppController appController;
  late List<String> logs;
  late Uri baseUri;

  Future<void> start({
    FlutterDeviceChecker flutterDeviceChecker = const FakeFlutterDeviceChecker(
      {'19271FDF6007TY', 'device-1', 'device-2'},
    ),
    DeviceStreamFactory deviceStreamFactory = const ShellDeviceStreamFactory(),
    bool Function(String projectRoot) projectRootExists = _projectRootExists,
    Duration sessionEventsHeartbeatInterval = const Duration(seconds: 15),
  }) async {
    inspectorClient = RecordingFlutterInspectorClient();
    appController = RecordingFlutterAppController();
    logs = <String>[];
    await _startServer(
      flutterDeviceChecker: flutterDeviceChecker,
      deviceStreamFactory: deviceStreamFactory,
      projectRootExists: projectRootExists,
      sessionEventsHeartbeatInterval: sessionEventsHeartbeatInterval,
    );
  }

  Future<void> restartWithDeviceChecker(
    FlutterDeviceChecker flutterDeviceChecker,
  ) async {
    await server.close();
    await _startServer(
      flutterDeviceChecker: flutterDeviceChecker,
      deviceStreamFactory: const ShellDeviceStreamFactory(),
      projectRootExists: _projectRootExists,
      sessionEventsHeartbeatInterval: const Duration(seconds: 15),
    );
  }

  Future<void> restartWithDeviceSource(
    DeviceStreamFactory deviceStreamFactory,
  ) async {
    await server.close();
    await _startServer(
      flutterDeviceChecker: const FakeFlutterDeviceChecker(
        {'19271FDF6007TY', 'device-1', 'device-2'},
      ),
      deviceStreamFactory: deviceStreamFactory,
      projectRootExists: _projectRootExists,
      sessionEventsHeartbeatInterval: const Duration(seconds: 15),
    );
  }

  Future<void> close() async {
    await server.close();
  }

  Future<void> _startServer({
    required FlutterDeviceChecker flutterDeviceChecker,
    required DeviceStreamFactory deviceStreamFactory,
    required bool Function(String projectRoot) projectRootExists,
    required Duration sessionEventsHeartbeatInterval,
  }) async {
    server = AskUiBridgeServer(
      sessionStore: SessionStore(),
      inspectorClient: inspectorClient,
      appController: appController,
      flutterDeviceChecker: flutterDeviceChecker,
      deviceStreamFactory: deviceStreamFactory,
      projectRootExists: projectRootExists,
      sessionEventsHeartbeatInterval: sessionEventsHeartbeatInterval,
      logger: BridgeLogger(write: logs.add),
    );
    final port = await server.start(
      host: InternetAddress.loopbackIPv4.host,
      port: 0,
    );
    baseUri = Uri.parse('http://${InternetAddress.loopbackIPv4.host}:$port');
  }
}

bool _projectRootExists(String projectRoot) => true;

class FakeDeviceReady {
  const FakeDeviceReady({
    required this.screenWidth,
    required this.screenHeight,
    required this.maxFps,
  });

  final int screenWidth;
  final int screenHeight;
  final int maxFps;
}

class FakeDeviceSourceFactory implements DeviceStreamFactory {
  FakeDeviceSourceFactory({
    required this.ready,
    this.videoChunks = const [],
  });

  final FakeDeviceReady ready;
  final List<List<int>> videoChunks;

  @override
  Future<DeviceStream> start({
    required BridgeSession session,
    required DeviceStreamSink sink,
  }) async {
    sink.sendReady(DeviceMetadata(
      deviceId: session.deviceId,
      screenWidth: ready.screenWidth,
      screenHeight: ready.screenHeight,
      maxFps: ready.maxFps,
      videoCodec: 'h264',
      controlReady: true,
    ));
    for (final chunk in videoChunks) {
      sink.sendVideoChunk(chunk);
    }
    return const ShellDeviceStream();
  }
}

Future<String> createSession(
  HttpClient client,
  Uri baseUri, {
  String? clientId,
}) async {
  final createRequest = await client.postUrl(baseUri.resolve('/api/sessions'));
  createRequest.headers.contentType = ContentType.json;
  createRequest.write(
    jsonEncode({
      'vmServiceUri': 'ws://127.0.0.1:12345/ws',
      'projectRoot': '/Users/example/app',
      'deviceId': '19271FDF6007TY',
      if (clientId != null) 'clientId': clientId,
    }),
  );

  final createResponse = await createRequest.close();
  final createBody = jsonDecode(await utf8.decodeStream(createResponse))
      as Map<String, Object?>;

  return createBody['sessionId']! as String;
}

Stream<SseEvent> readSseEvents(HttpClientResponse response) async* {
  String? eventName;
  final dataLines = <String>[];

  await for (final line
      in response.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (eventName != null) {
        yield SseEvent(
          name: eventName,
          data: jsonDecode(dataLines.join('\n')) as Map<String, Object?>,
        );
      }
      eventName = null;
      dataLines.clear();
      continue;
    }

    if (line.startsWith('event: ')) {
      eventName = line.substring('event: '.length);
    } else if (line.startsWith('data: ')) {
      dataLines.add(line.substring('data: '.length));
    }
  }
}

Future<SseEvent> readSseEvent(HttpClientResponse response) {
  return readSseEvents(response).first.timeout(const Duration(seconds: 2));
}

class SseEvent {
  const SseEvent({
    required this.name,
    required this.data,
  });

  final String name;
  final Map<String, Object?> data;
}

class RecordingFlutterInspectorClient implements FlutterInspectorClient {
  final requestedSessionIds = <String>[];
  final selectWidgetModeRequests = <RecordedSelectWidgetModeRequest>[];
  final selectWidgetModeStatusSessionIds = <String>[];
  final selectedWidgets = <RecordedWidgetSelectionRequest>[];
  final _selectWidgetModeControllers =
      <String, StreamController<SelectWidgetModeStatus>>{};
  Exception? failure;
  bool? selectWidgetModeStatus;

  @override
  Future<WidgetTreeNode> fetchRootWidgetTree(BridgeSession session) async {
    requestedSessionIds.add(session.id);

    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }

    return const WidgetTreeNode(
      id: 'inspector-1',
      label: 'MaterialApp',
      children: [
        WidgetTreeNode(
          id: 'inspector-2',
          label: 'Scaffold',
          children: [],
        ),
      ],
    );
  }

  @override
  Future<SelectWidgetModeResult> setSelectWidgetMode(
    BridgeSession session, {
    required bool enabled,
  }) async {
    selectWidgetModeRequests.add(RecordedSelectWidgetModeRequest(
      sessionId: session.id,
      enabled: enabled,
    ));

    final result = SelectWidgetModeResult(
      enabled: enabled,
      message: enabled
          ? 'Select Widget mode enabled.'
          : 'Select Widget mode disabled.',
    );
    _selectWidgetModeControllers[session.id]
        ?.add(SelectWidgetModeStatus(enabled: result.enabled));

    return result;
  }

  @override
  Future<SelectWidgetModeStatus> getSelectWidgetModeStatus(
    BridgeSession session,
  ) async {
    selectWidgetModeStatusSessionIds.add(session.id);
    return SelectWidgetModeStatus(enabled: selectWidgetModeStatus);
  }

  @override
  Future<WidgetSelectionResult> selectWidgetById(
    BridgeSession session, {
    required String widgetId,
  }) async {
    selectedWidgets.add(RecordedWidgetSelectionRequest(
      sessionId: session.id,
      widgetId: widgetId,
    ));
    return WidgetSelectionResult(
      widgetId: widgetId,
      message: 'Widget selected.',
    );
  }

  @override
  Stream<SelectWidgetModeStatus> watchSelectWidgetModeStatus(
    BridgeSession session,
  ) {
    return _selectWidgetModeControllers
        .putIfAbsent(
          session.id,
          () => StreamController<SelectWidgetModeStatus>.broadcast(),
        )
        .stream;
  }
}

class RecordingFlutterAppController implements FlutterAppController {
  final hotReloadSessionIds = <String>[];
  final hotRestartSessionIds = <String>[];
  Exception? hotRestartFailure;
  bool hotRestartSucceeds = false;

  @override
  Future<HotReloadResult> hotReload(BridgeSession session) async {
    hotReloadSessionIds.add(session.id);
    return const HotReloadResult(
      message: 'Hot reload completed.',
      reloadReport: {
        'success': true,
      },
    );
  }

  @override
  Future<HotRestartResult> hotRestart(BridgeSession session) async {
    hotRestartSessionIds.add(session.id);

    final hotRestartFailure = this.hotRestartFailure;
    if (hotRestartFailure != null) {
      throw hotRestartFailure;
    }

    if (hotRestartSucceeds) {
      return const HotRestartResult(
        message: 'Hot restart completed.',
      );
    }

    throw const HotRestartUnsupportedException(
      'Hot restart is not available for this bridge session.',
    );
  }
}

class FailingFlutterDeviceChecker implements FlutterDeviceChecker {
  @override
  Future<FlutterDeviceAvailability> checkDeviceId(String deviceId) async {
    throw StateError('Flutter devices exploded');
  }
}

class RecordedSelectWidgetModeRequest {
  const RecordedSelectWidgetModeRequest({
    required this.sessionId,
    required this.enabled,
  });

  final String sessionId;
  final bool enabled;

  @override
  bool operator ==(Object other) {
    return other is RecordedSelectWidgetModeRequest &&
        other.sessionId == sessionId &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(sessionId, enabled);
}

class RecordedWidgetSelectionRequest {
  const RecordedWidgetSelectionRequest({
    required this.sessionId,
    required this.widgetId,
  });

  final String sessionId;
  final String widgetId;

  @override
  bool operator ==(Object other) {
    return other is RecordedWidgetSelectionRequest &&
        other.sessionId == sessionId &&
        other.widgetId == widgetId;
  }

  @override
  int get hashCode => Object.hash(sessionId, widgetId);
}
