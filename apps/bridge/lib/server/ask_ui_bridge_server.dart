import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_controller/flutter_app_controller.dart';
import '../chat/chat_ingress.dart';
import '../chat/chat_session.dart';
import '../device/device_stream.dart';
import '../device/device_web_socket_session.dart';
import '../device/scrcpy_device_stream.dart';
import '../inspector/flutter_inspector_client.dart';
import '../logging/bridge_logger.dart';
import '../sessions/bridge_session_creator.dart';
import '../sessions/bridge_session_event_stream.dart';
import '../sessions/flutter_device_checker.dart';
import '../sessions/session_store.dart';
import '../snapshots/snapshot_capture.dart';

const int _agentChatMessageTextLimit = 4000;

class AskUiBridgeServer {
  AskUiBridgeServer({
    required SessionStore sessionStore,
    required FlutterInspectorClient inspectorClient,
    required FlutterAppController appController,
    FlutterDeviceChecker? flutterDeviceChecker,
    DeviceStreamFactory? deviceStreamFactory,
    SnapshotCapture? snapshotCapture,
    bool Function(String path)? snapshotFileExists,
    bool Function(String projectRoot)? projectRootExists,
    Duration sessionEventsHeartbeatInterval = const Duration(seconds: 15),
    BridgeLogger? logger,
  })  : _sessionStore = sessionStore,
        _inspectorClient = inspectorClient,
        _appController = appController,
        _sessionCreator = BridgeSessionCreator(
          sessionStore: sessionStore,
          flutterDeviceChecker:
              flutterDeviceChecker ?? const FlutterDevicesCommandChecker(),
          projectRootExists: projectRootExists ??
              ((projectRoot) => Directory(projectRoot).existsSync()),
          log: (logger ?? BridgeLogger(write: print)).info,
        ),
        _deviceWebSocketSession = DeviceWebSocketSession(
          deviceStreamFactory:
              deviceStreamFactory ?? ScrcpyDeviceStreamFactory(),
          logger: logger ?? BridgeLogger(write: print),
        ),
        _snapshotCapture = snapshotCapture ?? AdbSnapshotCapture().capture,
        _snapshotFileExists =
            snapshotFileExists ?? ((path) => File(path).existsSync()),
        _chatIngress = ChatIngress(
          snapshotFileExists:
              snapshotFileExists ?? ((path) => File(path).existsSync()),
        ),
        _sessionEventStream = BridgeSessionEventStream(
          inspectorClient: inspectorClient,
          heartbeatInterval: sessionEventsHeartbeatInterval,
          logger: logger ?? BridgeLogger(write: print),
        ),
        _logger = logger ?? BridgeLogger(write: print);

