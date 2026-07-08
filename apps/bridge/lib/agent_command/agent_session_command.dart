import 'dart:convert';
import 'dart:io';

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

  Map<String, Object?> _decodeJsonObject(String responseBody) {
    final Object? decoded = jsonDecode(responseBody.trim());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected JSON object');
    }

    return decoded;
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

  late final Map<String, Object?> response;
  try {
    response = await transport.poll(
      baseUrl: request.baseUrl,
      sessionId: request.sessionId,
    );
  } on AgentCommandException catch (error) {
    return _CommandOutput.failure(error.code);
  }

  final Object? message = response['message'];
  final String? messageId =
      message is Map<String, Object?> && message['id'] is String
          ? message['id'] as String
          : null;

  return _CommandOutput.success({
    'status': 'ok',
    'message': message,
    'nextStep': _NextStep.pollSuccess(messageId),
  });
}

class _AgentPollRequest {
  const _AgentPollRequest({
    required this.baseUrl,
    required this.sessionId,
  });

  final Uri baseUrl;
  final String sessionId;

  static _AgentPollRequest parse(
    List<String> args,
    Map<String, String> environment,
  ) {
    if (args.length < 2 || args[0] != 'agent' || args[1] != 'poll') {
      throw const _CommandValidationError('invalid_arguments');
    }

    String? baseUrl;
    String? sessionId;

    for (var index = 2; index < args.length; index += 1) {
      final String arg = args[index];
      if (arg == '--base-url' && index + 1 < args.length) {
        index += 1;
        baseUrl = args[index];
      } else if (arg == '--session-id' && index + 1 < args.length) {
        index += 1;
        sessionId = args[index];
      } else if (arg == '--once') {
        continue;
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

    return _AgentPollRequest(
      baseUrl: Uri.parse(resolvedBaseUrl),
      sessionId: resolvedSessionId,
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
}

class _NextStep {
  _NextStep._();

  static String pollSuccess(String? messageId) {
    return 'Process $messageId, then reply with --reply-to $messageId and either --agent-reply or --agent-error.';
  }
}
