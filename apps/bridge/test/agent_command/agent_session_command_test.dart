import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/agent_command/agent_session_command.dart';
import 'package:test/test.dart';

import '../server/bridge_server_test_harness.dart';

void main() {
  group('Agent Session Command', () {
    test('polls once using flag connection values before environment',
        () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport(
        pollResponse: {
          'status': 'ok',
          'message': {
            'id': 'message-7',
            'role': 'user',
            'text': 'Make this button primary.',
          },
          'nextStep': 'Bridge transport instruction.',
        },
      );

      final AgentCommandResult result = await runAgentSessionCommand(
        const [
          'agent',
          'poll',
          '--base-url',
          'http://127.0.0.1:8787',
          '--session-id',
          'session-from-flag',
          '--once',
        ],
        environment: const {
          'ASK_UI_BRIDGE_URL': 'http://127.0.0.1:9999',
          'ASK_UI_SESSION_ID': 'session-from-env',
        },
        transport: transport,
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(jsonDecode(result.stdout), {
        'status': 'ok',
        'message': {
          'id': 'message-7',
          'role': 'user',
          'text': 'Make this button primary.',
        },
        'nextStep':
            'Process message-7, then reply with --reply-to message-7 and either --agent-reply or --agent-error.',
      });
      expect(transport.requests, [
        (
          baseUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-from-flag',
        ),
      ]);
    });

    test('fails with JSON when connection configuration is missing', () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport(
        pollResponse: const <String, Object?>{},
      );

      final AgentCommandResult missingUrl = await runAgentSessionCommand(
        const ['agent', 'poll', '--once'],
        environment: const {'ASK_UI_SESSION_ID': 'session-1'},
        transport: transport,
      );
      final AgentCommandResult missingSession = await runAgentSessionCommand(
        const ['agent', 'poll', '--once'],
        environment: const {'ASK_UI_BRIDGE_URL': 'http://127.0.0.1:8787'},
        transport: transport,
      );

      expect(missingUrl.exitCode, 1);
      expect(missingUrl.stdout, isEmpty);
      expect(jsonDecode(missingUrl.stderr), {
        'status': 'error',
        'error': 'missing_bridge_url',
      });
      expect(missingSession.exitCode, 1);
      expect(missingSession.stdout, isEmpty);
      expect(jsonDecode(missingSession.stderr), {
        'status': 'error',
        'error': 'missing_session_id',
      });
      expect(transport.requests, isEmpty);
    });

    test('reports poll conflicts and unsupported flags as JSON failures',
        () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport(
        pollError: const AgentCommandException('agent_poll_already_active'),
      );

      final AgentCommandResult conflict = await runAgentSessionCommand(
        const ['agent', 'poll', '--once'],
        environment: const {
          'ASK_UI_BRIDGE_URL': 'http://127.0.0.1:8787',
          'ASK_UI_SESSION_ID': 'session-1',
        },
        transport: transport,
      );
      final AgentCommandResult timeoutFlag = await runAgentSessionCommand(
        const ['agent', 'poll', '--timeout', '1', '--once'],
        environment: const {
          'ASK_UI_BRIDGE_URL': 'http://127.0.0.1:8787',
          'ASK_UI_SESSION_ID': 'session-1',
        },
        transport: transport,
      );

      expect(conflict.exitCode, 1);
      expect(conflict.stdout, isEmpty);
      expect(jsonDecode(conflict.stderr), {
        'status': 'error',
        'error': 'agent_poll_already_active',
      });
      expect(timeoutFlag.exitCode, 1);
      expect(timeoutFlag.stdout, isEmpty);
      expect(jsonDecode(timeoutFlag.stderr), {
        'status': 'error',
        'error': 'invalid_arguments',
      });
      expect(transport.requests, [
        (
          baseUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
        ),
      ]);
    });

    test('HTTP transport reads poll JSON and normalizes bridge errors',
        () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);

      final List<Uri> requests = <Uri>[];
      final List<Map<String, Object?>> requestBodies = <Map<String, Object?>>[];
      server.listen((HttpRequest request) async {
        requests.add(request.uri);
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/agent/poll') &&
            request.uri.path.contains('/sessions/session-1/')) {
          request.response.write('\n');
          request.response.write(
            jsonEncode({
              'status': 'ok',
              'message': {
                'id': 'message-1',
                'role': 'user',
                'text': 'Make this button primary.',
              },
              'nextStep': 'Bridge transport instruction.',
            }),
          );
        } else if (request.uri.path.endsWith('/agent/reply')) {
          final Map<String, Object?> body =
              jsonDecode(await utf8.decodeStream(request))
                  as Map<String, Object?>;
          requestBodies.add(body);
          request.response.write(
            jsonEncode({
              'status': 'ok',
              'message': {
                'id': 'message-2',
                'role': 'agent',
                'text': body['text'],
                'replyToMessageId': body['replyToMessageId'],
              },
            }),
          );
        } else if (request.uri.path.endsWith('/agent/error')) {
          final Map<String, Object?> body =
              jsonDecode(await utf8.decodeStream(request))
                  as Map<String, Object?>;
          requestBodies.add(body);
          request.response.write(
            jsonEncode({
              'status': 'ok',
              'message': {
                'id': 'message-3',
                'role': 'system',
                'text': body['text'],
                'replyToMessageId': body['replyToMessageId'],
              },
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.conflict;
          request.response.write(
            jsonEncode({'error': 'agent_poll_already_active'}),
          );
        }
        await request.response.close();
      });

      final AgentHttpCommandTransport transport = AgentHttpCommandTransport();
      final Map<String, Object?> response = await transport.poll(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        sessionId: 'session-1',
      );
      final Map<String, Object?> replyResponse =
          await transport.writeAgentReply(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        sessionId: 'session-1',
        replyToMessageId: 'message-1',
        text: 'Done.',
      );
      final Map<String, Object?> errorResponse =
          await transport.writeAgentError(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        sessionId: 'session-1',
        replyToMessageId: 'message-1',
        text: 'Could not run tests.',
      );
      final Future<Map<String, Object?>> Function() conflictPoll = () {
        return transport.poll(
          baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
          sessionId: 'conflict',
        );
      };

      expect(response['message'], {
        'id': 'message-1',
        'role': 'user',
        'text': 'Make this button primary.',
      });
      expect(replyResponse['message'], {
        'id': 'message-2',
        'role': 'agent',
        'text': 'Done.',
        'replyToMessageId': 'message-1',
      });
      expect(errorResponse['message'], {
        'id': 'message-3',
        'role': 'system',
        'text': 'Could not run tests.',
        'replyToMessageId': 'message-1',
      });
      await expectLater(
        conflictPoll(),
        throwsA(
          isA<AgentCommandException>().having(
            (error) => error.code,
            'code',
            'agent_poll_already_active',
          ),
        ),
      );
      expect(requests, [
        Uri.parse('/api/sessions/session-1/agent/poll'),
        Uri.parse('/api/sessions/session-1/agent/reply'),
        Uri.parse('/api/sessions/session-1/agent/error'),
        Uri.parse('/api/sessions/conflict/agent/poll'),
      ]);
      expect(requestBodies, [
        {'text': 'Done.', 'replyToMessageId': 'message-1'},
        {'text': 'Could not run tests.', 'replyToMessageId': 'message-1'},
      ]);
    });

    test('binary agent poll writes JSON failure to stderr only', () async {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        const ['bin/ask_ui_bridge.dart', 'agent', 'poll', '--once'],
        workingDirectory: Directory.current.path,
        environment: const <String, String>{},
        includeParentEnvironment: false,
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr as String), {
        'status': 'error',
        'error': 'missing_bridge_url',
      });
    });

    test('writes an agent reply once with a required reply-to id', () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport(
        replyResponse: {
          'status': 'ok',
          'message': {
            'id': 'message-2',
            'role': 'agent',
            'text': 'Done.',
            'replyToMessageId': 'message-1',
          },
        },
      );

      final AgentCommandResult result = await runAgentSessionCommand(
        const [
          'agent',
          'poll',
          '--base-url',
          'http://127.0.0.1:8787',
          '--session-id',
          'session-1',
          '--reply-to',
          'message-1',
          '--agent-reply',
          'Done.',
          '--once',
        ],
        environment: const <String, String>{},
        transport: transport,
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(jsonDecode(result.stdout), {
        'status': 'ok',
        'writtenMessage': {
          'id': 'message-2',
          'role': 'agent',
          'text': 'Done.',
          'replyToMessageId': 'message-1',
        },
        'message': null,
        'nextStep': 'No further polling was requested.',
      });
      expect(transport.replyRequests, [
        (
          baseUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
          replyToMessageId: 'message-1',
          text: 'Done.',
        ),
      ]);
      expect(transport.requests, isEmpty);
    });

    test('validates agent reply once arguments before polling', () async {
      final FakeAgentCommandTransport invalidReplyTransport =
          FakeAgentCommandTransport(
        replyError: const AgentCommandException('invalid_reply_to_message'),
      );
      final FakeAgentCommandTransport localValidationTransport =
          FakeAgentCommandTransport();

      Future<AgentCommandResult> runReply(
        List<String> extraArgs, {
        FakeAgentCommandTransport? transport,
      }) {
        return runAgentSessionCommand(
          [
            'agent',
            'poll',
            '--base-url',
            'http://127.0.0.1:8787',
            '--session-id',
            'session-1',
            ...extraArgs,
          ],
          environment: const <String, String>{},
          transport: transport ?? localValidationTransport,
        );
      }

      final AgentCommandResult missingReplyTo = await runReply(
        const ['--agent-reply', 'Done.', '--once'],
      );
      final AgentCommandResult emptyReply = await runReply(
        const [
          '--reply-to',
          'message-1',
          '--agent-reply',
          '  ',
          '--once',
        ],
      );
      final AgentCommandResult longReply = await runReply([
        '--reply-to',
        'message-1',
        '--agent-reply',
        List<String>.filled(4001, 'x').join(),
        '--once',
      ]);
      final AgentCommandResult exclusive = await runReply(
        const [
          '--reply-to',
          'message-1',
          '--agent-reply',
          'Done.',
          '--agent-error',
          'Failed.',
          '--once',
        ],
      );
      final AgentCommandResult invalidReplyTo = await runReply(
        const [
          '--reply-to',
          'message-404',
          '--agent-reply',
          'Done.',
          '--once',
        ],
        transport: invalidReplyTransport,
      );

      expect(jsonDecode(missingReplyTo.stderr), {
        'status': 'error',
        'error': 'invalid_reply_to_message',
      });
      expect(jsonDecode(emptyReply.stderr), {
        'status': 'error',
        'error': 'empty_chat_message',
      });
      expect(jsonDecode(longReply.stderr), {
        'status': 'error',
        'error': 'chat_message_too_long',
      });
      expect(jsonDecode(exclusive.stderr), {
        'status': 'error',
        'error': 'invalid_arguments',
      });
      expect(jsonDecode(invalidReplyTo.stderr), {
        'status': 'error',
        'error': 'invalid_reply_to_message',
      });
      expect(localValidationTransport.requests, isEmpty);
      expect(localValidationTransport.replyRequests, isEmpty);
      expect(invalidReplyTransport.requests, isEmpty);
      expect(invalidReplyTransport.replyRequests.single.replyToMessageId,
          'message-404');
    });

    test('writes agent errors once with optional reply-to ids', () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport(
        errorResponses: <Map<String, Object?>>[
          {
            'status': 'ok',
            'message': {
              'id': 'message-1',
              'role': 'system',
              'text': 'Session setup failed.',
            },
          },
          {
            'status': 'ok',
            'message': {
              'id': 'message-3',
              'role': 'system',
              'text': 'Could not run tests.',
              'replyToMessageId': 'message-2',
            },
          },
        ],
      );

      final AgentCommandResult sessionError = await runAgentSessionCommand(
        const [
          'agent',
          'poll',
          '--base-url',
          'http://127.0.0.1:8787',
          '--session-id',
          'session-1',
          '--agent-error',
          'Session setup failed.',
          '--once',
        ],
        environment: const <String, String>{},
        transport: transport,
      );
      final AgentCommandResult correlatedError = await runAgentSessionCommand(
        const [
          'agent',
          'poll',
          '--base-url',
          'http://127.0.0.1:8787',
          '--session-id',
          'session-1',
          '--reply-to',
          'message-2',
          '--agent-error',
          'Could not run tests.',
          '--once',
        ],
        environment: const <String, String>{},
        transport: transport,
      );

      expect(jsonDecode(sessionError.stdout), {
        'status': 'ok',
        'writtenMessage': {
          'id': 'message-1',
          'role': 'system',
          'text': 'Session setup failed.',
        },
        'message': null,
        'nextStep': 'No further polling was requested.',
      });
      expect(jsonDecode(correlatedError.stdout), {
        'status': 'ok',
        'writtenMessage': {
          'id': 'message-3',
          'role': 'system',
          'text': 'Could not run tests.',
          'replyToMessageId': 'message-2',
        },
        'message': null,
        'nextStep': 'No further polling was requested.',
      });
      expect(transport.errorRequests, [
        (
          baseUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
          replyToMessageId: null,
          text: 'Session setup failed.',
        ),
        (
          baseUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
          replyToMessageId: 'message-2',
          text: 'Could not run tests.',
        ),
      ]);
      expect(transport.requests, isEmpty);
    });

    test('validates agent error once arguments before polling', () async {
      final FakeAgentCommandTransport invalidReplyTransport =
          FakeAgentCommandTransport(
        errorError: const AgentCommandException('invalid_reply_to_message'),
      );
      final FakeAgentCommandTransport localValidationTransport =
          FakeAgentCommandTransport();

      Future<AgentCommandResult> runError(
        List<String> extraArgs, {
        FakeAgentCommandTransport? transport,
      }) {
        return runAgentSessionCommand(
          [
            'agent',
            'poll',
            '--base-url',
            'http://127.0.0.1:8787',
            '--session-id',
            'session-1',
            ...extraArgs,
          ],
          environment: const <String, String>{},
          transport: transport ?? localValidationTransport,
        );
      }

      final AgentCommandResult emptyError = await runError(
        const ['--agent-error', '  ', '--once'],
      );
      final AgentCommandResult longError = await runError([
        '--agent-error',
        List<String>.filled(4001, 'x').join(),
        '--once',
      ]);
      final AgentCommandResult invalidReplyTo = await runError(
        const [
          '--reply-to',
          'message-404',
          '--agent-error',
          'Could not run tests.',
          '--once',
        ],
        transport: invalidReplyTransport,
      );

      expect(jsonDecode(emptyError.stderr), {
        'status': 'error',
        'error': 'empty_chat_message',
      });
      expect(jsonDecode(longError.stderr), {
        'status': 'error',
        'error': 'chat_message_too_long',
      });
      expect(jsonDecode(invalidReplyTo.stderr), {
        'status': 'error',
        'error': 'invalid_reply_to_message',
      });
      expect(localValidationTransport.requests, isEmpty);
      expect(localValidationTransport.errorRequests, isEmpty);
      expect(invalidReplyTransport.requests, isEmpty);
      expect(invalidReplyTransport.errorRequests.single.replyToMessageId,
          'message-404');
    });

    test('continues polling after writing an agent reply by default', () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport(
        replyResponse: {
          'status': 'ok',
          'message': {
            'id': 'message-2',
            'role': 'agent',
            'text': 'Done.',
            'replyToMessageId': 'message-1',
          },
        },
        pollResponse: {
          'status': 'ok',
          'message': {
            'id': 'message-3',
            'role': 'user',
            'text': 'Now update the empty state.',
          },
        },
      );

      final AgentCommandResult result = await runAgentSessionCommand(
        const [
          'agent',
          'poll',
          '--base-url',
          'http://127.0.0.1:8787',
          '--session-id',
          'session-1',
          '--reply-to',
          'message-1',
          '--agent-reply',
          'Done.',
        ],
        environment: const <String, String>{},
        transport: transport,
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(jsonDecode(result.stdout), {
        'status': 'ok',
        'writtenMessage': {
          'id': 'message-2',
          'role': 'agent',
          'text': 'Done.',
          'replyToMessageId': 'message-1',
        },
        'message': {
          'id': 'message-3',
          'role': 'user',
          'text': 'Now update the empty state.',
        },
        'nextStep': 'Process message-3, then reply with --reply-to message-3 '
            'and either --agent-reply or --agent-error.',
      });
      expect(transport.replyRequests, [
        (
          baseUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
          replyToMessageId: 'message-1',
          text: 'Done.',
        ),
      ]);
      expect(transport.requests, [
        (
          baseUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
        ),
      ]);
    });

    test('continues polling after writing agent errors by default', () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport(
        errorResponses: <Map<String, Object?>>[
          {
            'status': 'ok',
            'message': {
              'id': 'message-2',
              'role': 'system',
              'text': 'Could not run tests.',
              'replyToMessageId': 'message-1',
            },
          },
        ],
        pollResponse: {
          'status': 'ok',
          'message': {
            'id': 'message-3',
            'role': 'user',
            'text': 'Try a smaller fix.',
          },
        },
      );

      final AgentCommandResult result = await runAgentSessionCommand(
        const [
          'agent',
          'poll',
          '--base-url',
          'http://127.0.0.1:8787',
          '--session-id',
          'session-1',
          '--reply-to',
          'message-1',
          '--agent-error',
          'Could not run tests.',
        ],
        environment: const <String, String>{},
        transport: transport,
      );

      expect(result.exitCode, 0);
      expect(jsonDecode(result.stdout), {
        'status': 'ok',
        'writtenMessage': {
          'id': 'message-2',
          'role': 'system',
          'text': 'Could not run tests.',
          'replyToMessageId': 'message-1',
        },
        'message': {
          'id': 'message-3',
          'role': 'user',
          'text': 'Try a smaller fix.',
        },
        'nextStep': 'Process message-3, then reply with --reply-to message-3 '
            'and either --agent-reply or --agent-error.',
      });
      expect(transport.errorRequests.single.replyToMessageId, 'message-1');
      expect(transport.requests, [
        (
          baseUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
        ),
      ]);
    });

    test('reports partial success when continuation polling fails', () async {
      final FakeAgentCommandTransport replyTransport =
          FakeAgentCommandTransport(
        replyResponse: {
          'status': 'ok',
          'message': {
            'id': 'message-2',
            'role': 'agent',
            'text': 'Done.',
            'replyToMessageId': 'message-1',
          },
        },
        pollError: const AgentCommandException('agent_poll_already_active'),
      );
      final FakeAgentCommandTransport errorTransport =
          FakeAgentCommandTransport(
        errorResponses: <Map<String, Object?>>[
          {
            'status': 'ok',
            'message': {
              'id': 'message-3',
              'role': 'system',
              'text': 'Could not run tests.',
            },
          },
        ],
        pollError: const AgentCommandException('bridge_request_failed'),
      );

      final AgentCommandResult replyFailure = await runAgentSessionCommand(
        const [
          'agent',
          'poll',
          '--base-url',
          'http://127.0.0.1:8787',
          '--session-id',
          'session-1',
          '--reply-to',
          'message-1',
          '--agent-reply',
          'Done.',
        ],
        environment: const <String, String>{},
        transport: replyTransport,
      );
      final AgentCommandResult errorFailure = await runAgentSessionCommand(
        const [
          'agent',
          'poll',
          '--base-url',
          'http://127.0.0.1:8787',
          '--session-id',
          'session-1',
          '--agent-error',
          'Could not run tests.',
        ],
        environment: const <String, String>{},
        transport: errorTransport,
      );

      expect(replyFailure.exitCode, 1);
      expect(replyFailure.stdout, isEmpty);
      expect(jsonDecode(replyFailure.stderr), {
        'status': 'error',
        'error': 'poll_continuation_failed',
        'cause': 'agent_poll_already_active',
        'writtenMessage': {
          'id': 'message-2',
          'role': 'agent',
          'text': 'Done.',
          'replyToMessageId': 'message-1',
        },
        'nextStep':
            'Do not retry the written message; restart polling for the next Chat message.',
      });
      expect(errorFailure.exitCode, 1);
      expect(errorFailure.stdout, isEmpty);
      expect(jsonDecode(errorFailure.stderr), {
        'status': 'error',
        'error': 'poll_continuation_failed',
        'cause': 'bridge_request_failed',
        'writtenMessage': {
          'id': 'message-3',
          'role': 'system',
          'text': 'Could not run tests.',
        },
        'nextStep':
            'Do not retry the written message; restart polling for the next Chat message.',
      });
      expect(replyTransport.replyRequests, hasLength(1));
      expect(replyTransport.requests, hasLength(1));
      expect(errorTransport.errorRequests, hasLength(1));
      expect(errorTransport.requests, hasLength(1));
    });

    test('HTTP command continuation waits with Agent ready status', () async {
      final BridgeServerFixture fixture = BridgeServerFixture();
      await fixture.start();
      addTearDown(fixture.close);
      final HttpClient browserClient = HttpClient();
      final HttpClient agentClient = HttpClient();
      addTearDown(browserClient.close);
      addTearDown(agentClient.close);
      final String sessionId = await createSession(
        browserClient,
        fixture.baseUri,
      );

      final initialPollRequest = await agentClient.getUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/agent/poll'),
      );
      final Future<HttpClientResponse> initialPollResponseFuture =
          initialPollRequest.close();
      await waitForChatStatus(
        browserClient,
        fixture.baseUri,
        sessionId,
        'agent_ready',
      );

      final firstSendRequest = await browserClient.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      firstSendRequest.headers.contentType = ContentType.json;
      firstSendRequest.write(jsonEncode({'text': 'Make this button primary.'}));
      await (await firstSendRequest.close()).drain<void>();
      await (await initialPollResponseFuture).drain<void>();

      final Future<AgentCommandResult> commandFuture = runAgentSessionCommand(
        [
          'agent',
          'poll',
          '--base-url',
          fixture.baseUri.toString(),
          '--session-id',
          sessionId,
          '--reply-to',
          'message-1',
          '--agent-reply',
          'Done.',
        ],
        environment: const <String, String>{},
        transport: AgentHttpCommandTransport(),
      );
      await waitForChatStatus(
        browserClient,
        fixture.baseUri,
        sessionId,
        'agent_ready',
      );

      final secondSendRequest = await browserClient.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/chat/messages'),
      );
      secondSendRequest.headers.contentType = ContentType.json;
      secondSendRequest
          .write(jsonEncode({'text': 'Now update the empty state.'}));
      await (await secondSendRequest.close()).drain<void>();

      final AgentCommandResult result = await commandFuture;

      expect(result.exitCode, 0);
      expect(jsonDecode(result.stdout), {
        'status': 'ok',
        'writtenMessage': {
          'id': 'message-2',
          'role': 'agent',
          'text': 'Done.',
          'replyToMessageId': 'message-1',
        },
        'message': {
          'id': 'message-3',
          'role': 'user',
          'text': 'Now update the empty state.',
        },
        'nextStep': 'Process message-3, then reply with --reply-to message-3 '
            'and either --agent-reply or --agent-error.',
      });
      expect(
        await readChatStatus(browserClient, fixture.baseUri, sessionId),
        'agent_working',
      );
    });

    test('exposes the final supported error-code vocabulary', () {
      expect(supportedAgentCommandErrorCodes, {
        'missing_bridge_url',
        'missing_session_id',
        'invalid_arguments',
        'invalid_reply_to_message',
        'empty_chat_message',
        'chat_message_too_long',
        'session_not_found',
        'agent_poll_already_active',
        'bridge_request_failed',
        'poll_continuation_failed',
      });
    });

    test('normalizes unsupported bridge error codes to bridge_request_failed',
        () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport(
        pollError: const AgentCommandException('unexpected_bridge_error'),
      );

      final AgentCommandResult result = await runAgentSessionCommand(
        const ['agent', 'poll', '--once'],
        environment: const {
          'ASK_UI_BRIDGE_URL': 'http://127.0.0.1:8787',
          'ASK_UI_SESSION_ID': 'session-1',
        },
        transport: transport,
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'bridge_request_failed',
      });
    });

    test('rejects unsupported output and stdin flags with JSON only', () async {
      final FakeAgentCommandTransport transport = FakeAgentCommandTransport();
      final List<List<String>> unsupportedArgs = <List<String>>[
        const ['agent', 'poll', '--json'],
        const ['agent', 'poll', '--timeout', '1'],
        const ['agent', 'poll', '--stdin'],
        const ['agent', 'poll', '--agent-reply-stdin'],
        const ['agent', 'poll', '--unknown'],
      ];

      for (final List<String> args in unsupportedArgs) {
        final AgentCommandResult result = await runAgentSessionCommand(
          args,
          environment: const {
            'ASK_UI_BRIDGE_URL': 'http://127.0.0.1:8787',
            'ASK_UI_SESSION_ID': 'session-1',
          },
          transport: transport,
        );

        expect(result.exitCode, 1, reason: args.join(' '));
        expect(result.stdout, isEmpty, reason: args.join(' '));
        expect(
            jsonDecode(result.stderr),
            {
              'status': 'error',
              'error': 'invalid_arguments',
            },
            reason: args.join(' '));
      }
      expect(transport.requests, isEmpty);
    });

    test('product UI source does not expose command terminology', () {
      final Directory webSource = Directory('../../apps/web/src');
      final RegExp forbiddenTerms = RegExp(
        r'\b(Agent Session Command|agent command|agent poll|poller|transport|--agent-reply|--agent-error|--reply-to)\b',
        caseSensitive: false,
      );
      final List<String> leaks = <String>[];

      for (final FileSystemEntity entity
          in webSource.listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        if (!entity.path.endsWith('.ts') && !entity.path.endsWith('.tsx')) {
          continue;
        }
        if (entity.path.endsWith('.test.ts') ||
            entity.path.endsWith('.test.tsx')) {
          continue;
        }

        final String contents = entity.readAsStringSync();
        if (forbiddenTerms.hasMatch(contents)) {
          leaks.add(entity.path);
        }
      }

      expect(leaks, isEmpty);
    });
  });
}

