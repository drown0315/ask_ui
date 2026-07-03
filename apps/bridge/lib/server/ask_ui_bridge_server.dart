import 'dart:convert';
import 'dart:io';

import '../app_controller/flutter_app_controller.dart';
import '../inspector/flutter_inspector_client.dart';
import '../sessions/session_store.dart';

class AskUiBridgeServer {
  AskUiBridgeServer({
    required SessionStore sessionStore,
    required FlutterInspectorClient inspectorClient,
    required FlutterAppController appController,
  })  : _sessionStore = sessionStore,
        _inspectorClient = inspectorClient,
        _appController = appController;

  final SessionStore _sessionStore;
  final FlutterInspectorClient _inspectorClient;
  final FlutterAppController _appController;
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

    if (request.method == 'GET' &&
        request.uri.pathSegments.length == 4 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'widget-tree') {
      await _getWidgetTree(request);
      return;
    }

    if (request.method == 'POST' &&
        request.uri.pathSegments.length == 4 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'hot-reload') {
      await _hotReload(request);
      return;
    }

    if (request.method == 'POST' &&
        request.uri.pathSegments.length == 4 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'hot-restart') {
      await _hotRestart(request);
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

  Future<void> _getWidgetTree(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    try {
      final root = await _inspectorClient.fetchRootWidgetTree(session);
      await _writeJson(
        request.response,
        body: {'root': root.toJson()},
      );
    } catch (error) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badGateway,
        body: {
          'error': 'widget_tree_fetch_failed',
          'message': error.toString(),
        },
      );
    }
  }

  Future<void> _hotReload(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    try {
      final result = await _appController.hotReload(session);
      await _writeJson(
        request.response,
        body: result.toJson(),
      );
    } catch (error) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badGateway,
        body: {
          'error': 'hot_reload_failed',
          'message': error.toString(),
        },
      );
    }
  }

  Future<void> _hotRestart(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    await _writeJson(
      request.response,
      statusCode: HttpStatus.notImplemented,
      body: {
        'error': 'hot_restart_not_supported_for_session',
        'message': 'Hot restart is not available for this bridge session.',
      },
    );
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
