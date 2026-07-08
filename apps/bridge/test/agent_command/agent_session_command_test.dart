import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/agent_command/agent_session_command.dart';
import 'package:test/test.dart';

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
        Uri.parse('/api/sessions/conflict/agent/poll'),
      ]);
      expect(requestBodies, [
        {'text': 'Done.', 'replyToMessageId': 'message-1'},
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
  });
}

class FakeAgentCommandTransport implements AgentCommandTransport {
  FakeAgentCommandTransport({
    this.pollResponse,
    this.pollError,
    this.replyResponse,
    this.replyError,
  });

  final Map<String, Object?>? pollResponse;
  final AgentCommandException? pollError;
  final Map<String, Object?>? replyResponse;
  final AgentCommandException? replyError;
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
}