class FakeAgentCommandTransport implements AgentCommandTransport {
  FakeAgentCommandTransport({
    this.pollResponse,
    this.pollError,
    this.replyResponse,
    this.replyError,
    this.errorResponses = const <Map<String, Object?>>[],
    this.errorError,
  });

  final Map<String, Object?>? pollResponse;
  final AgentCommandException? pollError;
  final Map<String, Object?>? replyResponse;
  final AgentCommandException? replyError;
  final List<Map<String, Object?>> errorResponses;
  final AgentCommandException? errorError;
  final List<({Uri baseUrl, String sessionId})> requests =
      <({Uri baseUrl, String sessionId})>[];
  final List<
      ({
        Uri baseUrl,
        String sessionId,
        String replyToMessageId,
        String text,
      })> replyRequests = <({
    Uri baseUrl,
    String sessionId,
    String replyToMessageId,
    String text,
  })>[];
  final List<
      ({
        Uri baseUrl,
        String sessionId,
        String? replyToMessageId,
        String text,
      })> errorRequests = <({
    Uri baseUrl,
    String sessionId,
    String? replyToMessageId,
    String text,
  })>[];

  @override
  Future<Map<String, Object?>> poll({
    required Uri baseUrl,
    required String sessionId,
  }) async {
    requests.add((baseUrl: baseUrl, sessionId: sessionId));
    final AgentCommandException? error = pollError;
    if (error != null) {
      throw error;
    }

    return pollResponse ?? const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> writeAgentReply({
    required Uri baseUrl,
    required String sessionId,
    required String replyToMessageId,
    required String text,
  }) async {
    replyRequests.add((
      baseUrl: baseUrl,
      sessionId: sessionId,
      replyToMessageId: replyToMessageId,
      text: text,
    ));
    final AgentCommandException? error = replyError;
    if (error != null) {
      throw error;
    }

    return replyResponse ?? const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> writeAgentError({
    required Uri baseUrl,
    required String sessionId,
    required String? replyToMessageId,
    required String text,
  }) async {
    errorRequests.add((
      baseUrl: baseUrl,
      sessionId: sessionId,
      replyToMessageId: replyToMessageId,
      text: text,
    ));
    final AgentCommandException? error = errorError;
    if (error != null) {
      throw error;
    }

    return errorResponses[errorRequests.length - 1];
  }
}
