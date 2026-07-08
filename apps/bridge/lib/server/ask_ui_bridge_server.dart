import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_controller/flutter_app_controller.dart';
import '../chat/chat_session.dart';
import '../device/device_stream.dart';
import '../device/scrcpy_device_stream.dart';
import '../device_control/device_control_protocol.dart';
import '../inspector/flutter_inspector_client.dart';
import '../logging/bridge_logger.dart';
import '../sessions/flutter_device_checker.dart';
import '../sessions/session_store.dart';
import '../snapshots/snapshot_capture.dart';

const int _chatMessageTextLimit = 4000;
const int _selectionCommentTextLimit = 1000;
const int _selectionCommentMetadataLimit = 1000;
const int _selectionCommentBatchLimit = 20;

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
        _flutterDeviceChecker =
            flutterDeviceChecker ?? const FlutterDevicesCommandChecker(),
        _deviceStreamFactory =
            deviceStreamFactory ?? ScrcpyDeviceStreamFactory(),
        _snapshotCapture = snapshotCapture ?? AdbSnapshotCapture().capture,
        _snapshotFileExists =
            snapshotFileExists ?? ((path) => File(path).existsSync()),
        _projectRootExists = projectRootExists ??
            ((projectRoot) => Directory(projectRoot).existsSync()),
        _sessionEventsHeartbeatInterval = sessionEventsHeartbeatInterval,
        _logger = logger ?? BridgeLogger(write: print);

  final SessionStore _sessionStore;
  final FlutterInspectorClient _inspectorClient;
  final FlutterAppController _appController;
  final FlutterDeviceChecker _flutterDeviceChecker;
  final DeviceStreamFactory _deviceStreamFactory;
  final SnapshotCapture _snapshotCapture;
  final bool Function(String path) _snapshotFileExists;
  final bool Function(String projectRoot) _projectRootExists;
  final Duration _sessionEventsHeartbeatInterval;
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
        writeMessage: (chat, text) => chat.appendAgentReply(text),
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
        writeMessage: (chat, text) => chat.appendAgentError(text),
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

    final vmServiceUri = body['vmServiceUri'];
    final projectRoot = body['projectRoot'];
    final deviceId = body['deviceId'];
    final clientId = body['clientId'];

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

    final trimmedProjectRoot = projectRoot.trim();
    if (!_projectRootExists(trimmedProjectRoot)) {
      _logger.info(
        'session create failed error=invalid_project_root '
        'projectRoot=$trimmedProjectRoot',
      );
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'invalid_project_root',
          'message': 'Project root $trimmedProjectRoot does not exist.',
          'projectRoot': trimmedProjectRoot,
        },
      );
      return;
    }

    late final FlutterDeviceCheckResult targetDeviceCheck;
    try {
      targetDeviceCheck = await _flutterDeviceChecker.checkDeviceId(
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

    if (targetDeviceCheck.availability == FlutterDeviceAvailability.notFound) {
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

    if (targetDeviceCheck.availability ==
        FlutterDeviceAvailability.unavailable) {
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
        deviceDisplayName: targetDeviceCheck.device?.displayName ?? '',
        clientId: clientId is String ? clientId : null,
      );
      await _writeJson(
        request.response,
        body: {
          'sessionId': session.id,
          'targetDevice': {
            'id': session.deviceId,
            'displayName': session.deviceDisplayName,
          },
          'readOnly':
              session.isReadOnlyClient(clientId is String ? clientId : null),
        },
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

    final _ParsedChatMessageRequest? parsedMessage =
        _parseChatMessageRequest(body, session);
    if (parsedMessage == null) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'empty_chat_message'},
      );
      return;
    }

    if (parsedMessage.error != null) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': parsedMessage.error},
      );
      return;
    }

    if (parsedMessage.text.length > _chatMessageTextLimit) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'chat_message_too_long'},
      );
      return;
    }

    final ChatMessage? message = session.chat.sendUserMessage(
      text: parsedMessage.text,
      context: parsedMessage.context,
      parts: parsedMessage.parts,
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

  _ParsedChatMessageRequest? _parseChatMessageRequest(
    Map<String, Object?> body,
    BridgeSession session,
  ) {
    final Object? text = body['text'];
    if (text is String) {
      if (text.trim().isEmpty) {
        return null;
      }

      return _ParsedChatMessageRequest(text: text);
    }

    final Object? rawParts = body['parts'];
    if (rawParts is! List<Object?> || rawParts.isEmpty) {
      return null;
    }
    if (rawParts.length > _selectionCommentBatchLimit + 1) {
      return const _ParsedChatMessageRequest.invalid('invalid_chat_parts');
    }

    final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
    String typedText = '';
    int selectionCommentCount = 0;
    int textPartCount = 0;
    for (final rawPart in rawParts) {
      final Map<String, Object?>? part = _normalizeJsonObject(rawPart);
      if (part == null) {
        return const _ParsedChatMessageRequest.invalid('invalid_chat_parts');
      }

      final normalizedPart = _parseChatMessagePart(part, session);
      if (normalizedPart == null) {
        return const _ParsedChatMessageRequest.invalid('invalid_chat_parts');
      }

      if (normalizedPart['type'] == 'text') {
        textPartCount += 1;
        typedText = normalizedPart['text'] as String;
      } else {
        selectionCommentCount += 1;
      }

      parts.add(normalizedPart);
    }

    if (typedText.length > _chatMessageTextLimit ||
        textPartCount > 1 ||
        selectionCommentCount > _selectionCommentBatchLimit) {
      return const _ParsedChatMessageRequest.invalid('invalid_chat_parts');
    }

    final bool hasAttachment = parts.any(
      (part) => part['type'] == 'selection_comment',
    );
    if (!hasAttachment && typedText.trim().isEmpty) {
      return null;
    }

    return _ParsedChatMessageRequest(
      text: typedText,
      context: {'projectRoot': session.projectRoot},
      parts: parts,
    );
  }

  Map<String, Object?>? _parseChatMessagePart(
    Map<String, Object?> part,
    BridgeSession session,
  ) {
    switch (part['type']) {
      case 'text':
        final text = part['text'];
        if (text is! String) {
          return null;
        }
        return {
          'type': 'text',
          'text': text,
        };
      case 'selection_comment':
        final attachment = _normalizeJsonObject(part['attachment']);
        if (attachment == null) {
          return null;
        }
        final normalizedAttachment =
            _parseSelectionCommentAttachment(attachment, session);
        if (normalizedAttachment == null) {
          return null;
        }
        return {
          'type': 'selection_comment',
          'attachment': normalizedAttachment,
        };
    }

    return null;
  }

  Map<String, Object?>? _parseSelectionCommentAttachment(
    Map<String, Object?> attachment,
    BridgeSession session,
  ) {
    final id = attachment['id'];
    final commentText = attachment['commentText'];
    final selectedWidget = _normalizeJsonObject(attachment['selectedWidget']);
    final snapshot = _normalizeJsonObject(attachment['snapshot']);
    if (!_isBoundedNonBlankString(id, _selectionCommentMetadataLimit) ||
        !_isBoundedNonBlankString(commentText, _selectionCommentTextLimit) ||
        selectedWidget == null ||
        snapshot == null) {
      return null;
    }

    final normalizedSelectedWidget = _parseSelectedWidget(selectedWidget);
    final normalizedSnapshot = _parseSelectionCommentSnapshot(
      snapshot,
      session,
    );
    if (normalizedSelectedWidget == null || normalizedSnapshot == null) {
      return null;
    }

    return {
      'id': id,
      'commentText': commentText,
      'selectedWidget': normalizedSelectedWidget,
      'snapshot': normalizedSnapshot,
    };
  }

  Map<String, Object?>? _parseSelectedWidget(Map<String, Object?> widget) {
    final id = widget['id'];
    final displayLabel = widget['displayLabel'];
    if (!_isBoundedNonBlankString(id, _selectionCommentMetadataLimit) ||
        !_isBoundedNonBlankString(
          displayLabel,
          _selectionCommentMetadataLimit,
        )) {
      return null;
    }

    final normalized = <String, Object?>{
      'id': id,
      'displayLabel': displayLabel,
    };
    for (final key in ['sourceLocation', 'visibleText', 'semanticInfo']) {
      final value = widget[key];
      if (value != null) {
        if (!_isBoundedString(value, _selectionCommentTextLimit)) {
          return null;
        }
        normalized[key] = value;
      }
    }
    return normalized;
  }

  Map<String, Object?>? _parseSelectionCommentSnapshot(
    Map<String, Object?> snapshot,
    BridgeSession session,
  ) {
    switch (snapshot['status']) {
      case 'available':
        final path = snapshot['path'];
        if (!_isBoundedNonBlankString(path, _selectionCommentMetadataLimit) ||
            !_snapshotFileExists(path as String) ||
            !session.ownsManagedLocalPath(path)) {
          return null;
        }
        return {
          'status': 'available',
          'path': path,
        };
      case 'unavailable':
        return {'status': 'unavailable'};
    }

    return null;
  }

  bool _isBoundedNonBlankString(Object? value, int limit) {
    if (value is! String) {
      return false;
    }
    return value.trim().isNotEmpty && value.length <= limit;
  }

  bool _isBoundedString(Object? value, int limit) {
    return value is String && value.length <= limit;
  }

  Map<String, Object?>? _normalizeJsonObject(Object? value) {
    if (value is! Map) {
      return null;
    }

    final Map<String, Object?> normalized = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        return null;
      }
      normalized[key] = _normalizeJsonValue(entry.value);
    }
    return normalized;
  }

  Object? _normalizeJsonValue(Object? value) {
    if (value is Map) {
      final Map<String, Object?> normalized = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is String) {
          normalized[key] = _normalizeJsonValue(entry.value);
        }
      }
      return normalized;
    }

    if (value is List) {
      return value.map(_normalizeJsonValue).toList();
    }

    return value;
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
    required ChatMessage Function(ChatSession chat, String text) writeMessage,
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

    final text = body['text'];
    if (text is! String || text.trim().isEmpty) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'empty_chat_message'},
      );
      return;
    }

    if (text.length > 4000) {
      await _writeJson(
        request.response,
        statusCode: HttpStatus.badRequest,
        body: {'error': 'chat_message_too_long'},
      );
      return;
    }

    final ChatMessage message = writeMessage(session.chat, text);
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
    DeviceStream? deviceStream;
    var socketClosed = false;
    var deviceStreamClosed = false;
    Future<void> closeDeviceStream() async {
      final stream = deviceStream;
      if (stream == null || deviceStreamClosed) {
        return;
      }
      deviceStreamClosed = true;
      await stream.close();
    }

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
        final decoded = jsonDecode(message);
        if (decoded is Map<String, Object?>) {
          unawaited(deviceStream?.handleControl(decoded));
        }
      },
      onDone: () async {
        socketClosed = true;
        _activeDeviceSessionIds.remove(sessionId);
        await closeDeviceStream();
        _logger.info('device websocket session=$sessionId close');
      },
      onError: (error) async {
        socketClosed = true;
        _activeDeviceSessionIds.remove(sessionId);
        await closeDeviceStream();
        _logger.info('device websocket session=$sessionId error=$error');
      },
    );
    final streamSink = _WebSocketDeviceStreamSink(
      socket: socket,
      logger: _logger,
      sessionId: sessionId,
    );
    final streamFactory = request.uri.queryParameters['debugVideo'] == 'fixture'
        ? FixtureH264DeviceStreamFactory(chunk: _fixtureH264AnnexBChunk)
        : _deviceStreamFactory;

    try {
      deviceStream = await streamFactory.start(
        session: session,
        sink: streamSink,
      );
      if (socketClosed) {
        await closeDeviceStream();
        return;
      }
      if (request.uri.queryParameters['debugMetadata'] == 'rotation') {
        streamSink.sendMetadata(DeviceMetadata(
          deviceId: session.deviceId,
          screenWidth: 2400,
          screenHeight: 1080,
          maxFps: 60,
          videoCodec: 'h264',
          controlReady: true,
        ));
      }
    } catch (error, stackTrace) {
      _logger.info(
        'device websocket session=$sessionId start_failed '
        'error=$error\nStack trace:\n$stackTrace',
      );
      if (socketClosed) {
        return;
      }
      socket.add(jsonEncode({
        'type': 'error',
        'error': 'device_start_failed',
        'message': 'Device failed to start.',
      }));
      await socket.close();
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

    Timer? heartbeat;
    StreamSubscription<SelectWidgetModeStatus>? selectWidgetSubscription;
    StreamSubscription<ChatSessionEvent>? chatSubscription;
    var streamClosed = false;
    var writeQueue = Future<void>.value();

    Future<void> closeSseStream() async {
      if (streamClosed) {
        return;
      }
      streamClosed = true;
      heartbeat?.cancel();
      await selectWidgetSubscription?.cancel();
      await chatSubscription?.cancel();
      _logger.info('events stream session=$sessionId close');
    }

    Future<void> enqueueSseWrite(void Function() write) {
      final nextWrite = writeQueue.then((_) async {
        if (streamClosed) {
          return;
        }

        try {
          write();
          await request.response.flush();
        } catch (error) {
          _logger.info(
            'events stream session=$sessionId write_failed error=$error',
          );
          await closeSseStream();
        }
      });
      writeQueue = nextWrite.catchError((_) {});
      return nextWrite;
    }

    await enqueueSseWrite(() {
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
    });

    await enqueueSseWrite(() {
      _writeSseEvent(
        request.response,
        event: 'bridge_session_event',
        data: {
          'type': 'chat_snapshot',
          'sessionId': sessionId,
          'payload': {
            'agentStatus': session.chat.snapshot().agentStatus.wireName,
            'messages': session.chat
                .snapshot()
                .messages
                .map((message) => message.toJson())
                .toList(),
          },
        },
      );
    });

    selectWidgetSubscription =
        _inspectorClient.watchSelectWidgetModeStatus(session).listen((status) {
      unawaited(enqueueSseWrite(() {
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
      }));
    });
    chatSubscription = session.chat.events.listen((event) {
      unawaited(enqueueSseWrite(() {
        _writeSseEvent(
          request.response,
          event: 'bridge_session_event',
          data: {
            ...event.toJson(),
            'sessionId': sessionId,
          },
        );
      }));
    });
    heartbeat = Timer.periodic(_sessionEventsHeartbeatInterval, (_) {
      unawaited(enqueueSseWrite(() {
        request.response.add(utf8.encode(': ping\n\n'));
      }));
    });

    request.response.done.whenComplete(() {
      unawaited(closeSseStream());
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

class _WebSocketDeviceStreamSink implements DeviceStreamSink {
  _WebSocketDeviceStreamSink({
    required this.socket,
    required this.logger,
    required this.sessionId,
  });

  final WebSocket socket;
  final BridgeLogger logger;
  final String sessionId;

  @override
  void sendReady(DeviceMetadata metadata) {
    socket.add(jsonEncode({
      'type': 'ready',
      ...metadata.toJson(),
    }));
    logger.info(
      'device websocket session=$sessionId ready '
      'deviceId=${metadata.deviceId} '
      'screenWidth=${metadata.screenWidth} '
      'screenHeight=${metadata.screenHeight}',
    );
  }

  @override
  void sendMetadata(DeviceMetadata metadata) {
    socket.add(jsonEncode({
      'type': 'metadata',
      ...metadata.toJson(),
    }));
    logger.info(
      'device websocket session=$sessionId metadata '
      'deviceId=${metadata.deviceId} '
      'screenWidth=${metadata.screenWidth} '
      'screenHeight=${metadata.screenHeight}',
    );
  }

  @override
  void sendVideoChunk(List<int> bytes) {
    socket.add(bytes);
  }

  @override
  void fail(String error, String message) {
    socket.add(jsonEncode({
      'type': 'error',
      'error': error,
      'message': message,
    }));
  }

  @override
  void log(String message) {
    logger.info('device websocket session=$sessionId $message');
  }

  @override
  Future<void> close() async {
    await socket.close();
  }
}

class _ParsedChatMessageRequest {
  const _ParsedChatMessageRequest({
    required this.text,
    this.context = const <String, Object?>{},
    this.parts = const <Map<String, Object?>>[],
  }) : error = null;

  const _ParsedChatMessageRequest.invalid(String error)
      : text = '',
        context = const <String, Object?>{},
        parts = const <Map<String, Object?>>[],
        error = error;

  final String text;
  final Map<String, Object?> context;
  final List<Map<String, Object?>> parts;
  final String? error;
}

/// Single-frame Annex B H.264 byte fixture for the Device WebSocket shell.
///
/// The bytes are a 16x16 Constrained Baseline IDR frame generated by ffmpeg.
/// They prove that the bridge can send decodable binary video bytes over the
/// same WebSocket as JSON protocol messages.
final List<int> _fixtureH264AnnexBChunk = [
  ...base64Decode(
    'AAAAAWdCwArd7ARAAAADAEAAAAMAo8SJ4AAAAAFozg/IAAABBgX//03cRem95tlIt5Ys2CDZI+7veDI2NCAtIGNvcmUgMTY1IHIzMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9MCByZWY9MSBkZWJsb2NrPTA6MDowIGFuYWx5c2U9MDowIG1lPWRpYSBzdWJtZT0wIHBzeT0xIHBzeV9yZD0xLjAwOjAuMDAgbWl4ZWRfcmVmPTAgbWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0wIDh4OGRjdD0wIGNxbT0wIGRlYWR6b25lPTIxLDExIGZhc3RfcHNraXA9MSBjaHJvbWFfcXBfb2Zmc2V0PTAgdGhyZWFkcz0xIGxvb2thaGVhZF90aHJlYWRzPTEgc2xpY2VkX3RocmVhZHM9MCBucj0wIGRlY2ltYXRlPTEgaW50ZXJsYWNlZD0wIGJsdXJheV9jb21wYXQ9MCBjb25zdHJhaW5lZF9pbnRyYT0wIGJmcmFtZXM9MCB3ZWlnaHRwPTAga2V5aW50PTEga2V5aW50X21pbj0xIHNjZW5lY3V0PTAgaW50cmFfcmVmcmVzaD0wIHJjPWNyZiBtYnRyZWU9MCBjcmY9MjMuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89MS40MCBhcT0wAIAAAAFliIQ6JigACQLg',
  ),
  0x00,
  0x00,
  0x01,
  0x09,
  0xf0,
];
