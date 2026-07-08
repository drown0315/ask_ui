import 'dart:async';

import '../chat/chat_session.dart';
import '../inspector/flutter_inspector_client.dart';
import '../logging/bridge_logger.dart';
import 'session_store.dart';

class BridgeSessionEventStream {
  BridgeSessionEventStream({
    required FlutterInspectorClient inspectorClient,
    required Duration heartbeatInterval,
    required BridgeLogger logger,
  })  : _inspectorClient = inspectorClient,
        _heartbeatInterval = heartbeatInterval,
        _logger = logger;

  final FlutterInspectorClient _inspectorClient;
  final Duration _heartbeatInterval;
  final BridgeLogger _logger;

  Future<BridgeSessionEventStreamResult> open({
    required BridgeSession session,
    required BridgeSessionEventTransport transport,
  }) async {
    final sessionId = session.id;
    late final SelectWidgetModeStatus snapshot;
    try {
      snapshot = await _inspectorClient.getSelectWidgetModeStatus(session);
    } catch (error) {
      _logger.info('events stream session=$sessionId failed error=$error');
      return BridgeSessionEventStreamFailure(
        error: 'session_events_failed',
        message: error.toString(),
      );
    }

    transport.start();
    _logger.info('events stream session=$sessionId open');

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
          await transport.flush();
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
      transport.writeEvent(
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
      transport.writeEvent(
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
        transport.writeEvent(
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
        transport.writeEvent(
          event: 'bridge_session_event',
          data: {
            ...event.toJson(),
            'sessionId': sessionId,
          },
        );
      }));
    });
    heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      unawaited(enqueueSseWrite(() {
        transport.writeComment('ping');
      }));
    });

    transport.done.whenComplete(() {
      unawaited(closeSseStream());
    });
    return const BridgeSessionEventStreamOpened();
  }
}

abstract interface class BridgeSessionEventTransport {
  Future<void> get done;

  void start();

  void writeEvent({
    required String event,
    required Map<String, Object?> data,
  });

  void writeComment(String comment);

  Future<void> flush();
}

sealed class BridgeSessionEventStreamResult {
  const BridgeSessionEventStreamResult();
}

class BridgeSessionEventStreamOpened extends BridgeSessionEventStreamResult {
  const BridgeSessionEventStreamOpened();
}

class BridgeSessionEventStreamFailure extends BridgeSessionEventStreamResult {
  const BridgeSessionEventStreamFailure({
    required this.error,
    required this.message,
  });

  final String error;
  final String message;
}
