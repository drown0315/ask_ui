import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/server/ask_ui_bridge_server.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('AskUiBridgeServer', () {
    late AskUiBridgeServer server;
    late Uri baseUri;

    setUp(() async {
      server = AskUiBridgeServer(sessionStore: SessionStore());
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
  });
}
