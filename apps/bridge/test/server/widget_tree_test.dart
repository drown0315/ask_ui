import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'bridge_server_test_harness.dart';

void main() {
  group('AskUiBridgeServer widget tree API', () {
    late BridgeServerFixture fixture;

    setUp(() async {
      fixture = BridgeServerFixture();
      await fixture.start();
    });

    tearDown(() async {
      await fixture.close();
    });

    test('returns a normalized widget tree for an existing session', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final sessionId = await createSession(client, fixture.baseUri);

      final treeRequest = await client.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/widget-tree'),
      );
      final treeResponse = await treeRequest.close();
      final treeBody = jsonDecode(await utf8.decodeStream(treeResponse))
          as Map<String, Object?>;

      expect(treeResponse.statusCode, HttpStatus.ok);
      expect(fixture.inspectorClient.requestedSessionIds, [sessionId]);
      expect(
        fixture.logs,
        contains(
            '[ask_ui_bridge] widget_tree request session=$sessionId start'),
      );
      expect(
        fixture.logs,
        contains(
            '[ask_ui_bridge] widget_tree request session=$sessionId success'),
      );
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

      final request = await client.getUrl(
        fixture.baseUri.resolve('/api/sessions/session-missing/widget-tree'),
      );
      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.notFound);
      expect(body, containsPair('error', 'session_not_found'));
      expect(fixture.inspectorClient.requestedSessionIds, isEmpty);
    });

    test('returns the inspector failure message when widget tree fetch fails',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      fixture.inspectorClient.failure =
          Exception('No runnable Dart isolate found');

      final sessionId = await createSession(client, fixture.baseUri);

      final treeRequest = await client.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/widget-tree'),
      );
      final treeResponse = await treeRequest.close();
      final treeBody = jsonDecode(await utf8.decodeStream(treeResponse))
          as Map<String, Object?>;

      expect(treeResponse.statusCode, HttpStatus.badGateway);
      expect(treeBody, containsPair('error', 'widget_tree_fetch_failed'));
      expect(treeBody['message'], contains('No runnable Dart isolate found'));
    });
  });
}
