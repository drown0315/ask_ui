import 'dart:convert';
import 'dart:io';

const int _chatMessageTextLimit = 4000;

/// Result returned by the Agent Session Command runner.
///
/// Tests use this object directly, while the binary maps it to stdout, stderr,
/// and the process exit code.
class AgentCommandResult {
  const AgentCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Transport boundary for Agent Session Command bridge requests.
abstract interface class AgentCommandTransport {
  Future<Map<String, Object?>> poll({
    required Uri baseUrl,
    required String sessionId,
  });

  Future<Map<String, Object?>> writeAgentReply({
    required Uri baseUrl,
    required String sessionId,
    required String replyToMessageId,
    required String text,
  });

  Future<Map<String, Object?>> writeAgentError({
    required Uri baseUrl,
    required String sessionId,
    required String? replyToMessageId,
    required String text,
  });
}

/// Normalized bridge transport failure for command output.
class AgentCommandException implements Exception {
  const AgentCommandException(this.code);

  final String code;
}

/// HTTP transport for the Agent Session Command bridge endpoints.
class AgentHttpCommandTransport implements AgentCommandTransport {
  AgentHttpCommandTransport({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  @override
  Future<Map<String, Object?>> poll({
    required Uri baseUrl,
    required String sessionId,
  }) async {
    final Uri pollUri = baseUrl.resolve(
      '/api/sessions/$sessionId/agent/poll',
    );

    try {
      final HttpClientRequest request = await _httpClient.getUrl(pollUri);
      final HttpClientResponse response = await request.close();
      final String responseBody = await utf8.decodeStream(response);
      final Map<String, Object?> decoded = _decodeJsonObject(responseBody);

      if (response.statusCode != HttpStatus.ok) {
        final Object? error = decoded['error'];
        throw AgentCommandException(
          error is String ? error : 'bridge_request_failed',
        );
      }

      return decoded;
    } on AgentCommandException {
      rethrow;
    } catch (_) {
      throw const AgentCommandException('bridge_request_failed');
    }
  }

  @override
  Future<Map<String, Object?>> writeAgentReply({
    required Uri baseUrl,
    required String sessionId,
    required String replyToMessageId,
    required String text,
  }) async {
    final Uri replyUri = baseUrl.resolve(
      '/api/sessions/$sessionId/agent/reply',
    );
    return _postAgentMessage(
      replyUri,
      {
        'text': text,
        'replyToMessageId': replyToMessageId,
      },
    );
  }

  @override
  Future<Map<String, Object?>> writeAgentError({
    required Uri baseUrl,
    required String sessionId,
    required String? replyToMessageId,
    required String text,
  }) async {
    final Uri errorUri = baseUrl.resolve(
      '/api/sessions/$sessionId/agent/error',
    );
    return _postAgentMessage(
      errorUri,
      {
        'text': text,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      },
    );
  }

  Map<String, Object?> _decodeJsonObject(String responseBody) {
    final Object? decoded = jsonDecode(responseBody.trim());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected JSON object');
    }

    return decoded;
  }

  Future<Map<String, Object?>> _postAgentMessage(
    Uri uri,
    Map<String, Object?> body,
  ) async {
    try {
      final HttpClientRequest request = await _httpClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final HttpClientResponse response = await request.close();
      final String responseBody = await utf8.decodeStream(response);
      final Map<String, Object?> decoded = _decodeJsonObject(responseBody);

      if (response.statusCode != HttpStatus.ok) {
        final Object? error = decoded['error'];
        throw AgentCommandException(
          error is String ? error : 'bridge_request_failed',
        );
      }

      return decoded;
    } on AgentCommandException {
      rethrow;
    } catch (_) {
      throw const AgentCommandException('bridge_request_failed');
    }
  }
}

/// Parses and runs the agent-facing command contract.
Future<AgentCommandResult> runAgentSessionCommand(
  List<String> args, {
  required Map<String, String> environment,
  required AgentCommandTransport transport,
}) async {
  late final _AgentPollRequest request;
  try {
    request = _AgentPollRequest.parse(args, environment);
  } on _CommandValidationError catch (error) {
    return _CommandOutput.failure(error.code);
  }

  if (request.agentReplyText != null) {
    late final Map<String, Object?> replyResponse;
    try {
      replyResponse = await transport.writeAgentReply(
        baseUrl: request.baseUrl,
        sessionId: request.sessionId,
        replyToMessageId: request.replyToMessageId!,
        text: request.agentReplyText!,
      );
    } on AgentCommandException catch (error) {
      return _CommandOutput.failure(error.code);
    }

    return _finishWrite(
      request: request,
      transport: transport,
      writtenMessage: replyResponse['message'],
    );
  }

  if (request.agentErrorText != null) {
    late final Map<String, Object?> errorResponse;
    try {
      errorResponse = await transport.writeAgentError(
        baseUrl: request.baseUrl,
        sessionId: request.sessionId,
        replyToMessageId: request.replyToMessageId,
        text: request.agentErrorText!,
      );
    } on AgentCommandException catch (error) {
      return _CommandOutput.failure(error.code);
    }

    return _finishWrite(
      request: request,
      transport: transport,
      writtenMessage: errorResponse['message'],
    );
  }

  try {
    return await _pollSuccess(request: request, transport: transport);
  } on AgentCommandException catch (error) {
    return _CommandOutput.failure(error.code);
  }
}

Future<AgentCommandResult> _finishWrite({
  required _AgentPollRequest request,
  required AgentCommandTransport transport,
  required Object? writtenMessage,
}) async {
  if (request.once) {
    return _CommandOutput.success({
      'status': 'ok',
      'writtenMessage': writtenMessage,
      'message': null,
      'nextStep': _NextStep.writeOnceSuccess(),
    });
  }

  return _pollAfterWrite(
    request: request,
    transport: transport,
    writtenMessage: writtenMessage,
  );
}

Future<AgentCommandResult> _pollSuccess({
  required _AgentPollRequest request,
  required AgentCommandTransport transport,
  Object? writtenMessage,
}) async {
  late final Map<String, Object?> response;
  response = await transport.poll(
    baseUrl: request.baseUrl,
    sessionId: request.sessionId,
  );

  final Object? message = response['message'];
  final String? messageId =
      message is Map<String, Object?> && message['id'] is String
          ? message['id'] as String
          : null;

  return _CommandOutput.success({
    'status': 'ok',
    if (writtenMessage != null) 'writtenMessage': writtenMessage,
    'message': message,
    'nextStep': _NextStep.pollSuccess(messageId),
  });
}

Future<AgentCommandResult> _pollAfterWrite({
  required _AgentPollRequest request,
  required AgentCommandTransport transport,
  required Object? writtenMessage,
}) async {
  try {
    return await _pollSuccess(
      request: request,
      transport: transport,
      writtenMessage: writtenMessage,
    );
  } on AgentCommandException catch (error) {
    return _CommandOutput.pollContinuationFailure(
      cause: error.code,
      writtenMessage: writtenMessage,
    );
  }
}

class _AgentPollRequest {
  const _AgentPollRequest({
    required this.baseUrl,
    required this.sessionId,
    this.replyToMessageId,
    this.agentReplyText,
    this.agentErrorText,
    this.once = false,
  });