  final SessionStore _sessionStore;
  final FlutterInspectorClient _inspectorClient;
  final FlutterAppController _appController;
  final BridgeSessionCreator _sessionCreator;
  final DeviceWebSocketSession _deviceWebSocketSession;
  final SnapshotCapture _snapshotCapture;
  final bool Function(String path) _snapshotFileExists;
  final ChatIngress _chatIngress;
  final BridgeSessionEventStream _sessionEventStream;
  final BridgeLogger _logger;
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
    await _sessionStore.destroyAll();
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
        request.uri.pathSegments[3] == 'chat') {
      await _getChat(request);
      return;
    }

    if (request.method == 'POST' &&
        request.uri.pathSegments.length == 4 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'snapshots') {
      await _captureSnapshot(request);
      return;
    }

    if (request.method == 'POST' &&
        request.uri.pathSegments.length == 5 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'chat' &&
        request.uri.pathSegments[4] == 'messages') {
      await _sendChatMessage(request);
      return;
    }

    if (request.method == 'GET' &&
        request.uri.pathSegments.length == 5 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'agent' &&
        request.uri.pathSegments[4] == 'poll') {
      await _pollAgent(request);
      return;
    }

    if (request.method == 'POST' &&
        request.uri.pathSegments.length == 5 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'agent' &&
        request.uri.pathSegments[4] == 'reply') {
      await _writeAgentChatMessage(
        request,
        writeMessage: (chat, text, replyToMessageId) {
          return chat.appendAgentReply(
            text,
            replyToMessageId: replyToMessageId,
          );
        },
      );
      return;
    }

    if (request.method == 'POST' &&
        request.uri.pathSegments.length == 5 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'sessions' &&
        request.uri.pathSegments[3] == 'agent' &&
        request.uri.pathSegments[4] == 'error') {
      await _writeAgentChatMessage(
        request,
        writeMessage: (chat, text, replyToMessageId) {
          return chat.appendAgentError(
            text,
            replyToMessageId: replyToMessageId,
          );
        },
      );
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

    final BridgeSessionCreationResult result =
        await _sessionCreator.create(body);
    switch (result) {
      case BridgeSessionCreationSuccess():
        final BridgeSession session = result.session;
        await _writeJson(
          request.response,
          body: {
            'sessionId': session.id,
            'targetDevice': {
              'id': session.deviceId,
              'displayName': session.deviceDisplayName,
            },
            'readOnly': result.readOnly,
          },
        );
      case BridgeSessionCreationFailure():
        await _writeJson(
          request.response,
          statusCode: HttpStatus.badRequest,
          body: _sessionCreationErrorBody(result),
        );
    }
  }

  Map<String, Object?> _sessionCreationErrorBody(
    BridgeSessionCreationFailure failure,
  ) {
    return {
      'error': failure.error,
      if (failure.message != null) 'message': failure.message,
      if (failure.deviceId != null) 'deviceId': failure.deviceId,
      if (failure.projectRoot != null) 'projectRoot': failure.projectRoot,
      if (failure.expectedDeviceId != null)
        'expectedDeviceId': failure.expectedDeviceId,
      if (failure.requestedDeviceId != null)
        'requestedDeviceId': failure.requestedDeviceId,
    };
  }

  /// Return the current Chat state for one Bridge Session.
  ///
  /// This endpoint gives the web app an initial Chat History and Agent Status
  /// snapshot before it starts consuming later updates from the existing
  /// session events stream.
  Future<void> _getChat(HttpRequest request) async {
    final String sessionId = request.uri.pathSegments[2];
    final BridgeSession? session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('chat request session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    final String? clientId = request.uri.queryParameters['clientId'];
    await _writeJson(
      request.response,
      body: session.chat.snapshot().toJson(
            readOnly: session.isReadOnlyClient(clientId),
          ),
    );
  }

  /// Send one Chat message to the currently waiting Agent Session.
  ///
  /// The request can be a plain `text` message or ordered `parts` containing
  /// Selection Comment attachments followed by an optional typed text part.
  ///
  /// This endpoint intentionally has no offline queue. If no Agent Session is
  /// actively polling, the browser keeps its composer text and can try again
  /// once Agent Status returns to `agent_ready`.
  Future<void> _sendChatMessage(HttpRequest request) async {
    final String sessionId = request.uri.pathSegments[2];
    final BridgeSession? session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('chat send session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    late final Map<String, Object?> body;
    try {
      final String rawBody = await utf8.decodeStream(request);
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

    final ChatIngressMessage parsedMessage =
        _chatIngress.parseMessage(body, session);
    if (parsedMessage is RejectedChatIngressMessage) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': parsedMessage.error},
      );
      return;
    }
    final acceptedMessage = parsedMessage as AcceptedChatIngressMessage;

    final ChatMessage? message = session.chat.sendUserMessage(
      text: acceptedMessage.text,
      context: acceptedMessage.context,
      parts: acceptedMessage.parts,
    );
    if (message == null) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.conflict,
        body: {'error': 'agent_not_ready'},
      );
      return;
    }

    await _writeJson(
      request.response,
      body: {
        'status': 'ok',
        'message': message.toJson(),
      },
    );
  }

  Future<void> _captureSnapshot(HttpRequest request) async {
    final String sessionId = request.uri.pathSegments[2];
    final BridgeSession? session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('snapshot capture session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    late final Map<String, Object?> body;
    try {
      final String rawBody = await utf8.decodeStream(request);
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

    final commentId = body['commentId'];
    final format = body['format'];
    final scope = body['scope'];
    final maxSizeBytes = body['maxSizeBytes'];

    if (commentId is! String || commentId.trim().isEmpty) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'missing_comment_id'},
      );
      return;
    }

    if (format != 'png' || scope != 'full_device' || maxSizeBytes is! int) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'invalid_snapshot_request'},
      );
      return;
    }

    final SnapshotCaptureResult result = await _snapshotCapture(
      SnapshotCaptureRequest(
        session: session,
        commentId: commentId.trim(),
        maxSizeBytes: maxSizeBytes,
      ),
    );

    if (!result.isAvailable ||
        result.mimeType != 'image/png' ||
        result.sizeBytes > maxSizeBytes ||
        !_snapshotFileExists(result.path) ||
        !session.ownsManagedLocalPath(result.path)) {
      await _writeJson(
        request.response,
        body: {'status': 'unavailable'},
      );
      return;
    }

    await _writeJson(
      request.response,
      body: {
        'status': 'ok',
        'snapshot': {
          'path': result.path,
          'mimeType': result.mimeType,
          'sizeBytes': result.sizeBytes,
        },
      },
    );
  }

  /// Wait for the next Chat message for the launching Agent Session.
  ///
  /// The normal agent loop leaves `timeoutMs` unset and waits indefinitely.
  /// Tests and debugging clients may pass `timeoutMs` to get a bounded response.
  Future<void> _pollAgent(HttpRequest request) async {
    final String sessionId = request.uri.pathSegments[2];
    final BridgeSession? session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('agent poll session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    final Duration? timeout = _parseOptionalTimeout(
      request.uri.queryParameters['timeoutMs'],
    );
    var clientDisconnected = false;
    var responseWritten = false;
    Timer? disconnectHeartbeat;
    void markClientDisconnected() {
      if (responseWritten || clientDisconnected) {
        return;
      }

      clientDisconnected = true;
      disconnectHeartbeat?.cancel();
      session.chat.cancelAgentWait();
    }

    request.response.done.whenComplete(() {
      markClientDisconnected();
    });

    try {
      final Future<AgentPollResult> poll = session.chat.waitForAgentMessage(
        timeout: timeout,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write('\n');
      await request.response.flush();
      disconnectHeartbeat = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) {
          unawaited(
            (() async {
              try {
                request.response.write('\n');
                await request.response.flush();
              } catch (_) {
                markClientDisconnected();
              }
            })(),
          );
        },
      );

      final AgentPollResult result = await poll;
      disconnectHeartbeat.cancel();
      if (clientDisconnected) {
        return;
      }

      responseWritten = true;
      request.response.write(jsonEncode(result.toJson()));
      await request.response.close();
    } on AgentPollAlreadyActive {
      responseWritten = true;
      await _writeJson(
        request.response,
        statusCode: HttpStatus.conflict,
        body: {'error': 'agent_poll_already_active'},
      );
    }
  }

  Duration? _parseOptionalTimeout(String? timeoutMs) {
    if (timeoutMs == null || timeoutMs.isEmpty) {
      return null;
    }

    final int? milliseconds = int.tryParse(timeoutMs);
    if (milliseconds == null || milliseconds < 0) {
      return null;
    }

    return Duration(milliseconds: milliseconds);
  }

  /// Store one agent-authored Chat History message.
  ///
  /// The caller chooses whether the message is a normal `agent` reply or a
  /// command-level `system` error. Both share the same plain text body contract.
  Future<void> _writeAgentChatMessage(
    HttpRequest request, {
    required ChatMessage Function(
      ChatSession chat,
      String text,
      String? replyToMessageId,
    ) writeMessage,
  }) async {
    final String sessionId = request.uri.pathSegments[2];
    final BridgeSession? session = _sessionStore.find(sessionId);

    if (session == null) {
      _logger.info('agent write session=$sessionId session_not_found');
      await _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {'error': 'session_not_found'},
      );
      return;
    }

    late final Map<String, Object?> body;
    try {
      final String rawBody = await utf8.decodeStream(request);
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

    final Object? text = body['text'];
    if (text is! String || text.trim().isEmpty) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'empty_chat_message'},
      );
      return;
    }

    if (text.length > _agentChatMessageTextLimit) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'chat_message_too_long'},
      );
      return;
    }

    final Object? replyToMessageId = body['replyToMessageId'];
    if (replyToMessageId != null && replyToMessageId is! String) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'invalid_reply_to_message'},
      );
      return;
    }

    late final ChatMessage message;
    try {
      message = writeMessage(session.chat, text, replyToMessageId as String?);
    } on InvalidReplyToMessage {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'invalid_reply_to_message'},
      );
      return;
    }

    await _writeJson(
      request.response,
      body: {
        'status': 'ok',
        'message': message.toJson(),
      },
    );
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
    await _deviceWebSocketSession.open(
      session: session,
      transport: _IoDeviceWebSocketTransport(socket),
      debugVideoFixture: request.uri.queryParameters['debugVideo'] == 'fixture',
      debugMetadataRotation:
          request.uri.queryParameters['debugMetadata'] == 'rotation',
    );
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
  /// 2. writes Select Widget mode and Chat snapshots as initial SSE events
  /// 3. forwards later Select Widget mode changes observed by the Inspector
  ///    client
  /// 4. forwards later Chat History and Agent Status changes from the Bridge
  ///    Session Chat state
  /// 5. clears subscriptions and the heartbeat when the browser disconnects
  ///
  /// Args:
  /// - `request`: GET request whose path is
  ///   `/api/sessions/{sessionId}/events`. Unknown sessions receive a JSON
  ///   `session_not_found` response instead of an SSE stream.
  ///
  /// Returns:
  /// A long-lived `text/event-stream` response. Initial events include
  /// `select_widget_mode_snapshot` and `chat_snapshot`; later updates include
  /// `select_widget_mode_changed`, `agent_status_changed`, and
  /// `chat_history_changed`.
  ///
  /// Example:
  /// A browser subscribing to `session-1` first receives cached Select Widget
  /// and Chat state, then receives another event when DevTools toggles Select
  /// Widget mode or Chat state changes.
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

    final result = await _sessionEventStream.open(
      session: session,
      transport: _HttpSessionEventTransport(request.response),
    );
    if (result is BridgeSessionEventStreamFailure) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badGateway,
        body: {
          'error': result.error,
          'message': result.message,
        },
      );
    }
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
}

class _HttpSessionEventTransport implements BridgeSessionEventTransport {
  const _HttpSessionEventTransport(this.response);

  final HttpResponse response;

  @override
  Future<void> get done => response.done;

  @override
  void start() {
    response.statusCode = HttpStatus.ok;
    response.bufferOutput = false;
    response.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.transferEncodingHeader, 'chunked')
      ..set(HttpHeaders.connectionHeader, 'keep-alive');
  }

  @override
  void writeEvent({
    required String event,
    required Map<String, Object?> data,
  }) {
    response.add(utf8.encode('event: $event\ndata: ${jsonEncode(data)}\n\n'));
  }

  @override
  void writeComment(String comment) {
    response.add(utf8.encode(': $comment\n\n'));
  }

  @override
  Future<void> flush() {
    return response.flush();
  }
}

class _IoDeviceWebSocketTransport implements DeviceWebSocketTransport {
  const _IoDeviceWebSocketTransport(this.socket);

  final WebSocket socket;

  @override
  Stream<dynamic> get incoming => socket;

  @override
  void add(Object? message) {
    socket.add(message);
  }

  @override
  Future<void> close() async {
    await socket.close();
  }
}
