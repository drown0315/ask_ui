import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'bridge_server_test_harness.dart';

void main() {
  group('AskUiBridgeServer Select Widget API', () {
    late BridgeServerFixture fixture;

    setUp(() async {
      fixture = BridgeServerFixture();
      await fixture.start();
    });

    tearDown(() async {
      await fixture.close();
    });

    test('sets Select Widget mode for an existing session', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final sessionId = await createSession(client, fixture.baseUri);

      final selectRequest = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/select-widget-mode'),
      );
      selectRequest.headers.contentType = ContentType.json;
      selectRequest.write(jsonEncode({'enabled': true}));

      final selectResponse = await selectRequest.close();
      final selectBody = jsonDecode(await utf8.decodeStream(selectResponse))
          as Map<String, Object?>;

      expect(selectResponse.statusCode, HttpStatus.ok);
      expect(fixture.inspectorClient.selectWidgetModeRequests, [
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
        fixture.logs,
        contains(
          '[ask_ui_bridge] select_widget request session=$sessionId start enabled=true',
        ),
      );
      expect(
        fixture.logs,
        contains(
          '[ask_ui_bridge] select_widget request session=$sessionId success enabled=true',
        ),
      );
    });

    test('returns cached Select Widget mode status for an existing session',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      fixture.inspectorClient.selectWidgetModeStatus = true;

      final sessionId = await createSession(client, fixture.baseUri);

      final statusRequest = await client.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/select-widget-mode'),
      );
      final statusResponse = await statusRequest.close();
      final statusBody = jsonDecode(await utf8.decodeStream(statusResponse))
          as Map<String, Object?>;

      expect(statusResponse.statusCode, HttpStatus.ok);
      expect(fixture.inspectorClient.selectWidgetModeStatusSessionIds, [
        sessionId,
      ]);
      expect(statusBody, {
        'status': 'ok',
        'known': true,
        'enabled': true,
      });
    });

    test('streams the current Select Widget mode snapshot over SSE', () async {
      final client = HttpClient();
      addTearDown(client.close);
      fixture.inspectorClient.selectWidgetModeStatus = true;

      final sessionId = await createSession(client, fixture.baseUri);

      final eventsRequest = await client
          .getUrl(fixture.baseUri.resolve('/api/sessions/$sessionId/events'));
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

      final sessionId = await createSession(client, fixture.baseUri);

      final eventsRequest = await client
          .getUrl(fixture.baseUri.resolve('/api/sessions/$sessionId/events'));
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
        fixture.baseUri.resolve('/api/sessions/$sessionId/select-widget-mode'),
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

      final sessionId = await createSession(client, fixture.baseUri);

      final selectRequest = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/select-widget-mode'),
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
      expect(fixture.inspectorClient.selectWidgetModeRequests, isEmpty);
    });
  });
}