  final Uri baseUrl;
  final String sessionId;
  final String? replyToMessageId;
  final String? agentReplyText;
  final String? agentErrorText;
  final bool once;

  static _AgentPollRequest parse(
    List<String> args,
    Map<String, String> environment,
  ) {
    if (args.length < 2 || args[0] != 'agent' || args[1] != 'poll') {
      throw const _CommandValidationError('invalid_arguments');
    }

    String? baseUrl;
    String? sessionId;
    String? replyToMessageId;
    String? agentReplyText;
    String? agentErrorText;
    bool once = false;

    for (var index = 2; index < args.length; index += 1) {
      final String arg = args[index];
      if (arg == '--base-url' && index + 1 < args.length) {
        index += 1;
        baseUrl = args[index];
      } else if (arg == '--session-id' && index + 1 < args.length) {
        index += 1;
        sessionId = args[index];
      } else if (arg == '--reply-to' && index + 1 < args.length) {
        index += 1;
        replyToMessageId = args[index];
      } else if (arg == '--agent-reply' && index + 1 < args.length) {
        index += 1;
        agentReplyText = args[index];
      } else if (arg == '--agent-error' && index + 1 < args.length) {
        index += 1;
        agentErrorText = args[index];
      } else if (arg == '--once') {
        once = true;
      } else {
        throw const _CommandValidationError('invalid_arguments');
      }
    }

    final String? resolvedBaseUrl = baseUrl ?? environment['ASK_UI_BRIDGE_URL'];
    if (resolvedBaseUrl == null || resolvedBaseUrl.isEmpty) {
      throw const _CommandValidationError('missing_bridge_url');
    }

    final String? resolvedSessionId =
        sessionId ?? environment['ASK_UI_SESSION_ID'];
    if (resolvedSessionId == null || resolvedSessionId.isEmpty) {
      throw const _CommandValidationError('missing_session_id');
    }

    if (agentReplyText != null && agentErrorText != null) {
      throw const _CommandValidationError('invalid_arguments');
    }

    if (agentReplyText != null) {
      if (replyToMessageId == null || replyToMessageId.isEmpty) {
        throw const _CommandValidationError('invalid_reply_to_message');
      }

      if (agentReplyText.trim().isEmpty) {
        throw const _CommandValidationError('empty_chat_message');
      }

      if (agentReplyText.length > _chatMessageTextLimit) {
        throw const _CommandValidationError('chat_message_too_long');
      }
    } else if (agentErrorText != null) {
      if (agentErrorText.trim().isEmpty) {
        throw const _CommandValidationError('empty_chat_message');
      }

      if (agentErrorText.length > _chatMessageTextLimit) {
        throw const _CommandValidationError('chat_message_too_long');
      }
    } else if (replyToMessageId != null) {
      throw const _CommandValidationError('invalid_arguments');
    }

    return _AgentPollRequest(
      baseUrl: Uri.parse(resolvedBaseUrl),
      sessionId: resolvedSessionId,
      replyToMessageId: replyToMessageId,
      agentReplyText: agentReplyText,
      agentErrorText: agentErrorText,
      once: once,
    );
  }
}

class _CommandValidationError implements Exception {
  const _CommandValidationError(this.code);

  final String code;
}

class _CommandOutput {
  _CommandOutput._();

  static AgentCommandResult success(Map<String, Object?> body) {
    return AgentCommandResult(exitCode: 0, stdout: jsonEncode(body));
  }

  static AgentCommandResult failure(String code) {
    return AgentCommandResult(
      exitCode: 1,
      stderr: jsonEncode({
        'status': 'error',
        'error': code,
      }),
    );
  }

  static AgentCommandResult pollContinuationFailure({
    required String cause,
    required Object? writtenMessage,
  }) {
    return AgentCommandResult(
      exitCode: 1,
      stderr: jsonEncode({
        'status': 'error',
        'error': 'poll_continuation_failed',
        'cause': cause,
        'writtenMessage': writtenMessage,
        'nextStep': _NextStep.pollContinuationFailure(),
      }),
    );
  }
}

class _NextStep {
  _NextStep._();

  static String pollSuccess(String? messageId) {
    return 'Process $messageId, then reply with --reply-to $messageId and either --agent-reply or --agent-error.';
  }

  static String writeOnceSuccess() {
    return 'No further polling was requested.';
  }

  static String pollContinuationFailure() {
    return 'Do not retry the written message; restart polling for the next Chat message.';
  }
}
