import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_controller/flutter_app_controller.dart';
import '../device_control/device_control_protocol.dart';
import '../inspector/flutter_inspector_client.dart';
import '../logging/bridge_logger.dart';
import '../sessions/flutter_device_checker.dart';
import '../sessions/session_store.dart';

class AskUiBridgeServer {
  AskUiBridgeServer({
    required SessionStore sessionStore,
    required FlutterInspectorClient inspectorClient,
    required FlutterAppController appController,
    FlutterDeviceChecker? flutterDeviceChecker,
    BridgeLogger? logger,
  })  : _sessionStore = sessionStore,
        _inspectorClient = inspectorClient,
        _appController = appController,
        _flutterDeviceChecker =
            flutterDeviceChecker ?? const FlutterDevicesCommandChecker(),
        _logger = logger ?? BridgeLogger(write: print);

  final SessionStore _sessionStore;
  final FlutterInspectorClient _inspectorClient;
  final FlutterAppController _appController;
  final FlutterDeviceChecker _flutterDeviceChecker;
  final BridgeLogger _logger;
  final Set<String> _activeDeviceSessionIds = {};
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
        request.uri.pathSegments[3] == 'device') {
      await _openDevice(request);
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
        request.uri.pathSegments[3] == 'select-widget-mode') {
      await _setSelectWidgetMode(request);
      return;
    }

    if (request.method == 'POST' &&
        request.uri.pathSegments.length == 4 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'widget-selection') {
      await _selectWidgetById(request);
      return;
    }

    if (request.method == 'GET' &&
        request.uri.pathSegments.length == 4 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'events') {
      await _streamSessionEvents(request);
      return;
    }

    if (request.method == 'GET' &&
        request.uri.pathSegments.length == 4 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'select-widget-mode') {
      await _getSelectWidgetMode(request);
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
    _logger.info('session create start');
    Map<String, Object?> body;

    try {
      final rawBody = await utf8.decodeStream(request);
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Expected JSON object');
      }
      body = decoded;
    } on FormatException {
      _logger.info('session create failed error=invalid_json');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'invalid_json'},
      );
      return;
    }

    final vmServiceUri = body['vmServiceUri'];
    final projectRoot = body['projectRoot'];
    final deviceId = body['deviceId'];

    if (vmServiceUri is! String ||
        projectRoot is! String ||
        deviceId is! String) {
      _logger.info('session create failed error=missing_session_parameters');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'missing_session_parameters'},
      );
      return;
    }

    if (vmServiceUri.trim().isEmpty ||
        projectRoot.trim().isEmpty ||
        deviceId.trim().isEmpty) {
      _logger.info('session create failed error=missing_session_parameters');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'missing_session_parameters'},
      );
      return;
    }

    late final FlutterDeviceAvailability targetDeviceAvailability;
    try {
      targetDeviceAvailability = await _flutterDeviceChecker.checkDeviceId(
        deviceId,
      );
    } catch (error, stackTrace) {
      _logger.info(
        'target_device_check_failed command="flutter devices --machine" '
        'deviceId=$deviceId error=$error\n'
        'Stack trace:\n$stackTrace',
      );
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'target_device_check_failed',
          'message': 'Ask UI could not check Flutter target devices.',
          'deviceId': deviceId,
        },
      );
      return;
    }

    if (targetDeviceAvailability == FlutterDeviceAvailability.notFound) {
      _logger.info(
        'session create failed error=target_device_not_found deviceId=$deviceId',
      );
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'target_device_not_found',
          'message': 'Target Device $deviceId is not listed by Flutter.',
          'deviceId': deviceId,
        },
      );
      return;
    }

    if (targetDeviceAvailability == FlutterDeviceAvailability.unavailable) {
      _logger.info(
        'session create failed error=target_device_unavailable deviceId=$deviceId',
      );
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'target_device_unavailable',
          'message': 'Target Device $deviceId is not available.',
          'deviceId': deviceId,
        },
      );
      return;
    }

    try {
      final session = _sessionStore.createSession(
        vmServiceUri: vmServiceUri,
        projectRoot: projectRoot,
        deviceId: deviceId,
      );
      await _writeJson(
        request.response,
        body: {'sessionId': session.id},
      );
      _logger.info(
        'session create success session=${session.id} deviceId=${session.deviceId}',
      );
    } on InvalidSessionRequest {
      _logger.info('session create failed error=missing_session_parameters');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'missing_session_parameters'},
      );
    } on DeviceMismatchForSession catch (error) {
      _logger.info(
        'session create failed error=device_mismatch_for_session '
        'expectedDeviceId=${error.expectedDeviceId} '
        'requestedDeviceId=${error.requestedDeviceId}',
      );
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'device_mismatch_for_session',
          'message': 'VM Service device does not match Target Device '
              '${error.requestedDeviceId}.',
          'expectedDeviceId': error.expectedDeviceId,
          'requestedDeviceId': error.requestedDeviceId,
        },
      );
    }
  }

  Future<void> _openDevice(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('device websocket session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    _logger.info('device websocket session=$sessionId open');
    if (_activeDeviceSessionIds.contains(sessionId)) {
      _logger.info('device websocket session=$sessionId already_active');
      socket.add(jsonEncode({
        'type': 'error',
        'error': 'device_already_active',
        'message': 'Device is already active for this bridge session.',
      }));
      await socket.close();
      return;
    }

    _activeDeviceSessionIds.add(sessionId);
    socket.listen(
      (message) {
        if (message is! String) {
          return;
        }

        final Map<String, Object?>? controlError =
            DeviceControlProtocol.validateTextMessage(message);
        if (controlError != null) {
          _logger.info(
            'device control session=$sessionId control_error '
            'error=${controlError['error']}',
          );
          socket.add(jsonEncode(controlError));
          return;
        }
        _logAcceptedDeviceControl(sessionId: sessionId, rawMessage: message);
      },
      onDone: () {
        _activeDeviceSessionIds.remove(sessionId);
        _logger.info('device websocket session=$sessionId close');
      },
      onError: (error) {
        _activeDeviceSessionIds.remove(sessionId);
        _logger.info('device websocket session=$sessionId error=$error');
      },
    );
    socket.add(jsonEncode({
      'type': 'ready',
      ..._buildDeviceMetadata(
        deviceId: session.deviceId,
        screenWidth: 1080,
        screenHeight: 2400,
      ),
    }));
    _logger.info(
      'device websocket session=$sessionId ready '
      'deviceId=${session.deviceId} screenWidth=1080 screenHeight=2400',
    );
    if (request.uri.queryParameters['debugMetadata'] == 'rotation') {
      socket.add(jsonEncode({
        'type': 'metadata',
        ..._buildDeviceMetadata(
          deviceId: session.deviceId,
          screenWidth: 2400,
          screenHeight: 1080,
        ),
      }));
      _logger.info(
        'device websocket session=$sessionId metadata '
        'deviceId=${session.deviceId} screenWidth=2400 screenHeight=1080',
      );
    }
  }

  void _logAcceptedDeviceControl({
    required String sessionId,
    required String rawMessage,
  }) {
    final decoded = jsonDecode(rawMessage);
    if (decoded is! Map<String, Object?>) {
      return;
    }

    if (decoded['type'] == DeviceControlProtocol.systemKeyType) {
      _logger.info(
        'device control session=$sessionId systemKey key=${decoded['key']}',
      );
      return;
    }

    if (decoded['type'] != DeviceControlProtocol.touchType) {
      return;
    }

    final action = decoded['action'];
    if (action == 'move') {
      return;
    }

    _logger.info(
      'device control session=$sessionId touch action=$action '
      'pointerId=${decoded['pointerId']} x=${decoded['x']} y=${decoded['y']}',
    );
  }

  Map<String, Object?> _buildDeviceMetadata({
    required String deviceId,
    required int screenWidth,
    required int screenHeight,
  }) {
    return {
      'deviceId': deviceId,
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
      'maxFps': 60,
      'videoCodec': 'h264',
      'controlReady': true,
    };
  }

  Future<void> _getWidgetTree(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('widget_tree request session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    _logger.info('widget_tree request session=$sessionId start');
    try {
      final root = await _inspectorClient.fetchRootWidgetTree(session);
      await _writeJson(
        request.response,
        body: {'root': root.toJson()},
      );
      _logger.info('widget_tree request session=$sessionId success');
    } catch (error) {
      _logger
          .info('widget_tree request session=$sessionId failed error=$error');
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
      _logger.info('hot_reload request session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    _logger.info('hot_reload request session=$sessionId start');
    try {
      final result = await _appController.hotReload(session);
      await _writeJson(
        request.response,
        body: result.toJson(),
      );
      _logger.info('hot_reload request session=$sessionId success');
    } catch (error) {
      _logger.info('hot_reload request session=$sessionId failed error=$error');
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

  Future<void> _setSelectWidgetMode(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger
          .info('select_widget request session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    late final bool enabled;
    try {
      final rawBody = await utf8.decodeStream(request);
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, Object?> || decoded['enabled'] is! bool) {
        throw const FormatException('Expected enabled boolean');
      }
      enabled = decoded['enabled']! as bool;
    } on FormatException {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'invalid_select_widget_mode_request'},
      );
      return;
    }

    _logger.info(
      'select_widget request session=$sessionId start enabled=$enabled',
    );
    try {
      final result = await _inspectorClient.setSelectWidgetMode(
        session,
        enabled: enabled,
      );
      await _writeJson(
        request.response,
        body: result.toJson(),
      );
      _logger.info(
        'select_widget request session=$sessionId success enabled=$enabled',
      );
    } catch (error) {
      _logger
          .info('select_widget request session=$sessionId failed error=$error');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badGateway,
        body: {
          'error': 'select_widget_mode_failed',
          'message': error.toString(),
        },
      );
    }
  }

  Future<void> _getSelectWidgetMode(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('select_widget status session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    _logger.info('select_widget status session=$sessionId start');
    try {
      final status = await _inspectorClient.getSelectWidgetModeStatus(session);
      await _writeJson(
        request.response,
        body: status.toJson(),
      );
      _logger.info(
        'select_widget status session=$sessionId success known=${status.enabled != null}',
      );
    } catch (error) {
      _logger
          .info('select_widget status session=$sessionId failed error=$error');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badGateway,
        body: {
          'error': 'select_widget_mode_status_failed',
          'message': error.toString(),
        },
      );
    }
  }

  /// Select one Flutter Inspector widget for the current bridge session.
  ///
  /// This method:
  /// 1. validates that the bridge session exists
  /// 2. parses a non-empty `widgetId` from the JSON request body
  /// 3. forwards the id to Flutter Inspector through `setSelectionById`
  /// 4. returns a stable JSON response for success or failure
  ///
  /// Args:
  /// - `request`: POST request whose path is
  ///   `/api/sessions/{sessionId}/widget-selection` and whose body contains
  ///   `{widgetId: string}`.
  ///
  /// Returns:
  /// `{status: ok, widgetId, message}` when Flutter Inspector accepts the id.
  /// Missing or empty ids return `invalid_widget_selection_request`.
  ///
  /// Example:
  /// Posting `{widgetId: inspector-2}` selects that object in Flutter
  /// Inspector for `session-1`.
  Future<void> _selectWidgetById(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info(
          'widget_selection request session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    late final String widgetId;
    try {
      final rawBody = await utf8.decodeStream(request);
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, Object?> ||
          decoded['widgetId'] is! String ||
          (decoded['widgetId']! as String).trim().isEmpty) {
        throw const FormatException('Expected non-empty widgetId string');
      }
      widgetId = (decoded['widgetId']! as String).trim();
    } on FormatException {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'invalid_widget_selection_request'},
      );
      return;
    }

    _logger.info(
      'widget_selection request session=$sessionId start widget=$widgetId',
    );
    try {
      final result = await _inspectorClient.selectWidgetById(
        session,
        widgetId: widgetId,
      );
      await _writeJson(
        request.response,
        body: result.toJson(),
      );
      _logger.info(
        'widget_selection request session=$sessionId success widget=$widgetId',
      );
    } catch (error) {
      _logger.info(
        'widget_selection request session=$sessionId failed error=$error',
      );
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badGateway,
        body: {
          'error': 'widget_selection_failed',
          'message': error.toString(),
        },
      );
    }
  }

  /// Stream bridge session events to one browser tab using Server-Sent Events.
  ///
  /// This method:
  /// 1. validates that the session exists
  /// 2. writes one Select Widget mode snapshot as the first SSE event
  /// 3. forwards later Select Widget mode changes observed by the Inspector
  ///    client
  /// 4. clears the subscription and heartbeat when the browser disconnects
  ///
  /// Args:
  /// - `request`: GET request whose path is
  ///   `/api/sessions/{sessionId}/events`. Unknown sessions receive a JSON
  ///   `session_not_found` response instead of an SSE stream.
  ///
  /// Returns:
  /// A long-lived `text/event-stream` response. The first event has
  /// `type=select_widget_mode_snapshot`; later updates use
  /// `type=select_widget_mode_changed`.
  ///
  /// Example:
  /// A browser subscribing to `session-1` first receives the cached state, then
  /// receives another event when DevTools toggles Select Widget mode.
  Future<void> _streamSessionEvents(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('events stream session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    SelectWidgetModeStatus snapshot;
    try {
      snapshot = await _inspectorClient.getSelectWidgetModeStatus(session);
    } catch (error) {
      _logger.info('events stream session=$sessionId failed error=$error');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badGateway,
        body: {
          'error': 'session_events_failed',
          'message': error.toString(),
        },
      );
      return;
    }

    _logger.info('events stream session=$sessionId open');
    request.response.statusCode = HttpStatus.ok;
    request.response.bufferOutput = false;
    request.response.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.transferEncodingHeader, 'chunked')
      ..set(HttpHeaders.connectionHeader, 'keep-alive');

    _writeSseEvent(
      request.response,
      event: 'bridge_session_event',
      data: {
        'type': 'select_widget_mode_snapshot',
        'sessionId': sessionId,
        'payload': {
          'known': snapshot.enabled != null,
          if (snapshot.enabled != null) 'enabled': snapshot.enabled,
        },
      },
    );
    await request.response.flush();

    final subscription =
        _inspectorClient.watchSelectWidgetModeStatus(session).listen((status) {
      _writeSseEvent(
        request.response,
        event: 'bridge_session_event',
        data: {
          'type': 'select_widget_mode_changed',
          'sessionId': sessionId,
          'payload': {
            if (status.enabled != null) 'enabled': status.enabled,
          },
        },
      );
      request.response.flush();
    });
    final heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      request.response.add(utf8.encode(': ping\n\n'));
      request.response.flush();
    });

    request.response.done.whenComplete(() {
      heartbeat.cancel();
      subscription.cancel();
      _logger.info('events stream session=$sessionId close');
    });
  }

  Future<void> _hotRestart(HttpRequest request) async {
    final sessionId = request.uri.pathSegments[2];
    final session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('hot_restart request session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    _logger.info('hot_restart request session=$sessionId start');
    try {
      final result = await _appController.hotRestart(session);
      await _writeJson(
        request.response,
        body: result.toJson(),
      );
      _logger.info('hot_restart request session=$sessionId success');
    } on HotRestartUnsupportedException catch (error) {
      _logger.info('hot_restart request session=$sessionId unsupported');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notImplemented,
        body: {
          'error': 'hot_restart_not_supported_for_session',
          'message': error.message,
        },
      );
    } catch (error) {
      _logger
          .info('hot_restart request session=$sessionId failed error=$error');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badGateway,
        body: {
          'error': 'hot_restart_failed',
          'message': error.toString(),
        },
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

  /// Write one JSON payload as an SSE event frame.
  ///
  /// Args:
  /// - `response`: Open `text/event-stream` response.
  /// - `event`: Browser-visible event name. The web app listens for
  ///   `bridge_session_event`.
  /// - `data`: JSON-serializable payload written to the SSE `data:` line.
  ///
  /// Returns:
  /// Nothing. The caller decides when to flush because snapshot writes and
  /// change writes happen in different parts of the stream lifecycle.
  ///
  /// Example:
  /// `event=bridge_session_event` and
  /// `data={type: select_widget_mode_changed, payload: {enabled: true}}`
  /// becomes an EventSource `bridge_session_event` message in the browser.
  void _writeSseEvent(
    HttpResponse response, {
    required String event,
    required Map<String, Object?> data,
  }) {
    response.add(utf8.encode('event: $event\ndata: ${jsonEncode(data)}\n\n'));
  }
}
