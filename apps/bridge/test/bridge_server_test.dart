import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/app_controller/flutter_app_controller.dart';
import 'package:ask_ui_bridge/logging/bridge_logger.dart';
import 'package:ask_ui_bridge/server/ask_ui_bridge_server.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/widget_tree/widget_tree_snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('AskUiBridgeServer', () {
    late AskUiBridgeServer server;
    late RecordingFlutterInspectorClient inspectorClient;
    late RecordingFlutterAppController appController;
    late List<String> logs;
    late Uri baseUri;

    setUp(() async {
      inspectorClient = RecordingFlutterInspectorClient();
      appController = RecordingFlutterAppController();
      logs = <String>[];
      server = AskUiBridgeServer(
        sessionStore: SessionStore(),
        inspectorClient: inspectorClient,
        appController: appController,
        logger: BridgeLogger(write: logs.add),
      );
      final port =
          await server.start(host: InternetAddress.loopbackIPv4.host, port: 0);
      baseUri = Uri.parse('http://${InternetAddress.loopbackIPv4.host}:$port');
    });

    tearDown(() async {
      await server.close();
    });

    test('returns 400 when creating a session without required parameters',
        () async {
      final client = HttpClient();
      addTearDown(client.close);

      final request = await client.postUrl(baseUri.resolve('/api/sessions'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'vmServiceUri': 'ws://127.0.0.1:12345/ws'}));

      final response = await request.close();
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, HttpStatus.badRequest);
      expect(jsonDecode(body),
          containsPair('error', 'missing_session_parameters'));
    });

    test('creates a session from vmServiceUri and projectRoot', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final request = await client.postUrl(baseUri.resolve('/api/sessions'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.ok);
      expect(body['sessionId'], isA<String>());
      expect(body['sessionId'], isNotEmpty);
    });

    test('returns the same session for repeated target parameters', () async {
      final client = HttpClient();
      addTearDown(client.close);

      Future<String> createSession() async {
        final request = await client.postUrl(baseUri.resolve('/api/sessions'));
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({
            'vmServiceUri': 'ws://127.0.0.1:12345/ws',
            'projectRoot': '/Users/example/app',
          }),
        );

        final response = await request.close();
        final body = jsonDecode(await utf8.decodeStream(response))
            as Map<String, Object?>;

        expect(response.statusCode, HttpStatus.ok);
        return body['sessionId']! as String;
      }

      final firstSessionId = await createSession();
      final secondSessionId = await createSession();

      expect(secondSessionId, firstSessionId);
    });

    test('returns a normalized widget tree for an existing session', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final treeRequest = await client
          .getUrl(baseUri.resolve('/api/sessions/$sessionId/widget-tree'));
      final treeResponse = await treeRequest.close();
      final treeBody = jsonDecode(await utf8.decodeStream(treeResponse))
          as Map<String, Object?>;

      expect(treeResponse.statusCode, HttpStatus.ok);
      expect(inspectorClient.requestedSessionIds, [sessionId]);
      expect(
        treeBody,
        {
          'root': {
            'id': 'inspector-1',
            'label': 'MaterialApp',
            'children': [
              {
                'id': 'inspector-2',
                'label': 'Scaffold',
                'children': <Object?>[],
              },
            ],
          },
        },
      );
    });

    test('returns 404 when fetching a widget tree for an unknown session',
        () async {
      final client = HttpClient();
      addTearDown(client.close);

      final request = await client
          .getUrl(baseUri.resolve('/api/sessions/session-missing/widget-tree'));
      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.notFound);
      expect(body, containsPair('error', 'session_not_found'));
      expect(inspectorClient.requestedSessionIds, isEmpty);
    });

    test('returns the inspector failure message when widget tree fetch fails',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      inspectorClient.failure = Exception('No runnable Dart isolate found');

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final treeRequest = await client
          .getUrl(baseUri.resolve('/api/sessions/$sessionId/widget-tree'));
      final treeResponse = await treeRequest.close();
      final treeBody = jsonDecode(await utf8.decodeStream(treeResponse))
          as Map<String, Object?>;

      expect(treeResponse.statusCode, HttpStatus.badGateway);
      expect(treeBody, containsPair('error', 'widget_tree_fetch_failed'));
      expect(treeBody['message'], contains('No runnable Dart isolate found'));
    });

    test('returns a clear unsupported response for hot restart', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final restartRequest = await client
          .postUrl(baseUri.resolve('/api/sessions/$sessionId/hot-restart'));
      final restartResponse = await restartRequest.close();
      final restartBody = jsonDecode(await utf8.decodeStream(restartResponse))
          as Map<String, Object?>;

      expect(restartResponse.statusCode, HttpStatus.notImplemented);
      expect(appController.hotRestartSessionIds, [sessionId]);
      expect(
        restartBody,
        containsPair('error', 'hot_restart_not_supported_for_session'),
      );
      expect(
        restartBody['message'],
        'Hot restart is not available for this bridge session.',
      );
      expect(
        logs,
        contains(
            '[ask_ui_bridge] hot_restart request session=$sessionId start'),
      );
      expect(
        logs,
        contains(
            '[ask_ui_bridge] hot_restart request session=$sessionId unsupported'),
      );
    });

    test('runs hot reload for an existing session', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final reloadRequest = await client
          .postUrl(baseUri.resolve('/api/sessions/$sessionId/hot-reload'));
      final reloadResponse = await reloadRequest.close();
      final reloadBody = jsonDecode(await utf8.decodeStream(reloadResponse))
          as Map<String, Object?>;

      expect(reloadResponse.statusCode, HttpStatus.ok);
      expect(appController.hotReloadSessionIds, [sessionId]);
      expect(
        reloadBody,
        {
          'status': 'ok',
          'message': 'Hot reload completed.',
          'reloadReport': {
            'success': true,
          },
        },
      );
      expect(
          logs,
          contains(
              '[ask_ui_bridge] hot_reload request session=$sessionId start'));
      expect(
        logs,
        contains(
            '[ask_ui_bridge] hot_reload request session=$sessionId success'),
      );
    });

    test('sets Select Widget mode for an existing session', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final selectRequest = await client.postUrl(
        baseUri.resolve('/api/sessions/$sessionId/select-widget-mode'),
      );
      selectRequest.headers.contentType = ContentType.json;
      selectRequest.write(jsonEncode({'enabled': true}));

      final selectResponse = await selectRequest.close();
      final selectBody = jsonDecode(await utf8.decodeStream(selectResponse))
          as Map<String, Object?>;

      expect(selectResponse.statusCode, HttpStatus.ok);
      expect(inspectorClient.selectWidgetModeRequests, [
        const RecordedSelectWidgetModeRequest(
          sessionId: 'session-1',
          enabled: true,
        ),
      ]);
      expect(selectBody, {
        'status': 'ok',
        'enabled': true,
        'message': 'Select Widget mode enabled.',
      });
      expect(
        logs,
        contains(
          '[ask_ui_bridge] select_widget request session=$sessionId start enabled=true',
        ),
      );
      expect(
        logs,
        contains(
          '[ask_ui_bridge] select_widget request session=$sessionId success enabled=true',
        ),
      );
    });

    test('returns cached Select Widget mode status for an existing session',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      inspectorClient.selectWidgetModeStatus = true;

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final statusRequest = await client.getUrl(
        baseUri.resolve('/api/sessions/$sessionId/select-widget-mode'),
      );
      final statusResponse = await statusRequest.close();
      final statusBody = jsonDecode(await utf8.decodeStream(statusResponse))
          as Map<String, Object?>;

      expect(statusResponse.statusCode, HttpStatus.ok);
      expect(inspectorClient.selectWidgetModeStatusSessionIds, [sessionId]);
      expect(statusBody, {
        'status': 'ok',
        'known': true,
        'enabled': true,
      });
    });

    test('streams the current Select Widget mode snapshot over SSE', () async {
      final client = HttpClient();
      addTearDown(client.close);
      inspectorClient.selectWidgetModeStatus = true;

      final sessionId = await createSession(client, baseUri);

      final eventsRequest = await client
          .getUrl(baseUri.resolve('/api/sessions/$sessionId/events'));
      final eventsResponse = await eventsRequest.close();
      addTearDown(() => eventsResponse.detachSocket().then((socket) {
            socket.destroy();
          }));

      expect(eventsResponse.statusCode, HttpStatus.ok);
      expect(
        eventsResponse.headers.contentType?.mimeType,
        ContentType('text', 'event-stream').mimeType,
      );

      final event = await readSseEvent(eventsResponse);

      expect(event.name, 'bridge_session_event');
      expect(event.data, {
        'type': 'select_widget_mode_snapshot',
        'sessionId': sessionId,
        'payload': {
          'known': true,
          'enabled': true,
        },
      });
    });

    test('broadcasts Select Widget mode changes over SSE', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final sessionId = await createSession(client, baseUri);

      final eventsRequest = await client
          .getUrl(baseUri.resolve('/api/sessions/$sessionId/events'));
      final eventsResponse = await eventsRequest.close();
      addTearDown(() => eventsResponse.detachSocket().then((socket) {
            socket.destroy();
          }));
      final events = readSseEvents(eventsResponse).asBroadcastStream();

      await events
          .firstWhere(
            (event) => event.data['type'] == 'select_widget_mode_snapshot',
          )
          .timeout(const Duration(seconds: 2));
      final changedEvent = events
          .firstWhere(
            (event) => event.data['type'] == 'select_widget_mode_changed',
          )
          .timeout(const Duration(seconds: 2));

      final selectRequest = await client.postUrl(
        baseUri.resolve('/api/sessions/$sessionId/select-widget-mode'),
      );
      selectRequest.headers.contentType = ContentType.json;
      selectRequest.write(jsonEncode({'enabled': true}));
      final selectResponse = await selectRequest.close();
      await utf8.decodeStream(selectResponse);

      final event = await changedEvent;

      expect(event.name, 'bridge_session_event');
      expect(event.data, {
        'type': 'select_widget_mode_changed',
        'sessionId': sessionId,
        'payload': {
          'enabled': true,
        },
      });
    });

    test('rejects Select Widget mode requests without an enabled boolean',
        () async {
      final client = HttpClient();
      addTearDown(client.close);

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final selectRequest = await client.postUrl(
        baseUri.resolve('/api/sessions/$sessionId/select-widget-mode'),
      );
      selectRequest.headers.contentType = ContentType.json;
      selectRequest.write(jsonEncode({'enabled': 'true'}));

      final selectResponse = await selectRequest.close();
      final selectBody = jsonDecode(await utf8.decodeStream(selectResponse))
          as Map<String, Object?>;

      expect(selectResponse.statusCode, HttpStatus.badRequest);
      expect(
        selectBody,
        containsPair('error', 'invalid_select_widget_mode_request'),
      );
      expect(inspectorClient.selectWidgetModeRequests, isEmpty);
    });

    test('returns hot restart failures from the app controller', () async {
      final client = HttpClient();
      addTearDown(client.close);
      appController.hotRestartFailure = Exception('Flutter tool disconnected');

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final restartRequest = await client
          .postUrl(baseUri.resolve('/api/sessions/$sessionId/hot-restart'));
      final restartResponse = await restartRequest.close();
      final restartBody = jsonDecode(await utf8.decodeStream(restartResponse))
          as Map<String, Object?>;

      expect(restartResponse.statusCode, HttpStatus.badGateway);
      expect(restartBody, containsPair('error', 'hot_restart_failed'));
      expect(restartBody['message'], contains('Flutter tool disconnected'));
    });

    test('returns hot restart success from the app controller', () async {
      final client = HttpClient();
      addTearDown(client.close);
      appController.hotRestartSucceeds = true;

      final createRequest =
          await client.postUrl(baseUri.resolve('/api/sessions'));
      createRequest.headers.contentType = ContentType.json;
      createRequest.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
        }),
      );

      final createResponse = await createRequest.close();
      final createBody = jsonDecode(await utf8.decodeStream(createResponse))
          as Map<String, Object?>;
      final sessionId = createBody['sessionId']! as String;

      final restartRequest = await client
          .postUrl(baseUri.resolve('/api/sessions/$sessionId/hot-restart'));
      final restartResponse = await restartRequest.close();
      final restartBody = jsonDecode(await utf8.decodeStream(restartResponse))
          as Map<String, Object?>;

      expect(restartResponse.statusCode, HttpStatus.ok);
      expect(appController.hotRestartSessionIds, [sessionId]);
      expect(restartBody, {
        'status': 'ok',
        'message': 'Hot restart completed.',
      });
      expect(
        logs,
        contains(
            '[ask_ui_bridge] hot_restart request session=$sessionId start'),
      );
      expect(
        logs,
        contains(
            '[ask_ui_bridge] hot_restart request session=$sessionId success'),
      );
    });
  });
}

Future<String> createSession(HttpClient client, Uri baseUri) async {
  final createRequest = await client.postUrl(baseUri.resolve('/api/sessions'));
  createRequest.headers.contentType = ContentType.json;
  createRequest.write(
    jsonEncode({
      'vmServiceUri': 'ws://127.0.0.1:12345/ws',
      'projectRoot': '/Users/example/app',
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
