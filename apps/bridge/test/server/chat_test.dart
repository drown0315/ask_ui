import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'bridge_server_test_harness.dart';

void main() {
  group('AskUiBridgeServer Chat API', () {
    late BridgeServerFixture fixture;

    setUp(() async {
      fixture = BridgeServerFixture();
      await fixture.start();
    });

    tearDown(() async {
      await fixture.close();
    });

    test('returns the Bridge Session Chat snapshot', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);

      final request = await client.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat'),
      );
      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.ok);
      expect(body, {
        'status': 'ok',
        'agentStatus': 'waiting_for_agent',
        'messages': <Object?>[],
        'readOnly': false,
      });
    });

    test('marks a second browser client as read-only for the same session',
        () async {
      final client = HttpClient();
      addTearDown(client.close);

      final firstSessionId = await createSession(
        client,
        fixture.baseUri,
        clientId: 'browser-1',
      );
      final secondSessionId = await createSession(
        client,
        fixture.baseUri,
        clientId: 'browser-2',
      );

      expect(secondSessionId, firstSessionId);

      final request = await client.getUrl(
        fixture.baseUri.resolve(
          '/api/sessions/$secondSessionId/chat?clientId=browser-2',
        ),
      );
      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.ok);
      expect(body, containsPair('readOnly', true));
    });

    test('streams initial Chat state through session events', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);

      final request = await client.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/events'),
      );
      final response = await request.close();
      addTearDown(response.detachSocket);

      final List<SseEvent> events = <SseEvent>[];
      await for (final event in readSseEvents(response)) {
        events.add(event);
        if (events.length == 2) {
          break;
        }
      }

      expect(response.statusCode, HttpStatus.ok);
      expect(events.last.name, 'bridge_session_event');
      expect(events.last.data, {
        'type': 'chat_snapshot',
        'sessionId': sessionId,
        'payload': {
          'agentStatus': 'waiting_for_agent',
          'messages': <Object?>[],
        },
      });
    });
  });
}
