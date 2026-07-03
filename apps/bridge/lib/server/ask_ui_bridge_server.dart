import 'dart:convert';
import 'dart:io';

import '../sessions/session_store.dart';

class AskUiBridgeServer {
  AskUiBridgeServer({required SessionStore sessionStore})
      : _sessionStore = sessionStore;

  final SessionStore _sessionStore;
  HttpServer? _server;

  Future<int> start({required String host, required int port}) async {
    final server = await HttpServer.bind(host, port);
    _server = server;
    server.listen(_handleRequest);
    return server.port;
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _setCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/api/sessions') {
      await _createSession(request);
      return;
    }

    await _writeJson(
      request.response,
      statusCode: HttpStatus.notFound,
      body: {'error': 'not_found'},
    );
  }

  Future<void> _createSession(HttpRequest request) async {
    Map<String, Object?> body;

    try {
      final rawBody = await utf8.decodeStream(request);
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Expected JSON object');
      }
      body = decoded;
    } on FormatException {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'invalid_json'},
      );
      return;
    }

    final vmServiceUri = body['vmServiceUri'];
    final projectRoot = body['projectRoot'];

    if (vmServiceUri is! String || projectRoot is! String) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'missing_session_parameters'},
      );
      return;
    }

    try {
      final session = _sessionStore.createSession(
        vmServiceUri: vmServiceUri,
        projectRoot: projectRoot,
      );
      await _writeJson(
        request.response,
        body: {'sessionId': session.id},
      );
    } on InvalidSessionRequest {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'missing_session_parameters'},
      );
    }
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers
      ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
      ..set(HttpHeaders.accessControlAllowMethodsHeader, 'POST, GET, OPTIONS')
      ..set(HttpHeaders.accessControlAllowHeadersHeader, 'content-type');
  }

  Future<void> _writeJson(
    HttpResponse response, {
    int statusCode = HttpStatus.ok,
    required Map<String, Object?> body,
  }) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
