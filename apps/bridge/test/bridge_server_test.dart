import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/server/ask_ui_bridge_server.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/widget_tree/widget_tree_snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('AskUiBridgeServer', () {
    late AskUiBridgeServer server;
    late RecordingFlutterInspectorClient inspectorClient;
    late Uri baseUri;

    setUp(() async {
      inspectorClient = RecordingFlutterInspectorClient();
      server = AskUiBridgeServer(
        sessionStore: SessionStore(),
        inspectorClient: inspectorClient,
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
  });
}

class RecordingFlutterInspectorClient implements FlutterInspectorClient {
  final requestedSessionIds = <String>[];
  Exception? failure;

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
}
