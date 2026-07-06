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

    test('rejects a second active Agent poll request', () async {
      final firstClient = HttpClient();
      final secondClient = HttpClient();
      addTearDown(firstClient.close);
      addTearDown(secondClient.close);
      final String sessionId =
          await createSession(firstClient, fixture.baseUri);

      final firstRequest = await firstClient.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/poll'),
      );
      final Future<HttpClientResponse> firstResponse = firstRequest.close();
      await waitForChatStatus(
        secondClient,
        fixture.baseUri,
        sessionId,
        'agent_ready',
      );

      final secondRequest = await secondClient.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/poll'),
      );
      final secondResponse = await secondRequest.close();
      final secondBody = jsonDecode(await utf8.decodeStream(secondResponse))
          as Map<String, Object?>;

      expect(secondResponse.statusCode, HttpStatus.conflict);
      expect(secondBody, {'error': 'agent_poll_already_active'});

      firstClient.close(force: true);
      await firstResponse.then<void>(
        (response) async {
          await response.drain<void>().catchError((_) {});
        },
        onError: (_) {},
      );
    });

    test('returns timeout for debug Agent poll requests', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);

      final request = await client.getUrl(
        fixture.baseUri.resolve(
          '/api/sessions/$sessionId/agent/poll?timeoutMs=1',
        ),
      );
      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.ok);
      expect(body, {
        'status': 'timeout',
        'message': null,
        'nextStep':
            'Process this Chat message, write an agent reply or system error, then poll again.',
      });
      expect(
        await readChatStatus(client, fixture.baseUri, sessionId),
        'waiting_for_agent',
      );
    });
  });
}
