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

    test('rejects sending Chat when no Agent poller is ready', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);

      final request = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'text': 'Make this button primary.'}));

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.conflict);
      expect(body, {'error': 'agent_not_ready'});

      final chatRequest = await client.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat'),
      );
      final chatResponse = await chatRequest.close();
      final chatBody = jsonDecode(await utf8.decodeStream(chatResponse))
          as Map<String, Object?>;

      expect(chatBody['messages'], isEmpty);
    });

    test('rejects empty and over-limit Chat send text', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);

      final emptyRequest = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      emptyRequest.headers.contentType = ContentType.json;
      emptyRequest.write(jsonEncode({'text': ' \n\t '}));
      final emptyResponse = await emptyRequest.close();
      final emptyBody = jsonDecode(await utf8.decodeStream(emptyResponse))
          as Map<String, Object?>;

      final longRequest = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      longRequest.headers.contentType = ContentType.json;
      longRequest.write(jsonEncode({'text': List.filled(4001, 'x').join()}));
      final longResponse = await longRequest.close();
      final longBody = jsonDecode(await utf8.decodeStream(longResponse))
          as Map<String, Object?>;

      expect(emptyResponse.statusCode, HttpStatus.badRequest);
      expect(emptyBody, {'error': 'empty_chat_message'});
      expect(longResponse.statusCode, HttpStatus.badRequest);
      expect(longBody, {'error': 'chat_message_too_long'});
    });

    test('sends plain text Chat to the active Agent poller', () async {
      final browserClient = HttpClient();
      final agentClient = HttpClient();
      addTearDown(browserClient.close);
      addTearDown(agentClient.close);
      final String sessionId = await createSession(
        browserClient,
        fixture.baseUri,
      );

      final pollRequest = await agentClient.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/poll'),
      );
      final Future<HttpClientResponse> pollResponseFuture = pollRequest.close();
      await waitForChatStatus(
        browserClient,
        fixture.baseUri,
        sessionId,
        'agent_ready',
      );

      final sendRequest = await browserClient.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      sendRequest.headers.contentType = ContentType.json;
      sendRequest.write(jsonEncode({'text': 'Make this button primary.'}));

      final sendResponse = await sendRequest.close();
      final sendBody = jsonDecode(await utf8.decodeStream(sendResponse))
          as Map<String, Object?>;
      final pollResponse = await pollResponseFuture;
      final pollBody = jsonDecode(await utf8.decodeStream(pollResponse))
          as Map<String, Object?>;

      expect(sendResponse.statusCode, HttpStatus.ok);
      expect(sendBody, {
        'status': 'ok',
        'message': {
          'id': 'message-1',
          'role': 'user',
          'text': 'Make this button primary.',
        },
      });
      expect(pollResponse.statusCode, HttpStatus.ok);
      expect(pollBody['message'], {
        'id': 'message-1',
        'role': 'user',
        'text': 'Make this button primary.',
      });
      expect(
        await readChatStatus(browserClient, fixture.baseUri, sessionId),
        'agent_working',
      );
    });

    test('sends Selection Comment attachments to the active Agent poller',
        () async {
      final browserClient = HttpClient();
      final agentClient = HttpClient();
      addTearDown(browserClient.close);
      addTearDown(agentClient.close);
      final String sessionId = await createSession(
        browserClient,
        fixture.baseUri,
      );

      final pollRequest = await agentClient.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/poll'),
      );
      final Future<HttpClientResponse> pollResponseFuture = pollRequest.close();
      await waitForChatStatus(
        browserClient,
        fixture.baseUri,
        sessionId,
        'agent_ready',
      );

      final sendRequest = await browserClient.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      sendRequest.headers.contentType = ContentType.json;
      sendRequest.write(
        jsonEncode({
          'context': {'projectRoot': '/Users/example/app'},
          'parts': [
            {
              'type': 'selection_comment',
              'attachment': {
                'id': 'selection-comment-1',
                'commentText': 'Make this button primary.',
                'selectedWidget': {
                  'id': 'widget-1',
                  'displayLabel': 'PrimaryButton',
                  'sourceLocation': 'lib/home.dart:12:4',
                  'visibleText': 'Save',
                  'semanticInfo': 'button',
                },
                'snapshot': {
                  'status': 'available',
                  'path':
                      '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
                },
              },
            },
            {
              'type': 'selection_comment',
              'attachment': {
                'id': 'selection-comment-2',
                'commentText': 'Tighten this copy.',
                'selectedWidget': {
                  'id': 'widget-2',
                  'displayLabel': 'Subtitle',
                },
                'snapshot': {'status': 'unavailable'},
              },
            },
            {
              'type': 'text',
              'text': 'Please update this screen.',
            },
          ],
        }),
      );

      final sendResponse = await sendRequest.close();
      final sendBody = jsonDecode(await utf8.decodeStream(sendResponse))
          as Map<String, Object?>;
      final pollResponse = await pollResponseFuture;
      final pollBody = jsonDecode(await utf8.decodeStream(pollResponse))
          as Map<String, Object?>;

      final expectedMessage = {
        'id': 'message-1',
        'role': 'user',
        'text': 'Please update this screen.',
        'context': {'projectRoot': '/Users/example/app'},
        'parts': [
          {
            'type': 'selection_comment',
            'attachment': {
              'id': 'selection-comment-1',
              'commentText': 'Make this button primary.',
              'selectedWidget': {
                'id': 'widget-1',
                'displayLabel': 'PrimaryButton',
                'sourceLocation': 'lib/home.dart:12:4',
                'visibleText': 'Save',
                'semanticInfo': 'button',
              },
              'snapshot': {
                'status': 'available',
                'path':
                    '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
              },
            },
          },
          {
            'type': 'selection_comment',
            'attachment': {
              'id': 'selection-comment-2',
              'commentText': 'Tighten this copy.',
              'selectedWidget': {
                'id': 'widget-2',
                'displayLabel': 'Subtitle',
              },
              'snapshot': {'status': 'unavailable'},
            },
          },
          {
            'type': 'text',
            'text': 'Please update this screen.',
          },
        ],
      };

      expect(sendResponse.statusCode, HttpStatus.ok);
      expect(sendBody, {
        'status': 'ok',
        'message': expectedMessage,
      });
      expect(pollResponse.statusCode, HttpStatus.ok);
      expect(pollBody['message'], expectedMessage);
    });

    test('sends Selection Comment attachments without typed text', () async {
      final browserClient = HttpClient();
      final agentClient = HttpClient();
      addTearDown(browserClient.close);
      addTearDown(agentClient.close);
      final String sessionId = await createSession(
        browserClient,
        fixture.baseUri,
      );

      final pollRequest = await agentClient.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/poll'),
      );
      final Future<HttpClientResponse> pollResponseFuture = pollRequest.close();
      await waitForChatStatus(
        browserClient,
        fixture.baseUri,
        sessionId,
        'agent_ready',
      );

      final sendRequest = await browserClient.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      sendRequest.headers.contentType = ContentType.json;
      sendRequest.write(
        jsonEncode({
          'context': {'projectRoot': '/Users/example/app'},
          'parts': [
            {
              'type': 'selection_comment',
              'attachment': {
                'id': 'selection-comment-1',
                'commentText': 'Make this button primary.',
                'selectedWidget': {
                  'id': 'widget-1',
                  'displayLabel': 'PrimaryButton',
                },
                'snapshot': {'status': 'unavailable'},
              },
            },
          ],
        }),
      );

      final sendResponse = await sendRequest.close();
      final sendBody = jsonDecode(await utf8.decodeStream(sendResponse))
          as Map<String, Object?>;
      final pollResponse = await pollResponseFuture;
      final pollBody = jsonDecode(await utf8.decodeStream(pollResponse))
          as Map<String, Object?>;

      final expectedMessage = {
        'id': 'message-1',
        'role': 'user',
        'text': '',
        'context': {'projectRoot': '/Users/example/app'},
        'parts': [
          {
            'type': 'selection_comment',
            'attachment': {
              'id': 'selection-comment-1',
              'commentText': 'Make this button primary.',
              'selectedWidget': {
                'id': 'widget-1',
                'displayLabel': 'PrimaryButton',
              },
              'snapshot': {'status': 'unavailable'},
            },
          },
        ],
      };

      expect(sendResponse.statusCode, HttpStatus.ok);
      expect(sendBody, {
        'status': 'ok',
        'message': expectedMessage,
      });
      expect(pollResponse.statusCode, HttpStatus.ok);
      expect(pollBody['message'], expectedMessage);
    });

    test('rejects malformed and over-limit Selection Comment attachment parts',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);

      Future<Map<String, Object?>> sendBody(
        Map<String, Object?> body,
      ) async {
        final request = await client.postUrl(
          fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
        final response = await request.close();
        final responseBody = jsonDecode(await utf8.decodeStream(response))
            as Map<String, Object?>;

        expect(response.statusCode, HttpStatus.badRequest);
        return responseBody;
      }

      final malformedBody = await sendBody({
        'parts': [
          {
            'type': 'selection_comment',
            'attachment': {
              'id': 'selection-comment-1',
              'commentText': 'Make this button primary.',
              'selectedWidget': {'id': 'widget-1'},
              'snapshot': {'status': 'unavailable'},
            },
          },
        ],
      });
      final longTextBody = await sendBody({
        'parts': [
          {
            'type': 'selection_comment',
            'attachment': {
              'id': 'selection-comment-1',
              'commentText': List.filled(1001, 'x').join(),
              'selectedWidget': {
                'id': 'widget-1',
                'displayLabel': 'PrimaryButton',
              },
              'snapshot': {'status': 'unavailable'},
            },
          },
        ],
      });
      final tooManyPartsBody = await sendBody({
        'parts': List<Object?>.generate(
          21,
          (index) => {
            'type': 'selection_comment',
            'attachment': {
              'id': 'selection-comment-$index',
              'commentText': 'Comment $index',
              'selectedWidget': {
                'id': 'widget-$index',
                'displayLabel': 'Widget$index',
              },
              'snapshot': {'status': 'unavailable'},
            },
          },
        ),
      });
      final repeatedTextPartsBody = await sendBody({
        'parts': [
          {'type': 'text', 'text': 'First.'},
          {'type': 'text', 'text': 'Second.'},
        ],
      });

      expect(malformedBody, {'error': 'invalid_chat_parts'});
      expect(longTextBody, {'error': 'invalid_chat_parts'});
      expect(tooManyPartsBody, {'error': 'invalid_chat_parts'});
      expect(repeatedTextPartsBody, {'error': 'invalid_chat_parts'});
    });

    test('writes an Agent reply and allows the Agent to poll again', () async {
      final browserClient = HttpClient();
      final agentClient = HttpClient();
      addTearDown(browserClient.close);
      addTearDown(agentClient.close);
      final String sessionId = await createSession(
        browserClient,
        fixture.baseUri,
      );

      final pollRequest = await agentClient.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/poll'),
      );
      final Future<HttpClientResponse> pollResponseFuture = pollRequest.close();
      await waitForChatStatus(
        browserClient,
        fixture.baseUri,
        sessionId,
        'agent_ready',
      );

      final sendRequest = await browserClient.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      sendRequest.headers.contentType = ContentType.json;
      sendRequest.write(jsonEncode({'text': 'Make this button primary.'}));
      await (await sendRequest.close()).drain<void>();
      await (await pollResponseFuture).drain<void>();

      final replyRequest = await agentClient.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/reply'),
      );
      replyRequest.headers.contentType = ContentType.json;
      replyRequest.write(jsonEncode({'text': 'Done.'}));

      final replyResponse = await replyRequest.close();
      final replyBody = jsonDecode(await utf8.decodeStream(replyResponse))
          as Map<String, Object?>;

      expect(replyResponse.statusCode, HttpStatus.ok);
      expect(replyBody, {
        'status': 'ok',
        'message': {
          'id': 'message-2',
          'role': 'agent',
          'text': 'Done.',
        },
      });
      expect(
        await readChatStatus(browserClient, fixture.baseUri, sessionId),
        'waiting_for_agent',
      );

      final nextPollRequest = await agentClient.getUrl(
        fixture.baseUri.resolve(
          '/api/sessions/$sessionId/agent/poll?timeoutMs=1',
        ),
      );
      final nextPollResponse = await nextPollRequest.close();
      final nextPollBody = jsonDecode(await utf8.decodeStream(nextPollResponse))
          as Map<String, Object?>;

      expect(nextPollResponse.statusCode, HttpStatus.ok);
      expect(nextPollBody['status'], 'timeout');

      final chatRequest = await browserClient.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat'),
      );
      final chatResponse = await chatRequest.close();
      final chatBody = jsonDecode(await utf8.decodeStream(chatResponse))
          as Map<String, Object?>;

      expect(chatBody['messages'], [
        {
          'id': 'message-1',
          'role': 'user',
          'text': 'Make this button primary.',
        },
        {
          'id': 'message-2',
          'role': 'agent',
          'text': 'Done.',
        },
      ]);
    });

    test('writes an Agent error as a system Chat History message', () async {
      final browserClient = HttpClient();
      final agentClient = HttpClient();
      addTearDown(browserClient.close);
      addTearDown(agentClient.close);
      final String sessionId = await createSession(
        browserClient,
        fixture.baseUri,
      );

      final errorRequest = await agentClient.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/error'),
      );
      errorRequest.headers.contentType = ContentType.json;
      errorRequest.write(jsonEncode({'text': 'Agent command failed.'}));

      final errorResponse = await errorRequest.close();
      final errorBody = jsonDecode(await utf8.decodeStream(errorResponse))
          as Map<String, Object?>;

      expect(errorResponse.statusCode, HttpStatus.ok);
      expect(errorBody, {
        'status': 'ok',
        'message': {
          'id': 'message-1',
          'role': 'system',
          'text': 'Agent command failed.',
        },
      });
    });
  });
}
